module Api
  module V1
    class NotificationsController < BaseController
      LIMIT = 40
      before_action :require_login!

      # GET /api/v1/notifications  ->  { unread:, items: [...] } newest first
      def index
        items = current_user.notifications.newest.limit(LIMIT)
        render json: { unread: current_user.notifications.unread.count, items: items.map { |n| serialize(n) } }
      end

      # POST /api/v1/notifications/read   marks everything as read
      def read_all
        current_user.notifications.unread.update_all(read_at: Time.current)
        head :no_content
      end

      private

      def serialize(note)
        { id: note.id, kind: note.kind, h3: note.h3_index, score: note.score&.round(1), previous_score: note.previous_score&.round(1),
          lat: note.lat, lng: note.lng, read: note.read_at.present?, created_at: note.created_at }
      end
    end
  end
end
