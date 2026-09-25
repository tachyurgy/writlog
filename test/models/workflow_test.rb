require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  test "happy path projects state and deadlines from events" do
    m = build_matter
    Workflow.append!(m, "demand_sent", effective_on: Date.new(2026, 1, 7), payload: { cure_days: 10 })
    Workflow.append!(m, "suit_filed", effective_on: Date.new(2026, 2, 2), payload: { index_number: "600001/2026" })
    Workflow.append!(m, "served", effective_on: Date.new(2026, 6, 8), payload: { method: "personal" })
    m.reload
    assert_equal "served", m.state
    assert_equal Date.new(2026, 6, 29), m.answer_due_on
    assert_equal "Answer due", m.next_deadline_label
    assert_equal (1..4).to_a, m.matter_events.pluck(:seq)
    assert m.consistent_with_log?
  end

  test "illegal transitions are rejected and write nothing" do
    m = build_matter
    assert_raises(Workflow::InvalidTransition) { Workflow.append!(m, "judgment_entered", payload: { amount_cents: 1 }) }
    assert_raises(Workflow::InvalidTransition) { Workflow.append!(m, "suit_filed", effective_on: Date.new(2026, 2, 1)) } # no index
    assert_equal 1, m.reload.events_count
    assert_equal 1, m.matter_events.count
    assert_equal "intake", m.state
  end

  test "a default cannot be noted until the answer deadline has passed" do
    m = build_matter
    Workflow.append!(m, "suit_filed", effective_on: Date.new(2026, 6, 1), payload: { index_number: "1/2026" })
    Workflow.append!(m, "served", effective_on: Date.new(2026, 6, 8), payload: { method: "personal" })
    err = assert_raises(Workflow::InvalidTransition) { Workflow.append!(m, "default_noted", effective_on: Date.new(2026, 6, 29)) }
    assert_match "2026-06-29", err.message
    Workflow.append!(m, "default_noted", effective_on: Date.new(2026, 6, 30))
    assert_equal "in_default", m.reload.state
    assert_equal Date.new(2027, 6, 29), m.default_judgment_deadline_on
  end

  test "events cannot be back-dated before the previous event" do
    m = build_matter(opened_on: Date.new(2026, 3, 1))
    assert_raises(Workflow::InvalidTransition) { Workflow.append!(m, "demand_sent", effective_on: Date.new(2026, 2, 28)) }
  end

  test "terminal matters accept audit events but no workflow events" do
    m = build_matter
    Workflow.append!(m, "matter_closed", effective_on: Date.new(2026, 1, 6))
    assert_raises(Workflow::InvalidTransition) { Workflow.append!(m, "payment_received", payload: { amount_cents: 5 }) }
    Workflow.append!(m, "communication_logged", payload: { communication_id: 1 })
    assert_equal "closed", m.reload.state
    assert_equal Date.new(2026, 1, 6), m.last_event_on, "audit events must not move the as-of date"
  end

  test "the log is append-only in the database, not just in Ruby" do
    m = build_matter
    id = m.matter_events.first.id
    assert_raises(ActiveRecord::StatementInvalid) { MatterEvent.where(id:).update_all(kind: "x") }
    assert_raises(ActiveRecord::StatementInvalid) { MatterEvent.where(id:).delete_all }
  end

  # Property: along any random walk of legal events, the stored projection equals
  # a fresh replay of the log, seq is gap-free, and rejected events leave no trace.
  test "projection always equals replay of the log (random walks)" do
    rng = Random.new(42)
    payloads = {
      "suit_filed" => -> { { index_number: "#{rng.rand(600_000..699_999)}/2026" } },
      "served" => -> { { method: DeadlineRules::SERVICE_METHODS.keys.sample(random: rng), proof_filed_on: nil } },
      "judgment_entered" => -> { { amount_cents: rng.rand(10_000..9_000_000) } },
      "payment_received" => -> { { amount_cents: rng.rand(1..500_000) } },
      "settlement_reached" => -> { { amount_cents: rng.rand(1..500_000) } },
      "restraining_notice_served" => -> { { recipient: "Bank #{rng.rand(9)}" } },
      "information_subpoena_served" => -> { { recipient: "Bank #{rng.rand(9)}" } }
    }
    rejected = 0
    40.times do |i|
      m = build_matter(ref: "PROP-#{i}")
      date = Date.new(2026, 1, 5)
      rng.rand(3..14).times do
        kinds = Workflow.legal_kinds(m.reload.state)
        break if kinds.empty?
        # Mostly legal kinds, sometimes any kind at all, to exercise the guards.
        kind = rng.rand < 0.2 ? Workflow::USER_KINDS.sample(random: rng) : kinds.sample(random: rng)
        date += rng.rand(0..30)
        payload = payloads.fetch(kind, -> { {} }).call
        payload[:proof_filed_on] = (date + 2).iso8601 if kind == "served" && %w[substituted nail_and_mail].include?(payload[:method])
        before = m.events_count
        begin
          Workflow.append!(m, kind, effective_on: date, payload:)
        rescue Workflow::InvalidTransition
          rejected += 1
          assert_equal before, m.reload.events_count
        end
      end
      m.reload
      assert_equal Workflow.replay(m.matter_events.to_a), m.projection, "#{m.reference} drifted"
      assert_equal (1..m.events_count).to_a, m.matter_events.pluck(:seq)
    end
    assert rejected.positive?, "the walk should hit the guards"
  end
end
