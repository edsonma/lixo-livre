# The mobile app sends the anonymous token it got from POST /devices. A request without a (known) token
# is still served; the actions that need a device ask for it with require_device!.
module DeviceAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :set_device
  end

  private

  def set_device
    token = request.headers["X-Device-Token"]
    @device = Device.find_by(token: token) if token.present?
    @device&.touch(:last_seen_at)
  end

  def require_device!
    head :unauthorized unless @device
  end
end
