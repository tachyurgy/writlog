# Deadline computation for a New York commercial collection matter.
# Every rule returns a Deadline with the raw date, the rolled date and the
# citation, so the UI can show its work instead of a bare date.
module DeadlineRules
  Deadline = Data.define(:label, :raw_on, :due_on, :rule, :rolled_reasons) do
    def rolled? = raw_on != due_on
  end

  SERVICE_METHODS = {
    "personal" => "Personal delivery (CPLR 308(1))",
    "substituted" => "Deliver and mail (CPLR 308(2))",
    "nail_and_mail" => "Affix and mail (CPLR 308(4))",
    "secretary_of_state" => "Corporation via Secretary of State (BCL 306)"
  }.freeze

  module_function

  def build(label, raw, rule)
    due, reasons = CourtCalendar.roll_forward(raw)
    Deadline.new(label:, raw_on: raw, due_on: due, rule:, rolled_reasons: reasons)
  end

  # CPLR 320(a) + 3012: 20 days after personal delivery within the state;
  # otherwise 30 days after service is complete. Under 308(2)/(4) service is
  # complete 10 days after proof of service is filed.
  def answer_due(method:, served_on:, proof_filed_on: nil)
    case method
    when "personal"
      build("Answer due", served_on + 20, "CPLR 320(a): 20 days after personal delivery")
    when "substituted", "nail_and_mail"
      raise ArgumentError, "proof_filed_on is required for #{method} service" unless proof_filed_on
      complete = proof_filed_on + 10
      build("Answer due", complete + 30,
            "CPLR 308 + 320(a): service complete 10 days after proof filed (#{complete.iso8601}), then 30 days")
    when "secretary_of_state"
      build("Answer due", served_on + 30, "BCL 306 + CPLR 320(a): 30 days after service on the Secretary of State")
    else
      raise ArgumentError, "unknown service method #{method.inspect}"
    end
  end

  # CPLR 3215(c): move for default judgment within one year after the default.
  def default_judgment_deadline(answer_due_on)
    build("Default judgment motion deadline", answer_due_on.next_year,
          "CPLR 3215(c): within one year after the default")
  end

  # A demand letter's cure period.
  def demand_response(sent_on, days)
    build("Demand response period ends", sent_on + days, "Demand letter: #{days}-day cure period")
  end

  # CPLR 5222(b): a restraining notice is effective for one year after service.
  def restraint_expires(served_on)
    build("Restraining notice expires", served_on.next_year, "CPLR 5222(b): effective one year after service")
  end
end
