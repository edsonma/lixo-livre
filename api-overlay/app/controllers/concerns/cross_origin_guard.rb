# A browser sends Origin on every cross-site write. With a session cookie in play, a write that comes
# from another site is refused (the cookie is SameSite=Lax too: two locks, not one).
module CrossOriginGuard
  extend ActiveSupport::Concern

  included do
    before_action :refuse_cross_origin_writes
  end

  private

  def refuse_cross_origin_writes
    return if request.get? || request.head? || request.options?

    origin = request.headers["Origin"]
    return if origin.blank? || allowed_origin?(origin)

    render json: { error: "cross_origin" }, status: :forbidden
  end

  # Same host as the request (compared without the scheme, so a TLS-terminating proxy cannot break it),
  # or one of the configured origins (APP_ORIGIN, and WEB_ORIGINS for a separate web front end in development).
  def allowed_origin?(origin)
    configured = [ENV["APP_ORIGIN"], *ENV.fetch("WEB_ORIGINS", "").split(",")].map { |o| o.to_s.strip }.reject(&:empty?)
    origin.sub(%r{\Ahttps?://}, "") == request.host_with_port || configured.include?(origin)
  end
end
