class Trash < ApplicationRecord
  H3_RESOLUTION = 9
  TYPES = %w[plastic paper glass metal organic construction_debris
             electronics bulky_items textile hazardous mixed other].freeze

  PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze
  MAX_PHOTO_BYTES = 15.megabytes

  # How dirty the AI says the spot is: 0 (spotless) to 100 (large illegal dump). Set by the AI only.
  SEVERITY_RANGE = (0..100).freeze

  # A photo whose EXIF position is farther than this from the reported spot, or whose EXIF time
  # differs from the reported time by more than this, goes to human review.
  # (EXIF has no time zone, so the time tolerance must cover any zone offset.)
  MAX_EXIF_DISTANCE_M = 1_000
  MAX_EXIF_TIME_SKEW = 2.days

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
  validates :severity, inclusion: { in: SEVERITY_RANGE }, allow_nil: true
  validate :trash_types_are_known
  validate :photo_is_acceptable

  before_validation :set_h3_index, if: -> { lonlat.present? }

  # Step 1 of the pipeline. SanitizePhotoJob enqueues ValidateTrashJob when it is done.
  after_create_commit { SanitizePhotoJob.perform_later(id) }
  after_commit :refresh_heat_cell, if: :affects_heatmap?

  scope :visible, -> { where(hidden_at: nil) }
  scope :published, -> { where.not(published_at: nil) }
  # The only reports that may be shown publicly or counted on the map: scored by the AI, with a
  # sanitized photo, and published by their author.
  scope :for_heatmap, -> { validated.visible.published.where.not(sanitized_at: nil) }
  # Scored but never published: the author saw the result and has not decided yet.
  scope :drafts, -> { validated.where(published_at: nil) }
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

  class NotPublishable < StandardError; end

  # With AUTO_PUBLISH=true a report goes straight to the map when the AI validates it, with no
  # "Publicar" step (for clients that do not show the analysis screen).
  def self.auto_publish?
    DemoMode::TRUE_VALUES.include?(ENV["AUTO_PUBLISH"].to_s.strip.downcase)
  end

  def published?
    published_at.present?
  end

  # Scored, photo sanitized, still private: the author may publish it.
  def publishable?
    validated? && sanitized_at.present? && hidden_at.nil? && !published?
  end

  def publish!
    raise NotPublishable, "report #{id} cannot be published (status #{ai_status}, published: #{published?})" unless publishable?

    update!(published_at: Time.current)
  end

  # The author changed their mind. Only an unpublished report can be thrown away this way.
  def discard_draft!
    raise NotPublishable, "report #{id} is already published" if published?

    destroy!
  end

  # Used when the pipeline cannot finish: keeps the report private until a human looks at it.
  def hold_for_review!(reason)
    update_columns(
      ai_status: "needs_review",
      ai_payload: (ai_payload || {}).merge("hold_reason" => reason),
      updated_at: Time.current
    )
  end

  # --- human review (admins and moderators) ---

  class NotReviewable < StandardError; end

  # A held report (needs_review): a person looked at the protected photo and decided the severity.
  # It goes to the map right away. A photo that was never sanitized cannot be approved.
  def approve_after_review!(severity:, types: nil, reviewer: nil)
    raise NotReviewable, "report #{id} is not waiting for review" unless needs_review?
    raise NotReviewable, "report #{id} has no protected photo yet" unless sanitized_at.present?

    update!(
      ai_status: :validated, severity: severity, trash_types: types.nil? ? trash_types : types,
      validated_at: Time.current, published_at: Time.current,
      ai_payload: (ai_payload || {}).merge("reviewed" => "approved", "reviewer_id" => reviewer&.id)
    )
  end

  def reject_after_review!(reviewer: nil)
    raise NotReviewable, "report #{id} is not waiting for review" unless needs_review?

    update_columns(ai_status: "rejected", updated_at: Time.current,
                   ai_payload: (ai_payload || {}).merge("reviewed" => "rejected", "reviewer_id" => reviewer&.id))
    photo.purge_later
  end

  # A published photo people reported: the moderator says it is fine ...
  def keep_after_flags!
    transaction do
      flags.pending.update_all(status: "dismissed")
      update!(hidden_at: nil)
    end
  end

  # ... or takes it down.
  def take_down_after_flags!
    transaction do
      flags.pending.update_all(status: "resolved")
      update!(hidden_at: hidden_at || Time.current)
    end
  end

  # True when the EXIF data read at upload contradicts the report (see the constants above).
  def metadata_suspicious?
    distance = photo_meta["exif_distance_m"]
    return true if distance && distance > max_exif_distance_m

    exif_time = photo_meta["exif_taken_at"]
    return false unless exif_time

    (Time.zone.parse(exif_time) - taken_at).abs > MAX_EXIF_TIME_SKEW.to_i
  end

  # EXIF_MAX_DISTANCE_M (meters) overrides the default; useful for testing with gallery photos.
  def max_exif_distance_m
    Float(ENV.fetch("EXIF_MAX_DISTANCE_M", MAX_EXIF_DISTANCE_M))
  rescue ArgumentError
    MAX_EXIF_DISTANCE_M
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
