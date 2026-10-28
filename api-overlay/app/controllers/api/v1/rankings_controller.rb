module Api
  module V1
    # GET /api/v1/rankings?lat=&lng=&radius_km=5
    # The worst places around a point (with their trend) and the regions ranked by how dirty they are.
    class RankingsController < BaseController
      DEFAULT_KM = 5
      MAX_KM = 25
      WORST = 10

      def index
        lat = Float(params.require(:lat))
        lng = Float(params.require(:lng))
        km = (params[:radius_km].presence || DEFAULT_KM).to_f.clamp(1, MAX_KM)

        cells = HeatQuery.near(lat, lng, km * 1000)
        worst = cells.reject(&:cleaned?).select { |c| c.score > HeatmapController::MIN_SCORE }
                     .sort_by { |c| -c.score }.first(WORST)

        render json: {
          radius_km: km,
          worst: worst.map { |c| { h3: c.h3, lat: c.lat, lng: c.lng, score: c.score.round(1), count: c.count, trend: c.trend,
                                   meters: Geo.distance_m(lat, lng, c.lat, c.lng).round } },
          regions: HeatQuery.regions(cells)
        }
      rescue ArgumentError
        render json: { error: "invalid_params" }, status: :unprocessable_entity
      end
    end
  end
end
