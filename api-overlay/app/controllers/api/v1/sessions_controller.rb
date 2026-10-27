module Api
  module V1
    # The login state of the browser. GET says who is logged in (or null), POST logs in with an email and
    # password, DELETE logs out. Google and passkeys have their own endpoints below.
    class SessionsController < BaseController
      def show
        render json: { user: current_user && serialize_user(current_user) }
      end

      def create
        user = User.find_for_database_authentication(email: params.require(:email).to_s)
        return render(json: { error: "invalid_credentials" }, status: :unauthorized) unless user&.valid_password?(params.require(:password).to_s)

        sign_in_user(user)
        render json: { user: serialize_user(user) }
      end

      def destroy
        sign_out(:user)
        head :no_content
      end

      private

      def sign_in_user(user)
        user.save! if user.listed_as_admin? && !user.admin? # ADMIN_EMAILS changed since they signed up
        user.update_column(:last_sign_in_at, Time.current)
        sign_in(:user, user, store: true)
      end
    end
  end
end
