module Api
  module V1
    # Optional two-factor login with an authenticator app (TOTP). Passkeys and Google sign-in skip it:
    # a passkey is already two factors (the device and the fingerprint or face), and Google has its own.
    class TwoFactorsController < BaseController
      before_action :require_login!

      # POST /api/v1/two_factor/setup   -> { secret, uri }  (not active until /enable confirms a code)
      def setup
        return render(json: { error: "already_enabled" }, status: :unprocessable_entity) if current_user.otp_enabled?

        secret = current_user.start_otp_setup!
        render json: { secret: secret, uri: Totp.uri(secret, current_user.email) }
      end

      # POST /api/v1/two_factor/enable  { code }  -> { recovery_codes: [...], user }  (the codes are shown only now)
      def enable
        codes = current_user.enable_otp!(params.require(:code).to_s)
        return render(json: { error: "invalid_code" }, status: :unprocessable_entity) unless codes

        render json: { recovery_codes: codes, user: serialize_user(current_user) }
      end

      # POST /api/v1/two_factor/disable  { code }  a current code or a recovery code
      def disable
        return render(json: { error: "invalid_code" }, status: :unprocessable_entity) unless current_user.otp_enabled? && current_user.check_otp(params.require(:code).to_s)

        current_user.disable_otp!
        render json: { user: serialize_user(current_user) }
      end
    end
  end
end
