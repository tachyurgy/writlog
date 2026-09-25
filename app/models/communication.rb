class Communication < ApplicationRecord
  CHANNELS = %w[letter email phone court_filing portal].freeze
  DIRECTIONS = %w[outbound inbound].freeze

  belongs_to :matter
  belongs_to :generated_document, optional: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :counterparty, :subject, :occurred_at, presence: true

  # Logging a communication also appends to the matter's event log, in one transaction.
  def self.log!(matter, attrs)
    transaction do
      c = matter.communications.create!(attrs)
      Workflow.append!(matter, "communication_logged",
                       effective_on: c.occurred_at.to_date, clamp: true,
                       payload: { communication_id: c.id, channel: c.channel, direction: c.direction, subject: c.subject },
                       actor: "comms")
      c
    end
  end
end
