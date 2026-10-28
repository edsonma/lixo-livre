module Api
  module V1
    class HeatmapController < BaseController
      MIN_SCORE = 2 # cells that have cooled below this (severity 0-100, decayed) are not drawn
      CLEANED_SHOWN_DAYS = 30 # ... except a cell that was cleaned recently: it stays as a green pin

      # GET /api/v1/heatmap?bbox=west,south,east,north  ->  GeoJSON FeatureCollection of cell centers
      # Optional: days=7|30|90 (only recent reports) and type=plastic (only that kind of trash).
      # With either, cells are scored live from the reports (HeatQuery); without, from the stored scores.
      def index
        west, south, east, north = params.require(:bbox).split(",").map(&:to_f)

        days = params[:days].presence&.to_i
        type = params[:type].presence
        days = nil unless HeatQuery::PERIODS.include?(days)
        type = nil unless Trash::TYPES.include?(type)
        if days || type
          cells = HeatQuery.in_bbox(west, south, east, north, days: days, type: type)
          return render json: { type: "FeatureCollection", features: cells.select { |c| c.score > MIN_SCORE || c.cleaned? }.map(&:to_feature) }
        end

        cells = HeatCell.in_bbox(west, south, east, north)
                        .where("score > ? OR cleaned_at > ?", MIN_SCORE, CLEANED_SHOWN_DAYS.days.ago)
                        .limit(5_000)

        render json: { type: "FeatureCollection", features: cells.map(&:to_feature) }
      end
    end
  end
end
