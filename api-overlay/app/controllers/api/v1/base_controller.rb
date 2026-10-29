module Api
  module V1
    class BaseController < ActionController::API
      before_action :set_device
      before_action :refuse_cross_origin_writes

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { errors: e.record.errors.to_hash }, status: :unprocessable_entity
      end
      rescue_from ActiveRecord::RecordNotFound do
        head :not_found
      end
      rescue_from ActionController::ParameterMissing do |e|
        render json: { errors: { e.param => ["is required"] } }, status: :bad_request
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

      # Reporting needs an account. Also ties this device to the account: a device nobody owns yet is
      # claimed (so anonymous history is kept); one that belongs to somebody else is not used.
      def require_login!
        return render(json: { error: "login_required" }, status: :unauthorized) unless current_user

        return unless @device

        if @device.user_id.nil?
          @device.claim_by!(current_user)
        elsif @device.user_id != current_user.id
          @device = nil # the phone's token belongs to another account: the app asks for a new one
        end
      end

      # Reporting also needs the current Terms and Privacy Policy accepted (older accounts are asked once).
      def require_terms!
        render(json: { error: "terms_required" }, status: :forbidden) unless current_user&.terms_current?
      end

      def require_admin!
        return render(json: { error: "login_required" }, status: :unauthorized) unless current_user

        render(json: { error: "forbidden" }, status: :forbidden) unless current_user.admin?
      end

      def require_moderator!
        return render(json: { error: "login_required" }, status: :unauthorized) unless current_user

        render(json: { error: "forbidden" }, status: :forbidden) unless current_user.privileged?
      end

      # A browser sends Origin on every cross-site write. With a session cookie in play, a write that
      # comes from another site is refused (the cookie is SameSite=Lax too: two locks, not one).
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

      def serialize_user(user)
        { id: user.id, name: user.name, email: user.email, role: user.role, admin: user.admin?, moderator: user.privileged?,
          passkeys: user.passkeys.count, google: user.provider == "google", terms_ok: user.terms_current? }
      end

      def serialize_trash(trash)
        {
          id: trash.id,
          kind: trash.kind,
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
