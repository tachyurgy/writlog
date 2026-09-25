threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count
port ENV.fetch("PORT", 3000)
plugin :tmp_restart

# Solid Queue runs inside Puma as threads (async mode), not forked processes,
# so the whole app fits one small container. Swap to Sidekiq by changing the
# adapter in config/application.rb and removing these two lines.
if ENV.fetch("SOLID_QUEUE_IN_PUMA", "1") == "1"
  plugin :solid_queue
  solid_queue_mode :async
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
