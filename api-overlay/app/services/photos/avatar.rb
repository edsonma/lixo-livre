# Turns the picture a person chose for their profile into a small square JPEG: centred crop, EXIF
# orientation applied, then every piece of metadata dropped (a phone photo carries GPS and device info).
# Faces are not blurred: this is the person's own picture of themselves, shown on their own profile.
class Photos::Avatar
  class Invalid < StandardError; end

  SIZE = 512
  QUALITY = 85
  MAX_UPLOAD_BYTES = 8 * 1024 * 1024

  def self.call(bytes)
    new(bytes).call
  end

  def initialize(bytes)
    @bytes = bytes.to_s.b
  end

  # -> the JPEG bytes
  def call
    raise Invalid, "empty file" if @bytes.empty?
    raise Invalid, "file too large" if @bytes.bytesize > MAX_UPLOAD_BYTES

    image = Vips::Image.thumbnail_buffer(@bytes, SIZE, height: SIZE, crop: :centre, export_profile: "srgb") # also applies the EXIF orientation
    image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
    image.colourspace(:srgb).write_to_buffer(".jpg", Q: QUALITY, strip: true, optimize_coding: true)
  rescue Vips::Error => e
    raise Invalid, e.message
  end
end
