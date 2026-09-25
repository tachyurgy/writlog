# New York public holidays (General Construction Law section 24) and the
# section 25-a roll-forward rule: when the last day of a period falls on a
# Saturday, Sunday or public holiday, the act may be done on the next
# business day.
#
# Illustrative only. A real docketing system also tracks court-specific
# closures and emergency orders; those would be rows, not code.
module CourtCalendar
  module_function

  def holidays(year)
    @holidays ||= {}
    @holidays[year] ||= begin
      fixed = {
        "New Year's Day" => Date.new(year, 1, 1),
        "Lincoln's Birthday" => Date.new(year, 2, 12),
        "Juneteenth" => Date.new(year, 6, 19),
        "Independence Day" => Date.new(year, 7, 4),
        "Veterans Day" => Date.new(year, 11, 11),
        "Christmas Day" => Date.new(year, 12, 25)
      }
      floating = {
        "Martin Luther King Jr. Day" => nth_weekday(year, 1, 1, 3),
        "Washington's Birthday" => nth_weekday(year, 2, 1, 3),
        "Memorial Day" => last_weekday(year, 5, 1),
        "Labor Day" => nth_weekday(year, 9, 1, 1),
        "Columbus Day" => nth_weekday(year, 10, 1, 2),
        "Election Day" => nth_weekday(year, 11, 1, 1) + 1,
        "Thanksgiving Day" => nth_weekday(year, 11, 4, 4)
      }
      all = fixed.merge(floating)
      # GCL 24: a holiday falling on Sunday is observed the following Monday.
      observed = all.filter_map { |name, d| ["#{name} (observed)", d + 1] if d.sunday? }.to_h
      all.merge(observed).invert
    end
  end

  def holiday_name(date)
    holidays(date.year)[date]
  end

  def holiday?(date)
    !holiday_name(date).nil?
  end

  def business_day?(date)
    !(date.saturday? || date.sunday? || holiday?(date))
  end

  # GCL 25-a. Returns [rolled_date, reasons] where reasons explains each skipped day.
  def roll_forward(date)
    reasons = []
    d = date
    until business_day?(d)
      reasons << "#{d.iso8601} is #{holiday_name(d) || d.strftime('%A')}"
      d += 1
    end
    [d, reasons]
  end

  def nth_weekday(year, month, wday, n)
    first = Date.new(year, month, 1)
    first + ((wday - first.wday) % 7) + 7 * (n - 1)
  end

  def last_weekday(year, month, wday)
    last = Date.new(year, month, -1)
    last - ((last.wday - wday) % 7)
  end
end
