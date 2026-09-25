class MattersController < ApplicationController
  before_action :find_matter, only: :show

  def index
    @matters = Matter.by_deadline
    @state_counts = Matter.group(:state).count
  end

  def show
    @events = @matter.matter_events.to_a
    @consistent = Workflow.replay(@events) == @matter.projection
    @communications = @matter.communications.includes(:generated_document)
    @legal_kinds = Workflow.legal_kinds(@matter.state)
  end

  def new
    @matter = Matter.new(county: "Nassau")
  end

  def create
    attrs = params.require(:matter).permit(:client_name, :debtor_name, :debtor_address, :guarantor_name, :county)
    principal = (params.dig(:matter, :principal).to_s.delete(",$").to_d * 100).to_i
    ref = "WL-#{Date.current.year}-#{format('%04d', (Matter.maximum(:id) || 0) + 1001)}"
    @matter = Matter.open!(attrs.merge(reference: ref), principal_cents: principal, actor: "web")
    redirect_to matter_path(@matter), notice: "Opened #{@matter.reference}."
  rescue ActiveRecord::RecordInvalid, Workflow::InvalidTransition => e
    @matter = Matter.new(attrs)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end
end
