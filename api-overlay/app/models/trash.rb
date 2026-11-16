class Trash < ApplicationRecord
  H3_RESOLUTION = 9
  TYPES = %w[plastic paper glass metal organic construction_debris
             electronics bulky_items textile hazardous mixed other].freeze

  # "dirty": a report of trash. "cleanup": a photo showing that a reported place is clean now.
  KINDS = %w[dirty cleanup].freeze

  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  MAX_PHOTO_BYTES = 15.megabytes

  # How dirty the AI says the spot is: 0 (spotless) to 100 (large illegal dump). Set by the AI only.
  SEVERITY_RANGE = (0..100).freeze

  belongs_to :device
  belongs_to :user, optional: true
  has_many :flags, dependent: :destroy
  has_one_attached :photo

  include ExifCheck
  include Moderation
  include Publishing

  enum :ai_status, {
    pending: "pending",
    validated: "validated",
    rejected: "rejected",
    needs_review: "needs_review"
  }, default: "pending"

  validates :photo, :lonlat, :taken_at, presence: true
  validates :severity, inclusion: { in: SEVERITY_RANGE }, allow_nil: true
  validates :kind, inclusion: { in: KINDS }
  validates :extra_info, length: { maximum: 1000 }, on: :create
  validate :trash_types_are_known
  validate :photo_is_acceptable
  validate :taken_at_not_in_the_future, on: :create

  before_validation :set_h3_index, if: -> { lonlat.present? }

  # Step 1 of the pipeline. SanitizePhotoJob enqueues ValidateTrashJob when it is done.
  after_create_commit { SanitizePhotoJob.perform_later(id) }
  after_commit :refresh_heat_cell, if: :affects_heatmap?
  after_destroy_commit :refresh_heat_cell, if: -> { published_at.present? && h3_index.present? } # a withdrawn report leaves the map

  scope :visible, -> { where(hidden_at: nil) }
  scope :published, -> { where.not(published_at: nil) }
  # The only reports that may be shown publicly or counted on the map: scored by the AI, with a
  # sanitized photo, and published by their author.
  scope :for_heatmap, -> { validated.visible.published.where.not(sanitized_at: nil) }
  # Scored but never published: the author saw the result and has not decided yet.
  scope :drafts, -> { validated.where(published_at: nil) }
  # Rejected because the AI found no trash in the photo. Not a cleanup turned down (it says why), not a file
  # that could not be read, and not a rejection a person made in review. Such a photo is thrown away.
  NOT_AI_NO_TRASH_REASONS = (ReportStage::CLEANUP_REJECTIONS + %w[unreadable_image]).freeze
  scope :no_trash_found, -> {
    rejected.where("COALESCE(ai_payload ->> 'reason', '') NOT IN (?)", NOT_AI_NO_TRASH_REASONS)
            .where("ai_payload ->> 'reviewed' IS NULL")
  }
  # What the author sees in their own lists: everything except the photos the AI found no trash in.
  scope :listed, -> { where.not(id: no_trash_found.select(:id)) }
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

  def cleanup?
    kind == "cleanup"
  end

  # Is there something to clean here? A cleanup only makes sense where trash was reported.
  def dirty_reports_nearby?
    Trash.for_heatmap.where(h3_index: h3_index, kind: "dirty").where.not(id: id).exists?
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

  # taken_at is what the person says, and it sets how much the report weighs on the map (older counts less):
  # a time in the future would make a report outweigh everything else for as long as it lies ahead.
  def taken_at_not_in_the_future
    errors.add(:taken_at, "cannot be in the future") if taken_at && taken_at > 1.day.from_now # a day: time zones, wrong phone clocks
  end

  def photo_is_acceptable
    return unless photo.attached?

    unless PHOTO_CONTENT_TYPES.include?(photo.content_type)
      errors.add(:photo, "must be a JPEG, PNG, WebP or HEIC image")
    end
    errors.add(:photo, "is too large (max #{MAX_PHOTO_BYTES / 1.megabyte} MB)") if photo.byte_size > MAX_PHOTO_BYTES
  end

  # Re-score the cell when a report enters or leaves the heatmap
  def affects_heatmap?
    saved_change_to_ai_status? || saved_change_to_hidden_at? || saved_change_to_published_at?
  end

  def refresh_heat_cell
    RefreshHeatCellJob.perform_later(h3_index)
  end
end
