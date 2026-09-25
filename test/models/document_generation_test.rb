require "test_helper"

class DocumentGenerationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "same inputs return the same document and enqueue one job" do
    m = build_matter
    t = build_template
    first = DocumentRequest.call(m, t)
    second = DocumentRequest.call(m.reload, t)
    assert first.created
    refute second.created
    assert_equal first.document.id, second.document.id
    assert_enqueued_jobs 1, only: GenerateDocumentJob
  end

  test "changed inputs produce a new version, history kept" do
    m = build_matter
    t = build_template
    v1 = DocumentRequest.call(m, t).document
    Workflow.append!(m, "payment_received", effective_on: Date.new(2026, 2, 1), payload: { amount_cents: 250_000 })
    v2 = DocumentRequest.call(m.reload, t).document
    assert_equal [1, 2], [v1.version, v2.version]
    refute_equal v1.inputs_digest, v2.inputs_digest
    assert_equal "$7,500.00", v2.inputs["balance"]
  end

  test "missing merge fields block generation" do
    m = build_matter
    t = build_template(body: "X\n\nIndex {{index_number}}")
    assert_raises(DocumentRequest::Unresolved) { DocumentRequest.call(m, t) }
    assert_equal 0, GeneratedDocument.count
  end

  test "the job renders a PDF, logs once, and is a no-op when re-run" do
    m = build_matter
    doc = DocumentRequest.call(m, build_template).document
    GenerateDocumentJob.perform_now(doc.id)
    GenerateDocumentJob.perform_now(doc.id)
    doc.reload
    assert doc.ready?
    assert_equal 1, doc.attempts
    assert doc.pdf.download.start_with?("%PDF")
    assert_equal 1, m.matter_events.where(kind: "document_generated").count
    # Generating must not change the matter's inputs, so asking again is still idempotent.
    refute DocumentRequest.call(m.reload, doc.document_template).created
    assert m.consistent_with_log?
  end

  test "merge values are HTML-escaped in the preview" do
    html = DocumentRenderer.html("T\n\n{{debtor_name}}", { "debtor_name" => "<script>x</script>" })
    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
  end
end
