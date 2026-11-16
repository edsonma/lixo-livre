module Api
  module V1
    # PATCH /api/v1/profile   the person edits their own profile (multipart, so the picture can come along):
    #   name, bio, website, gender        only the ones sent are changed; blank clears (not the name)
    #   avatar                            an image file; remove_avatar=true deletes the current one
    # The email, the role and everything else are not accepted: only the fields named in UpdateProfile::EDITABLE
    # are read from the request. Answers { user }, or 422 { errors: { field: [messages] } }.
    class ProfilesController < BaseController
      before_action :require_login!

      def update
        UpdateProfile.call(
          user: current_user,
          fields: params.permit(*UpdateProfile::EDITABLE).to_h,
          avatar: params[:avatar],
          remove_avatar: ActiveModel::Type::Boolean.new.cast(params[:remove_avatar])
        )
        render json: { user: UserSerializer.call(current_user.reload) }
      end
    end
  end
end
