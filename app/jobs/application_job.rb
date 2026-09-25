class ApplicationJob < ActiveJob::Base
  # Deliberately plain ActiveJob: no Solid Queue-only features (limits_concurrency,
  # recurring config) are used, so these jobs run unchanged on Sidekiq.
  discard_on ActiveJob::DeserializationError
end
