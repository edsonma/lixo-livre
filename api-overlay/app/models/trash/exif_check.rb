# Does the photo's own metadata agree with what the person reported? (photo_meta is read at upload,
# see PhotoMetadata.) A disagreement sends the report to human review instead of the map.
module Trash::ExifCheck
  # A photo whose EXIF position is farther than this from the reported spot, or whose EXIF time
  # differs from the reported time by more than this, goes to human review.
  # (EXIF has no time zone, so the time tolerance must cover any zone offset.)
  MAX_EXIF_DISTANCE_M = 1_000
  MAX_EXIF_TIME_SKEW = 2.days

  # True when the EXIF data read at upload contradicts the report.
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
end
