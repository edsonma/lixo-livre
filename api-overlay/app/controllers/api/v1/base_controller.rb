module Api
  module V1
    class BaseController < ActionController::API
      before_action :set_device

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { errors: e.record.errors.to_hash }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::RecordNotFound do
        head :not_found
      end

      private

      # The mobile app sends the anonymous token it got from POST /devices.
      # Later, when login exists, the web can authenticate separately.
      def set_device
        token = request.headers["X-Device-Token"]
        @device = Device.find_by(token: token) if token.present?
        @device&.touch(:last_seen_at)
      end

      def require_device!
        head :unauthorized unless @device
      end

      def serialize_trash(trash)
        {
          id: trash.id,
          severity: trash.severity,
          trash_types: trash.trash_types,
          extra_info: trash.extra_info,
          taken_at: trash.taken_at,
          lat: trash.lonlat.y,
          lng: trash.lonlat.x,
          photo_url: url_for(trash.photo),
          uploader: trash.user ? { id: trash.user_id, name: trash.user.name } : nil # nil = anonymous
        }
      end
    end
  end
end
