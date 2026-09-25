require "test_helper"

class FlowsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @matter = build_matter(ref: "WL-TEST-1")
    @template = build_template
  end

  test "pages render" do
    get root_path
    assert_response :success
    assert_includes response.body, "WL-TEST-1"
    get matter_path(@matter)
    assert_response :success
    assert_includes response.body, "projection = replay of 1 events"
    assert_includes response.body, "Example Debtor &lt;Corp&gt;"
    get deadline_calculator_path(method: "substituted", served_on: "2026-08-28", proof_filed_on: "2026-09-01")
    assert_response :success
    assert_includes response.body, "Tuesday, October 13, 2026"
    get how_it_works_path
    assert_response :success
  end

  test "POST twice returns 201 then 200 with the same document, and one job" do
    post matter_documents_path(@matter), params: { template_id: @template.id }, as: :json
    assert_response :created
    first = response.parsed_body
    post matter_documents_path(@matter), params: { template_id: @template.id }, as: :json
    assert_response :ok
    assert_equal first.dig("document", "id"), response.parsed_body.dig("document", "id")
    assert_enqueued_jobs 1, only: GenerateDocumentJob

    perform_enqueued_jobs
    get document_path(first.dig("document", "id"), format: :json)
    assert_equal "ready", response.parsed_body["status"]
    assert_match %r{/rails/active_storage/}, response.parsed_body["pdf_url"]
  end

  test "preview reports missing fields and the composer cannot generate" do
    t = build_template(key: "restraining_notice", body: "R\n\n{{judgment_amount}}")
    get preview_matter_documents_path(@matter, template_id: t.id), as: :json
    assert_equal ["judgment_amount"], response.parsed_body["missing"]
    post matter_documents_path(@matter), params: { template_id: t.id }, as: :json
    assert_response :unprocessable_entity
  end

  test "event form rejects an illegal transition without writing" do
    post matter_events_path(@matter), params: { kind: "judgment_entered", amount: "100" }
    assert_redirected_to matter_path(@matter)
    assert_match "Rejected", flash[:alert]
    assert_equal 1, @matter.reload.events_count
  end

  test "event form records service and computes the answer deadline" do
    post matter_events_path(@matter), params: { kind: "suit_filed", effective_on: "2026-06-01", index_number: "1/2026" }
    post matter_events_path(@matter), params: { kind: "served", effective_on: "2026-06-08", method: "personal" }
    assert_equal Date.new(2026, 6, 29), @matter.reload.answer_due_on
  end

  test "logging a communication appends to the event log" do
    post matter_communications_path(@matter), params: { communication: { channel: "phone", direction: "inbound", counterparty: "Debtor", subject: "Called" } }
    assert_equal 1, @matter.communications.count
    assert_equal "communication_logged", @matter.matter_events.last.kind
  end

  test "open a matter from the form" do
    post matters_path, params: { matter: { client_name: "A LLC", debtor_name: "B Inc.", county: "Kings", principal: "12,500.50" } }
    m = Matter.order(:id).last
    assert_redirected_to matter_path(m)
    assert_equal 1_250_050, m.principal_cents
  end
end
