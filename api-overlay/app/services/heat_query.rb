# Scores map cells live from their reports, for questions the stored HeatCell score cannot answer:
# "only the last 7 days", "only plastic", "is it getting worse?", "which places are the worst near me?".
#
# The scoring rules are HeatScore's; this class only picks the reports and groups them by cell.
class HeatQuery
  PERIODS = [7, 30, 90].freeze
  TREND_DAYS = 14        # compare the score now with the score this many days ago
  TREND_THRESHOLD = 5    # a change smaller than this (points of 100) is "stable"
  REGION_RESOLUTION = 7  # H3 cells of a few km: the "bairro" level of the ranking
  MAX_ROWS = 20_000

  Cell = Struct.new(:h3, :lat, :lng, :score, :count, :cleaned_at, :trend, keyword_init: true) do
    def cleaned? = cleaned_at.present? && score < 2

    def to_feature
      {
        type: "Feature",
        properties: { h3: h3, score: score.round(2), count: count, cleaned: cleaned?, trend: trend[:label] },
        geometry: { type: "Point", coordinates: [lng, lat] }
      }
    end
  end

  # { delta:, label: "worse" | "better" | "stable" } for one cell's rows
  def self.trend(rows, now: Time.now)
    before = now - TREND_DAYS * 86_400
    now_score = HeatScore.call(rows, now: now).score
    old_score = HeatScore.call(rows.select { |r| r.taken_at <= before }, now: before).score
    delta = (now_score - old_score).round(1)
    label = delta >= TREND_THRESHOLD ? "worse" : delta <= -TREND_THRESHOLD ? "better" : "stable"
    { delta: delta, label: label }
  end

  # { h3 => [Row] }  ->  [Cell], keeping cells that still have a score or were cleaned
  def self.cells_from(grouped, now: Time.now)
    grouped.filter_map do |h3, rows|
      result = HeatScore.call(rows, now: now)
      next if result.score <= 0 && result.cleaned_at.nil?

      lat, lng = H3.to_geo_coordinates(H3.from_string(h3))
      Cell.new(h3: h3, lat: lat, lng: lng, score: result.score, count: result.count,
               cleaned_at: result.cleaned_at, trend: trend(rows, now: now))
    end
  end

  # Regions (H3 resolution 7) ranked by the average score of their cells, worst first.
  # parent_of is injectable so the grouping can be tested without the H3 library.
  def self.regions(cells, limit: 8, parent_of: ->(h3) { H3.to_string(H3.parent(H3.from_string(h3), REGION_RESOLUTION)) })
    cells.group_by { |c| parent_of.call(c.h3) }.map do |region, group|
      dirty = group.reject(&:cleaned?)
      next if dirty.empty?

      lat, lng = H3.to_geo_coordinates(H3.from_string(region))
      deltas = dirty.map { |c| c.trend[:delta] }
      mean_delta = (deltas.sum / deltas.size).round(1)
      { region: region, lat: lat, lng: lng, score: (dirty.sum(&:score) / dirty.size).round(1), cells: dirty.size,
        trend: { delta: mean_delta, label: mean_delta >= TREND_THRESHOLD ? "worse" : mean_delta <= -TREND_THRESHOLD ? "better" : "stable" } }
    end.compact.sort_by { |r| -r[:score] }.first(limit)
  end

  # Cells inside a bounding box, optionally only the last `days` days and one trash type.
  def self.in_bbox(west, south, east, north, days: nil, type: nil, now: Time.now)
    scope = Trash.for_heatmap.where(
      "ST_Intersects(lonlat, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)", west.to_f, south.to_f, east.to_f, north.to_f
    )
    cells_from(group(filter(scope, days, type, now)), now: now)
  end

  # Cells within radius_m meters of a point (all of their history: the ranking wants the trend).
  def self.near(lat, lng, radius_m, now: Time.now)
    scope = Trash.for_heatmap.where("ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
                                    lng.to_f, lat.to_f, radius_m.to_f)
    cells_from(group(scope), now: now)
  end

  def self.filter(scope, days, type, now)
    scope = scope.where("taken_at >= ?", now - days * 86_400) if days
    # a cleanup has no trash types: keep it, it still says the place was cleaned
    scope = scope.where("? = ANY(trash_types) OR kind = 'cleanup'", type) if type
    scope
  end

  def self.group(scope)
    scope.limit(MAX_ROWS).pluck(:h3_index, :severity, :taken_at, :ai_confidence, :kind, :user_id, :device_id)
         .group_by(&:first).transform_values do |list|
      list.map do |_, severity, taken_at, confidence, kind, user_id, device_id|
        HeatScore::Row.new(severity: severity, taken_at: taken_at, confidence: confidence, kind: kind,
                           reporter: user_id ? "u#{user_id}" : "d#{device_id}")
      end
    end
  end
end
