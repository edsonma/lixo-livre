module Api
  module V1
    # POST /api/v1/session/google   { credential }   the ID token from the "Sign in with Google" button.
    class GoogleSessionsController < BaseController
      def create
        outcome = SignInWithGoogle.call(credential: params.require(:credential), accepted_terms: params[:accepted_terms])
        return render(json: { error: outcome.error }, status: :unprocessable_entity) unless outcome.success?

        sign_in(:user, outcome.value, store: true)
        render json: { user: UserSerializer.call(outcome.value) }
      rescue Auth::GoogleIdentity::NotConfigured
        render json: { error: "google_not_configured" }, status: :service_unavailable
      rescue Auth::GoogleIdentity::Invalid => e
        render json: { error: "invalid_google_token", message: e.message }, status: :unauthorized
      end
    end
  end
end
