module Api
  module V1
    # Fingerprint / face login (WebAuthn passkeys).
    #   POST /passkeys/registration_options   logged in: challenge for adding a passkey to this account
    #   POST /passkeys                        logged in: the phone's answer; stores the passkey
    #   POST /passkeys/authentication_options challenge for logging in (no email needed)
    #   POST /passkeys/authenticate           the phone's signature; logs in
    #   GET /passkeys, DELETE /passkeys/:id   list and remove this account's passkeys
    class PasskeysController < BaseController
      before_action :require_login!, only: %i[registration_options create index destroy]

      def index
        render json: current_user.passkeys.order(:created_at).map { |p| serialize_passkey(p) }
      end

      def registration_options
        options, challenge = service.registration_options(current_user)
        session[:passkey_registration_challenge] = challenge
        render json: options
      rescue StandardError => e
        passkey_error(e)
      end

      def create
        challenge = session.delete(:passkey_registration_challenge)
        return render(json: { error: "no_challenge" }, status: :unprocessable_entity) unless challenge

        passkey = service.register(current_user, params.require(:credential).to_unsafe_h, challenge, nickname: params[:nickname])
        render json: serialize_passkey(passkey), status: :created
      rescue PasskeyService::Failed => e
        render json: { error: "passkey_failed", message: e.message }, status: :unprocessable_entity
      rescue ActionController::ParameterMissing
        raise
      rescue StandardError => e
        passkey_error(e)
      end

      def authentication_options
        options, challenge = service.authentication_options
        session[:passkey_authentication_challenge] = challenge
        render json: options
      rescue StandardError => e
        passkey_error(e)
      end

      def authenticate
        challenge = session.delete(:passkey_authentication_challenge)
        return render(json: { error: "no_challenge" }, status: :unprocessable_entity) unless challenge

        user = service.authenticate(params.require(:credential).to_unsafe_h, challenge)
        user.save! if user.listed_as_admin? && !user.admin?
        sign_in(:user, user, store: true)
        render json: { user: serialize_user(user) }
      rescue PasskeyService::Failed => e
        render json: { error: "passkey_failed", message: e.message }, status: :unauthorized
      end

      def destroy
        current_user.passkeys.find(params[:id]).destroy!
        head :no_content
      end

      private

      # Anything unexpected (a library mismatch, a bad configuration) is logged and shown to the
      # logged-in person instead of a blank 500, so it can be fixed.
      def passkey_error(error)
        Rails.logger.error("[passkeys] #{error.class}: #{error.message}\n#{error.backtrace.first(6).join("\n")}")
        render json: { error: "passkey_error", message: "#{error.class}: #{error.message}".truncate(200) }, status: :internal_server_error
      end

      def service
        PasskeyService.new(request)
      end

      def serialize_passkey(passkey)
        { id: passkey.id, nickname: passkey.nickname, created_at: passkey.created_at, last_used_at: passkey.last_used_at }
      end
    end
  end
end
