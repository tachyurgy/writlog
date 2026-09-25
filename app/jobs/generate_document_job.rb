# Renders one GeneratedDocument. Safe to run any number of times, in parallel,
# on any ActiveJob backend: the row lock serializes concurrent runs, a ready
# document is a no-op, and the matter log entry is guarded by a unique partial
# index (index_matter_events_one_per_document).
class GenerateDocumentJob < ApplicationJob
  queue_as :documents
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    GeneratedDocument.where(id: job.arguments.first).update_all(status: "failed", error: error.message.truncate(500))
  end

  def perform(document_id)
    doc = GeneratedDocument.find(document_id)
    doc.with_lock do
      return if doc.ready?

      doc.increment!(:attempts)
      template = doc.document_template
      values = doc.inputs
      doc.rendered_html = DocumentRenderer.html(template.body, values)
      bytes = DocumentRenderer.pdf(template.name, template.body, values,
                                   footer: "#{doc.matter.reference}  |  #{template.key} v#{template.version}  |  doc v#{doc.version}  |  #{doc.inputs_digest.first(12)}")
      # Upload synchronously so "ready" never points at a file that failed to land.
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: doc.filename,
                                                    content_type: "application/pdf")
      doc.pdf.attach(blob)
      doc.update!(status: "ready", error: nil, generated_at: Time.current)

      matter = doc.matter
      Workflow.append!(matter, "document_generated",
                       effective_on: Date.current, clamp: true,
                       payload: { document_id: doc.id.to_s, template_key: doc.template_key, version: doc.version },
                       actor: "generate_document_job")
    end
  end
end
