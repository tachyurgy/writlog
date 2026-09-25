require "test_helper"

class DeadlineRulesTest < ActiveSupport::TestCase
  test "personal delivery: 20 days, rolled off a Sunday" do
    d = DeadlineRules.answer_due(method: "personal", served_on: Date.new(2026, 6, 8))
    assert_equal Date.new(2026, 6, 28), d.raw_on
    assert_equal Date.new(2026, 6, 29), d.due_on
    assert d.rolled?
  end

  test "deliver and mail: complete 10 days after proof, then 30, rolled past Columbus Day" do
    d = DeadlineRules.answer_due(method: "substituted", served_on: Date.new(2026, 8, 28), proof_filed_on: Date.new(2026, 9, 1))
    assert_equal Date.new(2026, 10, 11), d.raw_on
    assert_equal Date.new(2026, 10, 13), d.due_on
    assert_match "2026-09-11", d.rule
  end

  test "secretary of state: 30 days" do
    d = DeadlineRules.answer_due(method: "secretary_of_state", served_on: Date.new(2026, 2, 18))
    assert_equal Date.new(2026, 3, 20), d.due_on
    refute d.rolled?
  end

  test "substituted service without proof date is an error" do
    assert_raises(ArgumentError) { DeadlineRules.answer_due(method: "substituted", served_on: Date.new(2026, 1, 5)) }
  end

  test "default judgment clock and restraint expiry roll too" do
    assert_equal Date.new(2027, 6, 29), DeadlineRules.default_judgment_deadline(Date.new(2026, 6, 29)).due_on
    # 2027-05-29 is a Saturday, 2027-05-31 is Memorial Day.
    assert_equal Date.new(2027, 6, 1), DeadlineRules.restraint_expires(Date.new(2026, 5, 29)).due_on
  end
end
