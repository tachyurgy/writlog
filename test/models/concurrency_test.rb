require "test_helper"

# Real threads, real connections, real Postgres locks. Transactional tests are
# off so each thread sees committed rows; cleanup is manual.
class ConcurrencyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  THREADS = 8

  setup do
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.establish_connection(cfg.except(:pool, :max_connections).merge(max_connections: THREADS + 6))
  end

  teardown do
    ActiveRecord::Base.connection.execute(<<~SQL)
      ALTER TABLE matter_events DISABLE TRIGGER matter_events_no_update_delete;
      TRUNCATE communications, generated_documents, document_templates, matter_events, matters,
               active_storage_attachments, active_storage_blobs, active_storage_variant_records RESTART IDENTITY CASCADE;
      ALTER TABLE matter_events ENABLE TRIGGER matter_events_no_update_delete;
    SQL
  end

  def race(n = THREADS)
    gate = Queue.new
    threads = Array.new(n) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          yield i
        end
      end
    end
    sleep 0.05
    n.times { gate << :go }
    threads.map(&:value)
  end

  test "N concurrent requests for the same document create exactly one row and one job" do
    3.times do |round|
      matter = build_matter(ref: "RACE-#{round}")
      template = build_template(version: round + 1)
      results = race { DocumentRequest.call(Matter.find(matter.id), template) }
      assert_equal 1, GeneratedDocument.where(matter_id: matter.id).count
      assert_equal 1, results.map { |r| r.document.id }.uniq.size
      assert_equal 1, results.count(&:created), "exactly one caller reports created"
    end
    assert_equal 3, enqueued_jobs.count { |j| j["job_class"] == "GenerateDocumentJob" }
  end

  test "the unique index alone rejects a duplicate (no lock involved)" do
    matter = build_matter
    template = build_template
    attrs = { matter_id: matter.id, document_template_id: template.id, template_key: template.key,
              template_version: 1, inputs_digest: "abc", inputs: {} }
    GeneratedDocument.create!(attrs.merge(version: 1))
    assert_raises(ActiveRecord::RecordNotUnique) { GeneratedDocument.create!(attrs.merge(version: 2)) }
  end

  test "the same job run concurrently renders once and logs once" do
    matter = build_matter
    doc = DocumentRequest.call(matter, build_template).document
    race { GenerateDocumentJob.perform_now(doc.id) }
    doc.reload
    assert doc.ready?
    assert_equal 1, doc.attempts
    assert_equal 1, ActiveStorage::Attachment.where(record: doc).count
    assert_equal 1, MatterEvent.where(matter_id: matter.id, kind: "document_generated").count
    assert matter.reload.consistent_with_log?
  end

  test "concurrent appends keep seq gap-free and the projection exact" do
    matter = build_matter
    race { |i| Workflow.append!(Matter.find(matter.id), "payment_received", effective_on: Date.new(2026, 2, 1), payload: { amount_cents: 100 + i }) }
    matter.reload
    assert_equal (1..THREADS + 1).to_a, matter.matter_events.pluck(:seq)
    assert_equal (0...THREADS).sum { |i| 100 + i }, matter.paid_cents
    assert matter.consistent_with_log?
  end
end
