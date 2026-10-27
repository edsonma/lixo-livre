module Api
  module V1
    # POST /api/v1/users   { name, email, password }  creates the account and logs it in.
    class RegistrationsController < BaseController
      def create
        user = User.new(email: params.require(:email).to_s, name: params[:name].to_s.strip.presence, password: params.require(:password).to_s)
        user.save!
        sign_in(:user, user, store: true)
        render json: { user: serialize_user(user) }, status: :created
      end
    end
  end
end
