class GeneratedDocument < ApplicationRecord
  STATUSES = %w[pending ready failed].freeze

  belongs_to :matter
  belongs_to :document_template
  has_one_attached :pdf
  has_many :communications, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  def ready? = status == "ready"
  def filename = "#{matter.reference}-#{template_key}-v#{version}.pdf"

  def as_api_json
    {
      id:, template_key:, template_version:, version:, status:, error:, attempts:,
      inputs_digest:, short_digest: inputs_digest.first(12),
      generated_at: generated_at&.iso8601, created_at: created_at.iso8601,
      pdf_url: (pdf.attached? ? Rails.application.routes.url_helpers.rails_blob_path(pdf, disposition: "inline", only_path: true) : nil)
    }
  end
end
