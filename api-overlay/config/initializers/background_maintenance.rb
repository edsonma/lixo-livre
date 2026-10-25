# The simple deployment (Active Job :async) runs jobs inside the web process. That has two gaps:
#   1. a restart drops queued jobs, leaving reports stuck in "pending" (they stay private);
#   2. nothing runs the nightly schedule, so heat scores would never decay.
# This thread covers both: shortly after boot and then every MAINTENANCE_INTERVAL_MINUTES
# (default 360) it re-queues stuck reports and recomputes the heat cells.
#
# With a real queue backend and scheduler (Solid Queue recurring tasks, Sidekiq, cron) set
# BACKGROUND_MAINTENANCE=false and use those instead.
if Rails.env.production? && ENV["BACKGROUND_MAINTENANCE"] != "false"
  Rails.application.config.after_initialize do
    next unless defined?(Rails::Server) # only in the web server, not in rake tasks or consoles

    Thread.new do
      Thread.current.name = "maintenance"
      sleep 20 # let the server come up first

      loop do
        Rails.application.executor.wrap do
          requeued = PipelineRecovery.requeue_stuck
          RecomputeHeatCellsJob.perform_later
          Rails.logger.info("[maintenance] requeued #{requeued.inspect}, recomputing heat cells")
        end
        sleep Integer(ENV.fetch("MAINTENANCE_INTERVAL_MINUTES", "360")) * 60
      rescue StandardError => e
        Rails.logger.error("[maintenance] #{e.class}: #{e.message}")
        sleep 60
      end
    end
  end
end
