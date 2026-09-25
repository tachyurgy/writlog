# Asks for a document. Idempotent: the same matter + template version + merge
# inputs always returns the same GeneratedDocument row, no matter how many
# times or how concurrently it is called. Enforced by the unique index
# index_generated_documents_idempotency; the matter row lock only keeps the
# per-template version counter gap-free.
class DocumentRequest
  Result = Data.define(:document, :created, :requeued)
  class Unresolved < StandardError; end

  def self.call(matter, template) = new(matter, template).call

  def initialize(matter, template)
    @matter = matter
    @template = template
  end

  def call
    resolved = MergeFields.resolve(@template, @matter)
    raise Unresolved, "missing merge fields: #{resolved['missing'].join(', ')}" if resolved["missing"].any?

    digest = MergeFields.digest(@template, resolved["values"])
    result = find_or_create(digest, resolved["values"])
    # Enqueue only after the row is committed. A duplicate enqueue would still be
    # harmless (the job is idempotent) but it would be wasted work.
    GenerateDocumentJob.perform_later(result.document.id) if result.created || result.requeued
    result
  end

  private

  def find_or_create(digest, values)
    existing = lookup(digest)
    return Result.new(existing, false, false) if existing && existing.status != "failed"

    GeneratedDocument.transaction(requires_new: true) do
      @matter.lock!
      if (existing = lookup(digest))
        # A failed render is retried by asking again: same row, back to pending.
        # The status check runs under the matter lock, so only one caller requeues.
        requeue = existing.status == "failed"
        existing.update!(status: "pending", error: nil) if requeue
        Result.new(existing, false, requeue)
      else
        version = GeneratedDocument.where(matter_id: @matter.id, template_key: @template.key).maximum(:version).to_i + 1
        doc = GeneratedDocument.create!(
          matter: @matter, document_template: @template, template_key: @template.key,
          template_version: @template.version, version:, inputs_digest: digest, inputs: values
        )
        Result.new(doc, true, false)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # Another writer won the race outside our lock (e.g. a second app process
    # that skipped the lock). The index decided; return the winner.
    Result.new(lookup(digest) || raise, false, false)
  end

  def lookup(digest)
    GeneratedDocument.find_by(matter_id: @matter.id, document_template_id: @template.id, inputs_digest: digest)
  end
end
