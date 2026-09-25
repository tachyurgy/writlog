# JSON API behind the React document composer.
class DocumentsController < ApplicationController
  before_action :find_matter, except: :show

  def index
    render json: { documents: @matter.generated_documents.map(&:as_api_json) }
  end

  def preview
    template = DocumentTemplate.find(params.require(:template_id))
    resolved = MergeFields.resolve(template, @matter)
    digest = resolved["missing"].empty? ? MergeFields.digest(template, resolved["values"]) : nil
    existing = digest && @matter.generated_documents.find_by(document_template: template, inputs_digest: digest)
    render json: {
      template: { id: template.id, key: template.key, version: template.version, name: template.name, fields: template.fields },
      values: resolved["values"], missing: resolved["missing"], inputs_digest: digest,
      html: DocumentRenderer.html(template.body, template.fields.index_with { |f| resolved["values"][f] || "{{#{f}}}" }),
      existing: existing&.as_api_json
    }
  end

  def create
    template = DocumentTemplate.find(params.require(:template_id))
    result = DocumentRequest.call(@matter, template)
    render json: { created: result.created, document: result.document.as_api_json },
           status: result.created ? :created : :ok
  rescue DocumentRequest::Unresolved => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    doc = GeneratedDocument.find(params[:id])
    respond_to do |f|
      f.json { render json: doc.as_api_json }
      f.html { @document = doc }
    end
  end
end
