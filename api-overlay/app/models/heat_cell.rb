class HeatCell < ApplicationRecord
  HALF_LIFE_DAYS = HeatScore::HALF_LIFE_DAYS # a report loses half its weight every 14 days

  validates :h3_index, presence: true, uniqueness: { scope: :resolution }

  scope :in_bbox, ->(west, south, east, north) {
    where(
      "ST_Intersects(lonlat, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)",
      west.to_f, south.to_f, east.to_f, north.to_f
    )
  }

  # severity (0-100) * 0.5^(age_days / half_life) for one report. How a whole cell is scored
  # (confidence, one-person-a-day, confirmations, cleanups) is in HeatScore.
  def self.weight(severity, taken_at, now: Time.current)
    severity * HeatScore.decay(taken_at, now: now)
  end

  def recompute!
    rows = Trash.for_heatmap.where(h3_index: h3_index)
                .pluck(:severity, :taken_at, :ai_confidence, :kind, :user_id, :device_id)
                .map do |severity, taken_at, confidence, kind, user_id, device_id|
      HeatScore::Row.new(severity: severity, taken_at: taken_at, confidence: confidence, kind: kind,
                         reporter: user_id ? "u#{user_id}" : "d#{device_id}")
    end
    result = HeatScore.call(rows)

    self.resolution = Trash::H3_RESOLUTION
    self.lonlat ||= center_point
    self.score = result.score
    self.reports_count = result.count
    self.cleaned_at = result.cleaned_at
    self.computed_at = Time.current
    save!
  end

  def to_feature
    {
      type: "Feature",
      properties: { h3: h3_index, score: score.round(2), count: reports_count, cleaned: cleaned_at.present? && score < 2 },
      geometry: { type: "Point", coordinates: [lonlat.x, lonlat.y] }
    }
  end

  private

  def center_point
    lat, lng = H3.to_geo_coordinates(H3.from_string(h3_index))
    Trash.point(lng, lat)
  end
end
