module Api
  module V1
    class EmailVerificationsController < BaseController
      before_action :require_login!, only: :resend

      # POST /api/v1/email/verify  { token }   the link from the email
      def create
        user = User.find_by_token_for(:email_verification, params.require(:token).to_s)
        return render(json: { error: "invalid_token" }, status: :unprocessable_entity) unless user

        user.verify_email!
        render json: { user: current_user&.id == user.id ? serialize_user(user) : nil }
      end

      # POST /api/v1/email/resend   sends the confirmation email again
      def resend
        return render(json: { error: "mail_not_configured" }, status: :service_unavailable) unless Mailer.configured?

        SendUserEmailJob.perform_later(current_user.id, "verify") unless current_user.email_verified?
        head :no_content
      end
    end
  end
end
