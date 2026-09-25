class Matter < ApplicationRecord
  has_many :matter_events, -> { order(:seq) }, dependent: :restrict_with_exception
  has_many :generated_documents, -> { order(:template_key, :version) }, dependent: :restrict_with_exception
  has_many :communications, -> { order(occurred_at: :desc) }, dependent: :restrict_with_exception

  validates :reference, :client_name, :debtor_name, :county, presence: true

  scope :by_deadline, -> { order(Arel.sql("next_deadline_on IS NULL, next_deadline_on, reference")) }

  # Opens a matter: the row and its first event are one transaction.
  def self.open!(attrs, principal_cents:, opened_on: Date.current, actor: "intake")
    transaction do
      m = create!(attrs)
      Workflow.append!(m, "matter_opened", effective_on: opened_on, payload: { principal_cents: }, actor:)
      m.reload
    end
  end

  def projection
    Workflow::PROJECTED.index_with { |a| self[a] }.merge("state" => (events_count.zero? ? nil : state))
  end

  def consistent_with_log?
    Workflow.replay(matter_events.to_a) == projection
  end

  def balance_cents
    (judgment_cents || principal_cents) - paid_cents
  end

  def terminal? = Workflow::TERMINAL.include?(state)

  def to_param = reference
end
