# Resolves a template's {{merge_fields}} against a matter. Values are strings,
# already formatted, so the digest of the inputs is stable and meaningful.
module MergeFields
  module_function

  def money(cents) = cents && format("$%s", ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", cents / 100.0)))
  def day(date) = date&.strftime("%B %-d, %Y")

  def resolvers
    {
      "matter_reference" => ->(m) { m.reference },
      "client_name" => ->(m) { m.client_name },
      "debtor_name" => ->(m) { m.debtor_name },
      "debtor_address" => ->(m) { m.debtor_address },
      "guarantor_name" => ->(m) { m.guarantor_name },
      "county" => ->(m) { m.county },
      "index_number" => ->(m) { m.index_number },
      "principal" => ->(m) { money(m.principal_cents) },
      "paid_to_date" => ->(m) { money(m.paid_cents) },
      "balance" => ->(m) { money(m.balance_cents) },
      "judgment_amount" => ->(m) { money(m.judgment_cents) },
      "judgment_entered_on" => ->(m) { day(m.judgment_entered_on) },
      "answer_due_on" => ->(m) { day(m.answer_due_on) },
      "served_on" => ->(m) { day(m.served_on) },
      # The document date is the date of the latest event, not "today", so the
      # same matter state always produces the same inputs (and the same digest).
      "as_of" => ->(m) { day(m.last_event_on) }
    }
  end

  # => { "values" => {field => value}, "missing" => [fields without a value] }
  def resolve(template, matter)
    values = template.fields.index_with { |f| resolvers[f]&.call(matter).presence }
    { "values" => values.compact, "missing" => values.select { |_f, v| v.nil? }.keys }
  end

  def digest(template, values)
    canonical = JSON.generate([template.id, template.version, values.sort.to_h])
    Digest::SHA256.hexdigest(canonical)
  end
end
