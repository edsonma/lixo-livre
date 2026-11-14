module Api
  module V1
    # The login state of the browser. GET says who is logged in (or null), POST logs in with an email and
    # password, DELETE logs out. Google and passkeys have their own endpoints below.
    class SessionsController < BaseController
      def show
        render json: { user: current_user && UserSerializer.call(current_user) }
      end

      def create
        password = params.require(:password).to_s
        outcome = AuthenticateWithPassword.call(email: params.require(:email).to_s, password: password, otp: params[:otp])
        return render(json: { error: outcome.error }, status: :unauthorized) unless outcome.success?

        sign_in_user(outcome.value)
        render json: { user: UserSerializer.call(outcome.value) }
      end

      def destroy
        sign_out(:user)
        head :no_content
      end

      private

      def sign_in_user(user)
        user.promote_if_eligible!
        user.update_column(:last_sign_in_at, Time.current)
        sign_in(:user, user, store: true)
      end
    end
  end
end
