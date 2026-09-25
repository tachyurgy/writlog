class MatterEvent < ApplicationRecord
  belongs_to :matter

  # The database trigger is the real guard; this makes the intent obvious in Ruby too.
  def readonly? = persisted?
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "matter_events is append-only" }

  def label = kind.humanize
end
