module Api
  module V1
    class DevicesController < BaseController
      # First launch of the mobile app: returns the anonymous token to store on the phone.
      def create
        device = Device.create!
        render json: { token: device.token }, status: :created
      end
    end
  end
end
