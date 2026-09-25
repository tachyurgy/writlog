class DeadlinesController < ApplicationController
  def show
    @method = params[:method].presence_in(DeadlineRules::SERVICE_METHODS.keys) || "personal"
    @served_on = parse(params[:served_on]) || Date.new(2026, 11, 13)
    @proof_filed_on = parse(params[:proof_filed_on]) || (@served_on + 3)
    @answer = DeadlineRules.answer_due(method: @method, served_on: @served_on, proof_filed_on: @proof_filed_on)
    @default = DeadlineRules.default_judgment_deadline(@answer.due_on)
    @year = (params[:year].presence || @served_on.year).to_i.clamp(2000, 2100)
    @holidays = CourtCalendar.holidays(@year).sort
  end

  private

  def parse(v)
    v.present? ? Date.parse(v) : nil
  rescue Date::Error
    nil
  end
end
