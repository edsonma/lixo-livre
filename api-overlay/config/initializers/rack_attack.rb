# Basic abuse protection. Uses Rails.cache; in development enable it with `bin/rails dev:cache`.
class Rack::Attack
  throttle("devices/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/api/v1/devices"
  end

  throttle("trashes/device", limit: 30, period: 1.hour) do |req|
    req.get_header("HTTP_X_DEVICE_TOKEN") if req.post? && req.path == "/api/v1/trashes"
  end

  # Login and sign-up: slow down password guessing and account spam.
  throttle("login/ip", limit: 20, period: 5.minutes) do |req|
    req.ip if req.post? && req.path.match?(%r{\A/api/v1/(session(/google)?|passkeys/authenticate)\z})
  end

  throttle("signup/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/api/v1/users"
  end

  # Emails and second factor: nobody should be able to flood an inbox or guess codes.
  throttle("password-forgot/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/api/v1/password/forgot"
  end

  throttle("password-forgot/email", limit: 3, period: 1.hour) do |req|
    email_param(req) if req.post? && req.path == "/api/v1/password/forgot"
  end

  throttle("password-reset/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/api/v1/password/reset"
  end

  throttle("email-resend/ip", limit: 6, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/api/v1/email/resend"
  end

  throttle("login/email", limit: 10, period: 10.minutes) do |req|
    email_param(req) if req.post? && req.path == "/api/v1/session"
  end

  throttle("two-factor/ip", limit: 20, period: 10.minutes) do |req|
    req.ip if req.post? && req.path.start_with?("/api/v1/two_factor/")
  end

  # the email in a JSON or form body, lowercased
  def self.email_param(req)
    ActionDispatch::Request.new(req.env).params["email"].to_s.strip.downcase.presence
  rescue StandardError
    nil
  end
end
