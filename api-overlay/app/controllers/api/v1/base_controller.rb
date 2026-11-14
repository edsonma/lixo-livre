module Api
  module V1
    # What every endpoint shares. Each concern has one job; see their own comments. The order matters:
    # the device is looked up first, then writes from other sites are refused.
    class BaseController < ActionController::API
      include ApiErrorHandling
      include DeviceAuthentication
      include CrossOriginGuard
      include AccountGuards
    end
  end
end
