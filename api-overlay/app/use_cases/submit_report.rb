# A person's new report: checks the position, stores the photo and starts the pipeline (the model's
# after_create hook queues SanitizePhotoJob). The AI scores it later; the app polls for the result.
# Raises InvalidPosition for a latitude/longitude that does not exist, and RecordInvalid for the rest.
class SubmitReport
  class InvalidPosition < StandardError; end

  def self.call(**args) = new(**args).call

  def initialize(device:, user:, photo:, lat:, lng:, taken_at:, extra_info: nil, kind: nil)
    @device = device
    @user = user
    @photo = photo
    @lat = lat
    @lng = lng
    @taken_at = taken_at
    @extra_info = extra_info
    @kind = kind
  end

  def call
    lat, lng = position
    @device.trashes.new(
      user: @user, lonlat: Trash.point(lng, lat), taken_at: @taken_at,
      extra_info: @extra_info, kind: @kind.presence || "dirty", photo: @photo
    ).tap(&:save!)
  end

  private

  def position
    lat = Float(@lat.to_s, exception: false)
    lng = Float(@lng.to_s, exception: false)
    raise InvalidPosition unless lat&.between?(-90, 90) && lng&.between?(-180, 180)

    [lat, lng]
  end
end
