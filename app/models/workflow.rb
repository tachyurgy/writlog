# The matter workflow is a state machine whose ONLY input is the append-only
# event log. `Workflow.fold` is a pure function from (projection, event) to the
# next projection; the same function validates new events and replays history,
# so the stored projection on `matters` can always be rebuilt from the log and
# checked against it (see Workflow.replay and test/models/workflow_test.rb).
module Workflow
  class InvalidTransition < StandardError; end

  OPEN = %w[intake demand_sent suit_filed served answered in_default judgment_entered enforcement settled].freeze
  TERMINAL = %w[satisfied closed].freeze
  STATES = (OPEN + TERMINAL).freeze
  ENFORCEMENT_FROM = %w[judgment_entered enforcement].freeze

  # kind => from: states the event is legal in, to: next state (:same keeps it),
  # requires: payload keys, deadline: how the event sets the next deadline.
  TRANSITIONS = {
    "matter_opened" => { from: [nil], to: "intake", requires: %w[principal_cents] },
    "demand_sent" => { from: %w[intake], to: "demand_sent", requires: [] },
    "suit_filed" => { from: %w[intake demand_sent], to: "suit_filed", requires: %w[index_number] },
    "served" => { from: %w[suit_filed], to: "served", requires: %w[method] },
    "answer_received" => { from: %w[served in_default], to: "answered", requires: [] },
    "default_noted" => { from: %w[served], to: "in_default", requires: [] },
    "judgment_entered" => { from: %w[answered in_default], to: "judgment_entered", requires: %w[amount_cents] },
    "restraining_notice_served" => { from: ENFORCEMENT_FROM, to: "enforcement", requires: %w[recipient] },
    "information_subpoena_served" => { from: ENFORCEMENT_FROM, to: "enforcement", requires: %w[recipient] },
    "execution_issued" => { from: ENFORCEMENT_FROM, to: "enforcement", requires: [] },
    "payment_received" => { from: OPEN, to: :same, requires: %w[amount_cents] },
    "settlement_reached" => { from: OPEN - %w[intake settled], to: "settled", requires: %w[amount_cents] },
    "satisfaction_filed" => { from: %w[judgment_entered enforcement settled], to: "satisfied", requires: [] },
    "matter_closed" => { from: OPEN, to: "closed", requires: [] },
    # Audit-only events: legal in every state, never move the machine.
    "document_generated" => { from: [nil] + STATES, to: :same, requires: %w[document_id] },
    "communication_logged" => { from: [nil] + STATES, to: :same, requires: %w[communication_id] }
  }.freeze

  AUDIT_KINDS = %w[document_generated communication_logged].freeze
  USER_KINDS = (TRANSITIONS.keys - %w[matter_opened document_generated communication_logged]).freeze

  PROJECTED = %w[state events_count last_event_on principal_cents paid_cents judgment_cents index_number
                 service_method served_on answer_due_on default_judgment_deadline_on judgment_entered_on
                 restraint_expires_on next_deadline_on next_deadline_label].freeze

  module_function

  def blank
    PROJECTED.index_with { nil }.merge("events_count" => 0, "paid_cents" => 0, "principal_cents" => 0)
  end

  def legal_kinds(state)
    TRANSITIONS.select { |_k, t| t[:from].include?(state) }.keys & USER_KINDS
  end

  # Pure: (projection Hash, kind, effective_on, payload) -> new projection Hash.
  # Raises InvalidTransition and never has side effects.
  def fold(p, kind, effective_on, payload)
    t = TRANSITIONS[kind] or raise InvalidTransition, "unknown event #{kind.inspect}"
    state = p["state"]
    unless t[:from].include?(state)
      raise InvalidTransition, "#{kind} is not allowed from #{state || 'a new matter'}"
    end
    missing = t[:requires].reject { |k| payload[k].present? }
    raise InvalidTransition, "#{kind} needs #{missing.join(', ')}" if missing.any?
    if p["last_event_on"] && effective_on < p["last_event_on"]
      raise InvalidTransition, "#{kind} dated #{effective_on} is before the previous event (#{p['last_event_on']})"
    end

    n = p.merge("events_count" => p["events_count"] + 1)
    # Audit events do not move the matter's "as of" date, so recording that a
    # document was generated can never change that document's own inputs.
    n["last_event_on"] = effective_on unless AUDIT_KINDS.include?(kind)
    n["state"] = t[:to] unless t[:to] == :same

    case kind
    when "matter_opened"
      n["principal_cents"] = Integer(payload["principal_cents"])
      set_deadline(n, nil)
    when "demand_sent"
      set_deadline(n, DeadlineRules.demand_response(effective_on, Integer(payload.fetch("cure_days", 10))))
    when "suit_filed"
      n["index_number"] = payload["index_number"]
      set_deadline(n, DeadlineRules.build("Service deadline", effective_on + 120, "CPLR 306-b: serve within 120 days of filing"))
    when "served"
      method = payload["method"]
      raise InvalidTransition, "unknown service method #{method}" unless DeadlineRules::SERVICE_METHODS.key?(method)
      proof = payload["proof_filed_on"].presence && Date.parse(payload["proof_filed_on"].to_s)
      if %w[substituted nail_and_mail].include?(method) && proof.nil?
        raise InvalidTransition, "#{method} service needs proof_filed_on"
      end
      due = DeadlineRules.answer_due(method:, served_on: effective_on, proof_filed_on: proof)
      n.merge!("service_method" => method, "served_on" => effective_on, "answer_due_on" => due.due_on)
      set_deadline(n, due)
    when "answer_received"
      set_deadline(n, nil)
    when "default_noted"
      if effective_on <= p["answer_due_on"]
        raise InvalidTransition, "no default yet: the answer is due #{p['answer_due_on']}"
      end
      dj = DeadlineRules.default_judgment_deadline(p["answer_due_on"])
      n["default_judgment_deadline_on"] = dj.due_on
      set_deadline(n, dj)
    when "judgment_entered"
      n["judgment_cents"] = Integer(payload["amount_cents"])
      n["judgment_entered_on"] = effective_on
      set_deadline(n, nil)
    when "restraining_notice_served"
      r = DeadlineRules.restraint_expires(effective_on)
      n["restraint_expires_on"] = r.due_on
      set_deadline(n, r)
    when "payment_received"
      amount = Integer(payload["amount_cents"])
      raise InvalidTransition, "payment must be positive" unless amount.positive?
      n["paid_cents"] = p["paid_cents"] + amount
    when "settlement_reached", "satisfaction_filed", "matter_closed"
      set_deadline(n, nil)
    end
    n
  end

  def set_deadline(n, deadline)
    n["next_deadline_on"] = deadline&.due_on
    n["next_deadline_label"] = deadline&.label
  end

  # Rebuild a projection from events alone.
  def replay(events)
    events.sort_by(&:seq).reduce(blank) { |p, e| fold(p, e.kind, e.effective_on, e.payload) }
  end

  # The only write path for matter state. Row-locks the matter so seq is
  # gap-free and the fold sees the latest projection even under concurrency.
  # clamp: true moves an audit event's date up to the latest event date instead
  # of rejecting it (used by jobs, whose "now" can race a newer event).
  def append!(matter, kind, effective_on: Date.current, payload: {}, actor: "system", clamp: false)
    payload = payload.to_h.stringify_keys.compact_blank
    Matter.transaction do
      matter.lock!
      current = matter.projection
      effective_on = [effective_on, current["last_event_on"]].compact.max if clamp
      nxt = fold(current, kind, effective_on, payload)
      event = matter.matter_events.create!(
        seq: current["events_count"] + 1, kind:, effective_on:, payload:, actor:,
        from_state: current["state"] || "new", to_state: nxt["state"]
      )
      matter.update_columns(nxt.merge("updated_at" => Time.current))
      event
    end
  end
end
