module Api
  module V1
    # POST /api/v1/session/google   { credential }   the ID token from the "Sign in with Google" button.
    # Finds the account by Google id, else by the (verified) email, else creates it.
    class GoogleSessionsController < BaseController
      def create
        identity = GoogleIdentity.verify(params.require(:credential))
        user = User.find_by(provider: "google", uid: identity.uid)
        if user.nil? && (user = User.find_by(email: identity.email)) && Mailer.configured? && !user.email_verified?
          user.reset_credentials! # the email was never confirmed: whoever registered it must not keep a way in
        end
        if user.nil? && !Terms.accepted_param?(params[:accepted_terms])
          return render json: { error: "terms_required" }, status: :unprocessable_entity # a new account needs consent first
        end

        user ||= User.new(email: identity.email, name: identity.name, password: Devise.friendly_token)
        user.provider ||= "google"
        user.uid ||= identity.uid
        user.accept_terms if user.new_record?
        user.email_verified_at ||= Time.current # Google already verified this address
        user.save!

        sign_in(:user, user, store: true)
        render json: { user: UserSerializer.call(user) }
      rescue GoogleIdentity::NotConfigured
        render json: { error: "google_not_configured" }, status: :service_unavailable
      rescue GoogleIdentity::Invalid => e
        render json: { error: "invalid_google_token", message: e.message }, status: :unauthorized
      end
    end
  end
end
