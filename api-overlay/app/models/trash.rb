class Trash < ApplicationRecord
  H3_RESOLUTION = 9
  TYPES = %w[plastic paper glass metal organic construction_debris
             electronics bulky_items textile hazardous mixed other].freeze

  belongs_to :device
  belongs_to :user, optional: true
  has_many :flags, dependent: :destroy
  has_one_attached :photo

  enum :ai_status, {
    pending: "pending",
    validated: "validated",
    rejected: "rejected",
    needs_review: "needs_review"
  }, default: "pending"

  validates :photo, :lonlat, :taken_at, presence: true
  validates :severity, inclusion: { in: 1..5 }, allow_nil: true
  validate :trash_types_are_known

  before_validation :set_h3_index, if: -> { lonlat.present? }

  after_create_commit { ValidateTrashJob.perform_later(id) }
  after_commit :refresh_heat_cell, if: :affects_heatmap?

  scope :visible, -> { where(hidden_at: nil) }
  scope :for_heatmap, -> { validated.visible }
  scope :near, ->(lng, lat, meters) {
    where(
      "ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)",
      lng.to_f, lat.to_f, meters.to_f
    )
  }

  # Geographic point helper: Trash.point(lng, lat)
  def self.point(lng, lat)
    RGeo::Geographic.spherical_factory(srid: 4326).point(lng.to_f, lat.to_f)
  end

  def hide!
    update!(hidden_at: Time.current)
  end

  private

  def set_h3_index
    cell = H3.from_geo_coordinates([lonlat.y, lonlat.x], H3_RESOLUTION)
    self.h3_index = H3.to_string(cell)
  end

  def trash_types_are_known
    unknown = trash_types - TYPES
    errors.add(:trash_types, "unknown: #{unknown.join(', ')}") if unknown.any?
  end

  # Re-score the cell when a report enters or leaves the heatmap
  def affects_heatmap?
    saved_change_to_ai_status? || saved_change_to_hidden_at?
  end

  def refresh_heat_cell
    RefreshHeatCellJob.perform_later(h3_index)
  end
end
