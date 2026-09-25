# Templates are immutable once published: an edit is a new row with version+1,
# so a generated document always points at the exact text it was merged from.
class DocumentTemplate < ApplicationRecord
  FIELD = /\{\{\s*([a-z_]+)\s*\}\}/

  has_many :generated_documents, dependent: :restrict_with_exception
  validates :key, :name, :body, :version, presence: true
  before_update { raise ActiveRecord::ReadOnlyRecord, "publish a new version instead" if body_changed? && generated_documents.exists? }

  scope :latest, -> { where("version = (SELECT MAX(version) FROM document_templates t2 WHERE t2.key = document_templates.key)").order(:name) }

  def fields = body.scan(FIELD).flatten.uniq
end
