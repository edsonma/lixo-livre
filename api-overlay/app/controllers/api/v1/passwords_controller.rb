module Api
  module V1
    class PasswordsController < BaseController
      # POST /api/v1/password/forgot  { email }
      # Always answers 204, whether or not the email has an account: it must not tell strangers who is registered.
      def forgot
        user = User.find_for_database_authentication(email: params.require(:email).to_s)
        SendUserEmailJob.perform_later(user.id, "reset") if user && Mailer.configured?
        head :no_content
      end

      # POST /api/v1/password/reset  { token, password }
      # Does not log the person in: they sign in with the new password (and their second factor, if they use one).
      def reset
        user = User.find_by_token_for(:password_reset, params.require(:token).to_s)
        return render(json: { error: "invalid_token" }, status: :unprocessable_entity) unless user

        password = params.require(:password).to_s
        user.password = password
        user.email_verified_at ||= Time.current # they just proved they read that inbox
        user.save!
        head :no_content
      end
    end
  end
end
