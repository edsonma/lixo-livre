require "vips"

# Makes an uploaded photo safe to store and show:
#
#   1. decodes it, applies the EXIF rotation, converts to sRGB, shrinks it to MAX_DIMENSION
#   2. asks the detector for faces and license plates (it only ever sees metadata-free pixels)
#   3. replaces each of those regions with a coarse mosaic
#   4. re-encodes as JPEG with ALL metadata dropped (EXIF, GPS, XMP, IPTC, ICC, thumbnails)
#
# The output is built from decoded pixels, so nothing from the original file can survive in it.
# If the detector raises, so does this: the caller must keep the photo private, never fall back
# to publishing it unblurred. Needs libvips (brew install vips / apt install libvips42).
class PhotoSanitizer
  class InvalidImage < StandardError; end

  MAX_DIMENSION = 2048
  JPEG_QUALITY = 85
  MOSAIC_CELLS = 6 # a redacted region becomes at most 6x6 blocks: no face or plate survives that

  Result = Struct.new(:data, :width, :height, :content_type, :redactions, keyword_init: true)

  # detector: anything with #detect(jpeg_bytes) returning PrivacyRegion objects
  def self.call(bytes, detector: PrivacyDetector)
    new(bytes, detector: detector).call
  end

  def initialize(bytes, detector:)
    @bytes = bytes
    @detector = detector
  end

  def call
    image = load_upright_srgb
    regions = @detector.detect(encode(image)) # metadata-free bytes: nothing sensitive leaves here
    image = redact(image, regions)

    Result.new(
      data: encode(image),
      width: image.width,
      height: image.height,
      content_type: "image/jpeg",
      redactions: regions.group_by(&:kind).transform_values(&:size)
    )
  rescue Vips::Error => e
    raise InvalidImage, e.message
  end

  private

  def load_upright_srgb
    image = Vips::Image.thumbnail_buffer(
      @bytes, MAX_DIMENSION,
      height: MAX_DIMENSION, size: :down, export_profile: "srgb" # also applies the EXIF orientation
    )
    image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
    image.colourspace(:srgb) # grayscale and CMYK become 3-band RGB
  end

  def redact(image, regions)
    regions.reduce(image) do |result, region|
      x, y, width, height = region.to_pixels(image.width, image.height)
      result.insert(mosaic(image.crop(x, y, width, height)), x, y) # always cut from the original pixels
    end
  end

  # Averages the patch down to a handful of cells, then blows the cells back up.
  def mosaic(patch)
    width = patch.width
    height = patch.height
    cols = [MOSAIC_CELLS, width].min
    rows = [MOSAIC_CELLS, height].min

    small = patch.resize(cols.fdiv(width), vscale: rows.fdiv(height), kernel: :linear)
    big = small.resize(width.fdiv(small.width), vscale: height.fdiv(small.height), kernel: :nearest)
    big.embed(0, 0, [width, big.width].max, [height, big.height].max, extend: :copy).crop(0, 0, width, height)
  end

  def encode(image)
    image.write_to_buffer(".jpg", Q: JPEG_QUALITY, strip: true, optimize_coding: true)
  end
end
