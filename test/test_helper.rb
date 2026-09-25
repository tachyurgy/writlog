ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # No parallelize: the concurrency tests open their own connections and
    # threads, which does not mix with forked parallel workers.

    def build_template(key: "demand_letter", version: 1, body: nil)
      DocumentTemplate.create!(key:, version:, name: "Demand #{version}",
                               body: body || "DEMAND\n\n{{debtor_name}} owes {{client_name}} {{balance}} as of {{as_of}}.")
    end

    def build_matter(ref: "T-#{SecureRandom.hex(3)}", principal_cents: 1_000_000, opened_on: Date.new(2026, 1, 5))
      Matter.open!({ reference: ref, client_name: "Example Funding LLC", debtor_name: "Example Debtor <Corp>",
                     county: "Nassau" }, principal_cents:, opened_on:, actor: "test")
    end
  end
end
