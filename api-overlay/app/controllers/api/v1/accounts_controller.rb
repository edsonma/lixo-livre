module Api
  module V1
    # DELETE /api/v1/account   the person deletes their account and everything they reported
    # (LGPD: right to erasure). Their photos leave the map and the places are re-scored.
    class AccountsController < BaseController
      before_action :require_login!

      def destroy
        user = current_user
        user.trashes.find_each(&:destroy!)
        sign_out(:user)
        user.destroy!
        head :no_content
      end
    end
  end
end
