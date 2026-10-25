class HeatCell < ApplicationRecord
  HALF_LIFE_DAYS = 14 # a report loses half its weight every 14 days

  validates :h3_index, presence: true, uniqueness: { scope: :resolution }

  scope :in_bbox, ->(west, south, east, north) {
    where(
      "ST_Intersects(lonlat, ST_MakeEnvelope(?, ?, ?, ?, 4326)::geography)",
      west.to_f, south.to_f, east.to_f, north.to_f
    )
  }

  # severity (0-100) * 0.5^(age_days / half_life); a cell's score is the sum over its reports
  def self.weight(severity, taken_at, now: Time.current)
    age_days = [(now - taken_at) / 1.day, 0].max
    severity * (0.5**(age_days / HALF_LIFE_DAYS))
  end

  def recompute!
    rows = Trash.for_heatmap.where(h3_index: h3_index).pluck(:severity, :taken_at)

    self.resolution = Trash::H3_RESOLUTION
    self.lonlat ||= center_point
    self.score = rows.sum { |severity, taken_at| self.class.weight(severity, taken_at) }
    self.reports_count = rows.size
    self.computed_at = Time.current
    save!
  end

  def to_feature
    {
      type: "Feature",
      properties: { h3: h3_index, score: score.round(2), count: reports_count },
      geometry: { type: "Point", coordinates: [lonlat.x, lonlat.y] }
    }
  end

  private

  def center_point
    lat, lng = H3.to_geo_coordinates(H3.from_string(h3_index))
    Trash.point(lng, lat)
  end
end
