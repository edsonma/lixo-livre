module Api
  module V1
    class NotificationsController < BaseController
      LIMIT = 40
      before_action :require_login!

      # GET /api/v1/notifications  ->  { unread:, items: [...] } newest first
      def index
        items = current_user.notifications.newest.limit(LIMIT)
        render json: { unread: current_user.notifications.unread.count, items: NotificationSerializer.collection(items) }
      end

      # POST /api/v1/notifications/read   marks everything as read
      def read_all
        current_user.notifications.unread.update_all(read_at: Time.current)
        head :no_content
      end
    end
  end
end
