module ApplicationHelper
  def money(cents) = cents.nil? ? "—" : MergeFields.money(cents)
  def day(date) = date ? date.strftime("%b %-d, %Y") : "—"

  def state_badge(state)
    tag.span(state.to_s.humanize, class: "badge state-#{state}")
  end

  def days_until(date)
    return "" unless date
    n = (date - Date.current).to_i
    if n.negative? then "#{-n}d ago"
    elsif n.zero? then "today"
    else "in #{n}d"
    end
  end

  def payload_summary(event)
    p = event.payload
    parts = []
    parts << "principal #{money(p['principal_cents'])}" if p["principal_cents"]
    parts << "#{p['cure_days'] || 10}-day cure" if event.kind == "demand_sent"
    parts << "index #{p['index_number']}" if p["index_number"]
    parts << DeadlineRules::SERVICE_METHODS[p["method"]] if p["method"]
    parts << "proof filed #{p['proof_filed_on']}" if p["proof_filed_on"]
    parts << money(p["amount_cents"]) if p["amount_cents"]
    parts << "on #{p['recipient']}" if p["recipient"]
    parts << "#{p['template_key']} v#{p['version']}" if p["template_key"]
    parts << "#{p['channel']} #{p['direction']}: #{p['subject']}" if p["communication_id"]
    parts << "“#{p['note']}”" if p["note"]
    parts.join(" · ")
  end
end
