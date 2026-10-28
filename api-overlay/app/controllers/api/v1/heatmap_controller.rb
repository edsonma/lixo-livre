module Api
  module V1
    class HeatmapController < BaseController
      MIN_SCORE = 2 # cells that have cooled below this (severity 0-100, decayed) are not drawn
      CLEANED_SHOWN_DAYS = 30 # ... except a cell that was cleaned recently: it stays as a green pin

      # GET /api/v1/heatmap?bbox=west,south,east,north  ->  GeoJSON FeatureCollection of cell centers
      def index
        west, south, east, north = params.require(:bbox).split(",").map(&:to_f)

        cells = HeatCell.in_bbox(west, south, east, north)
                        .where("score > ? OR cleaned_at > ?", MIN_SCORE, CLEANED_SHOWN_DAYS.days.ago)
                        .limit(5_000)

        render json: { type: "FeatureCollection", features: cells.map(&:to_feature) }
      end
    end
  end
end
