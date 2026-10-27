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
end
