class CommunicationsController < ApplicationController
  before_action :find_matter

  def create
    attrs = params.require(:communication).permit(:channel, :direction, :counterparty, :subject, :body, :generated_document_id)
    attrs[:occurred_at] = Time.current
    attrs[:generated_document_id] = nil unless @matter.generated_documents.exists?(id: attrs[:generated_document_id])
    Communication.log!(@matter, attrs)
    redirect_to matter_path(@matter, anchor: "comms"), notice: "Communication logged."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to matter_path(@matter, anchor: "comms"), alert: e.message
  end
end
