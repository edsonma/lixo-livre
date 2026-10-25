# Demo mode lets a deployment run end to end with FAKE AI and NO face/plate detection,
# so you can try the whole thing (for example on Railway) before wiring real providers.
#
#   DEMO_MODE=true        use the fake providers even in production
#   DEMO_CENTER=lat,lng   where the demo map opens and the fake reports are placed
#
# Never leave this on for real users: the fake detector blurs nothing.
module DemoMode
  TRUE_VALUES = %w[1 true yes on].freeze
  DEFAULT_CENTER = [-15.7942, -47.8825].freeze # lat, lng: Brasilia

  def self.enabled?
    TRUE_VALUES.include?(ENV["DEMO_MODE"].to_s.strip.downcase)
  end

  # Fake providers are fine in development and test, and in production only in demo mode.
  def self.fakes_allowed?(env = Rails.env)
    env.local? || enabled?
  end

  # [lat, lng]
  def self.center
    lat, lng = ENV["DEMO_CENTER"].to_s.split(",").map { |part| Float(part.strip, exception: false) }
    valid = lat && lng && lat.between?(-90, 90) && lng.between?(-180, 180)
    valid ? [lat, lng] : DEFAULT_CENTER
  end
end
