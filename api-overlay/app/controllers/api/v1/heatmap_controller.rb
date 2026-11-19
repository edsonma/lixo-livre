module Api
  module V1
    class HeatmapController < BaseController
      MIN_SCORE = 2 # cells that have cooled below this (severity 0-100, decayed) are not drawn
      CLEANED_SHOWN_DAYS = 30 # ... except a cell that was cleaned recently: it stays as a green pin

      # GET /api/v1/heatmap?bbox=west,south,east,north  ->  GeoJSON FeatureCollection of cell centers
      # Optional: days=7|30|90 (only recent reports) and type=plastic (only that kind of trash).
      # With either, cells are scored live from the reports (Heat::Query); without, from the stored scores.
      def index
        west, south, east, north = parse_bbox
        return render(json: { error: "invalid_params", message: "bbox must be west,south,east,north" }, status: :unprocessable_entity) unless west

        days = params[:days].presence&.to_i
        type = params[:type].presence
        days = nil unless Heat::Query::PERIODS.include?(days)
        type = nil unless Trash::TYPES.include?(type)
        if days || type
          cells = Heat::Query.in_bbox(west, south, east, north, days: days, type: type)
          return render json: { type: "FeatureCollection", features: cells.select { |c| c.score > MIN_SCORE || c.cleaned? }.map(&:to_feature) }
        end

        cells = HeatCell.in_bbox(west, south, east, north)
                        .where("score > ? OR cleaned_at > ?", MIN_SCORE, CLEANED_SHOWN_DAYS.days.ago)
                        .limit(5_000)

        # A published report whose cell was not made (yet) is still drawn, scored from the report itself.
        unstored = Heat::Query.unstored_in_bbox(west, south, east, north).select { |c| c.score > MIN_SCORE || c.cleaned? }

        render json: { type: "FeatureCollection", features: cells.map(&:to_feature) + unstored.map(&:to_feature) }
      end

      PHOTO_PINS_LIMIT = 300

      # GET /api/v1/heatmap/reports?bbox=west,south,east,north   (+ days, type like the heatmap)
      # The published reports in view, one point each, for the small photo pins shown when the map is zoomed in.
      # Only what the place screen already shows to everybody: where, how bad, when. No photo, no name.
      def reports
        west, south, east, north = parse_bbox
        return render(json: { error: "invalid_params", message: "bbox must be west,south,east,north" }, status: :unprocessable_entity) unless west

        days = params[:days].presence&.to_i
        type = params[:type].presence
        scope = Trash.for_heatmap.where.not(h3_index: nil).where(
          "ST_Intersects(lonlat, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)", west, south, east, north
        )
        scope = Heat::Query.filter(scope, Heat::Query::PERIODS.include?(days) ? days : nil, Trash::TYPES.include?(type) ? type : nil, Time.now)

        features = scope.order(taken_at: :desc).limit(PHOTO_PINS_LIMIT).map do |t|
          { type: "Feature",
            properties: { id: t.id, h3: t.h3_index, severity: t.severity, kind: t.kind, taken_at: t.taken_at },
            geometry: { type: "Point", coordinates: [t.lonlat.x, t.lonlat.y] } }
        end
        render json: { type: "FeatureCollection", features: features }
      end

      private

      # [west, south, east, north] as numbers, or nil. A map zoomed far out can report longitudes beyond
      # +-180 (the world repeats), so the values are clamped rather than refused.
      def parse_bbox
        parts = params.require(:bbox).to_s.split(",", -1)
        numbers = parts.map { |part| Float(part, exception: false) }
        return nil unless numbers.size == 4 && numbers.all? { |n| n&.finite? }

        west, south, east, north = numbers
        [west.clamp(-180, 180), south.clamp(-90, 90), east.clamp(-180, 180), north.clamp(-90, 90)]
      end
    end
  end
end
