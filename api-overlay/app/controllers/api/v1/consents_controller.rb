module Api
  module V1
    # POST /api/v1/consent   { accepted_terms: true }  records that the logged-in person accepted the
    # current Terms of Use and Privacy Policy (older accounts, or after the text changed).
    class ConsentsController < BaseController
      before_action :require_login!

      def create
        return render(json: { error: "terms_required" }, status: :unprocessable_entity) unless Terms.accepted_param?(params[:accepted_terms])

        current_user.accept_terms
        current_user.save!
        render json: { user: serialize_user(current_user) }
      end
    end
  end
end
