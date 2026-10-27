module Api
  module V1
    class MeController < BaseController
      FEED_LIMIT = 90

      before_action :require_login!
      before_action :require_device!, except: :feed

      # GET /api/v1/me/trashes   the "my pictures" feed in the mobile app (all statuses)
      # photo_url is only given once the photo has been sanitized (faces and
      # plates blurred), so the app never displays or links the raw original.
      def trashes
        trashes = @device.trashes.with_attached_photo.order(taken_at: :desc).limit(50)

        render json: trashes.map { |t| serialize_own_trash(t) }
      end

      # GET /api/v1/me/feed   everything this account has sent, from any device, newest first: the profile grid.
      # thumb_url is a small square crop for the grid; photo_url is the full photo.
      def feed
        reports = current_user.trashes.with_attached_photo.order(taken_at: :desc).limit(FEED_LIMIT)

        render json: reports.map { |t| serialize_own_trash(t) }
      end

      # GET /api/v1/me/trashes/:id   poll one report after uploading it:
      # stage goes protecting_photo -> analyzing -> scored | not_trash | in_review, and done flips to true.
      # "scored" waits for the author: POST .../publish puts it on the map (stage "published"), DELETE throws it away.
      def show
        render json: serialize_own_trash(@device.trashes.with_attached_photo.find(params[:id]))
      end

      # POST /api/v1/me/trashes/:id/publish   the author confirmed the AI's result: put it on the map
      def publish
        trash = @device.trashes.with_attached_photo.find(params[:id])
        trash.publish!
        render json: serialize_own_trash(trash)
      rescue Trash::NotPublishable => e
        render json: { error: "not_publishable", message: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/me/trashes/:id   "Voltar": throw away a report that was not published
      def destroy
        @device.trashes.find(params[:id]).discard_draft!
        head :no_content
      rescue Trash::NotPublishable => e
        render json: { error: "already_published", message: e.message }, status: :unprocessable_entity
      end

      private

      def serialize_own_trash(trash)
        ready = trash.sanitized_at.present?
        {
          id: trash.id,
          ai_status: trash.ai_status,
          stage: stage_of(trash),
          done: !trash.pending?,
          severity: trash.severity,
          trash_types: trash.trash_types,
          taken_at: trash.taken_at,
          lat: trash.lonlat.y,
          lng: trash.lonlat.x,
          published: trash.published?,
          can_publish: trash.publishable?,
          photo_ready: ready,
          photo_url: ready ? url_for(trash.photo) : nil,
          thumb_url: ready ? url_for(trash.photo.variant(resize_to_fill: [360, 360])) : nil
        }
      end

      def stage_of(trash)
        case trash.ai_status
        when "validated" then trash.published? ? "published" : "scored"
        when "rejected" then "not_trash"
        when "needs_review" then "in_review"
        else trash.sanitized_at ? "analyzing" : "protecting_photo"
        end
      end
    end
  end
end
