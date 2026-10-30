# Error tracking. Off unless SENTRY_DSN is set (free plan at sentry.io is enough to start).
if defined?(Sentry) && ENV["SENTRY_DSN"].to_s.strip != ""
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"].strip
    config.environment = ENV["RAILS_ENV"] || "production"
    config.release = ENV["RAILWAY_GIT_COMMIT_SHA"]
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES", "0").to_f
    config.send_default_pii = false # no IPs, cookies or user emails
    config.excluded_exceptions += ["ActionController::RoutingError"]
    # Never ship secrets or personal data that travel in params.
    config.before_send = lambda do |event, _hint|
      event.request.data = "[filtered]" if event.request
      event.request.cookies = nil if event.request
      event
    end
  end
end
