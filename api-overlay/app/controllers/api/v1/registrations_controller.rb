module Api
  module V1
    # POST /api/v1/users   { name, email, password, accepted_terms: true }  creates the account and logs it in.
    class RegistrationsController < BaseController
      def create
        user = User.new(email: params.require(:email).to_s, name: params[:name].to_s.strip.presence, password: params.require(:password).to_s)
        return render(json: { error: "terms_required" }, status: :unprocessable_entity) unless Terms.accepted_param?(params[:accepted_terms])

        user.accept_terms
        user.save!
        SendUserEmailJob.perform_later(user.id, "verify") if Mailer.configured?
        sign_in(:user, user, store: true)
        render json: { user: serialize_user(user) }, status: :created
      end
    end
  end
end
