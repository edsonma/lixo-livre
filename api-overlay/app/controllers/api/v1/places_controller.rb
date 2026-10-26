module Api
  module V1
    # A "place" is one map cell (H3 resolution 9, a few hundred meters across): the unit of the heat map.
    class PlacesController < BaseController
      H3_FORMAT = /\A[0-9a-f]{15}\z/
      PHOTOS = 30

      # GET /api/v1/places/:h3_index   everything the place screen shows: the latest report, the
      # cleanliness over time and the photos. 404 when the cell has no published reports.
      def show
        h3 = params[:h3_index].to_s
        raise ActiveRecord::RecordNotFound unless h3.match?(H3_FORMAT)

        reports = Trash.for_heatmap.where(h3_index: h3).with_attached_photo.includes(:user).order(taken_at: :desc)
        latest = reports.first or raise ActiveRecord::RecordNotFound

        cell = HeatCell.find_by(h3_index: h3, resolution: Trash::H3_RESOLUTION)
        render json: {
          h3: h3,
          center: { lat: latest.lonlat.y, lng: latest.lonlat.x },
          score: cell&.score&.round(2),
          reports_count: reports.count,
          latest: serialize_trash(latest),
          history: PlaceHistory.monthly(reports.pluck(:severity, :taken_at)),
          photos: reports.limit(PHOTOS).map { |t| serialize_trash(t) }
        }
      end
    end
  end
end
