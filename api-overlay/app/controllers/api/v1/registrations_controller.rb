module Api
  module V1
    # POST /api/v1/users   { name, email, password, accepted_terms: true }  creates the account and logs it in.
    class RegistrationsController < BaseController
      def create
        outcome = RegisterAccount.call(
          email: params.require(:email).to_s, password: params.require(:password).to_s,
          name: params[:name], accepted_terms: params[:accepted_terms]
        )
        return render(json: { error: outcome.error }, status: :unprocessable_entity) unless outcome.success?

        sign_in(:user, outcome.value, store: true)
        render json: { user: UserSerializer.call(outcome.value) }, status: :created
      end
    end
  end
end
