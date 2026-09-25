require "test_helper"

class CourtCalendarTest < ActiveSupport::TestCase
  test "known New York holidays" do
    h = CourtCalendar.holidays(2026)
    assert_equal "Columbus Day", h[Date.new(2026, 10, 12)]
    assert_equal "Election Day", h[Date.new(2026, 11, 3)]
    assert_equal "Thanksgiving Day", h[Date.new(2026, 11, 26)]
    assert_equal "Lincoln's Birthday", h[Date.new(2026, 2, 12)]
    assert_equal "Memorial Day", h[Date.new(2026, 5, 25)]
    # Christmas 2022 fell on a Sunday: observed Monday the 26th.
    assert CourtCalendar.holiday?(Date.new(2022, 12, 26))
    assert_equal 13, CourtCalendar.holidays(2026).size
  end

  test "rolls a Sunday into a Monday holiday and past it" do
    rolled, reasons = CourtCalendar.roll_forward(Date.new(2026, 10, 11))
    assert_equal Date.new(2026, 10, 13), rolled
    assert_equal ["2026-10-11 is Sunday", "2026-10-12 is Columbus Day"], reasons
  end

  # Property: for any date, the rolled date is the FIRST business day on or after it.
  test "roll_forward returns the earliest business day on or after the date" do
    rng = Random.new(20_260_924)
    start = Date.new(2018, 1, 1)
    2_000.times do
      raw = start + rng.rand(365 * 17)
      rolled, reasons = CourtCalendar.roll_forward(raw)
      assert CourtCalendar.business_day?(rolled), "#{rolled} is not a business day"
      assert rolled >= raw
      (raw...rolled).each { |d| refute CourtCalendar.business_day?(d), "skipped business day #{d}" }
      assert_equal (rolled - raw).to_i, reasons.size
    end
  end
end
