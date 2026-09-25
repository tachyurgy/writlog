class EventsController < ApplicationController
  before_action :find_matter

  PAYLOAD_KEYS = %w[cure_days index_number method proof_filed_on amount recipient note].freeze

  def create
    kind = params.require(:kind)
    effective_on = Date.parse(params[:effective_on].presence || Date.current.iso8601)
    payload = params.permit(*PAYLOAD_KEYS).to_h
    if (amount = payload.delete("amount")).present?
      payload["amount_cents"] = (amount.to_s.delete(",$").to_d * 100).to_i
    end
    event = Workflow.append!(@matter, kind, effective_on:, payload:, actor: "web")
    redirect_to matter_path(@matter, anchor: "event-#{event.seq}"), notice: "Recorded #{kind.humanize.downcase} (event ##{event.seq})."
  rescue Workflow::InvalidTransition, Date::Error, ArgumentError => e
    redirect_to matter_path(@matter), alert: "Rejected: #{e.message}"
  end
end
