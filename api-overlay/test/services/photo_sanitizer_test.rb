require "test_helper"

# Needs libvips (see README). The fixtures are 200x150 noise images, so a redacted region is easy
# to tell from an untouched one: noise has a high standard deviation, a mosaic has a very low one.
class PhotoSanitizerTest < ActiveSupport::TestCase
  # Stands in for the real detector and remembers what it was shown.
  class RecordingDetector
    attr_reader :seen

    def initialize(*regions)
      @regions = regions.map { |r| PrivacyRegion.from_hash(r) }
    end

    def detect(bytes)
      @seen = bytes
      @regions
    end
  end

  FACE = { kind: "face", x: 0.25, y: 0.25, width: 0.25, height: 0.25 }.freeze # padded: about (40,30) to (110,83)
  INSIDE = [55, 40, 40, 32].freeze  # fully inside the redacted box
  OUTSIDE = [150, 100, 40, 40].freeze # nowhere near it

  def exif_photo = file_fixture("exif_gps.jpg").binread

  def sanitize(bytes = exif_photo, *regions)
    PhotoSanitizer.call(bytes, detector: RecordingDetector.new(*regions))
  end

  test "keeps GPS, capture time and camera make and model by default" do
    assert PhotoMetadata.read(exif_photo).exif?, "fixture should start with EXIF"

    result = sanitize
    metadata = PhotoMetadata.read(result.data)

    assert_predicate result, :metadata_kept
    assert_predicate metadata, :gps?
    assert_in_delta(-15.7942, metadata.lat, 1e-4)
    assert_in_delta(-47.8825, metadata.lng, 1e-4)
    assert_equal Time.utc(2026, 10, 20, 14, 30), metadata.taken_at
    assert_includes result.data.b, "FakeCam"
    assert_includes result.data.b, "PhotoPhone 9"
  end

  test "the kept EXIF has no embedded preview image, maker note or private fields" do
    result = sanitize(file_fixture("exif_thumbnail.jpg").binread)

    assert_predicate result, :metadata_kept
    assert_includes result.data.b, "FakeCam"
    %w[UNBLURRED-THUMBNAIL SECRET-MAKERNOTE SECRET-DESCRIPTION SECRET-ARTIST SECRET-SERIAL].each do |secret|
      assert_not_includes result.data.b, secret
    end
  end

  test "strips every trace of EXIF when told to" do
    result = PhotoSanitizer.call(exif_photo, detector: RecordingDetector.new, keep_metadata: false)

    assert_not result.metadata_kept
    assert_not PhotoMetadata.read(result.data).exif?
    assert_not_includes result.data.b, "FakeCam"
    assert_not_includes result.data.b, "Exif".b
  end

  test "STRIP_PHOTO_METADATA=true switches the EXIF copy off" do
    with_env("STRIP_PHOTO_METADATA" => "true") do
      assert_not PhotoSanitizer.keep_metadata?
      assert_not PhotoMetadata.read(sanitize.data).exif?
    end
    with_env("STRIP_PHOTO_METADATA" => nil) { assert PhotoSanitizer.keep_metadata? }
    with_env("STRIP_PHOTO_METADATA" => "false") { assert PhotoSanitizer.keep_metadata? }
  end

  test "a photo that had no EXIF has none afterwards" do
    result = sanitize(file_fixture("plain.jpg").binread)

    assert_not result.metadata_kept
    assert_not PhotoMetadata.read(result.data).exif?
  end

  test "output is a JPEG with the dimensions reported" do
    result = sanitize

    assert_equal "image/jpeg", result.content_type
    assert_equal "\xFF\xD8".b, result.data.byteslice(0, 2)
    image = decode(result.data)
    assert_equal [200, 150], [image.width, image.height]
    assert_equal [200, 150], [result.width, result.height]
    assert_equal 3, image.bands
  end

  test "the detector only ever sees metadata-free pixels" do
    detector = RecordingDetector.new
    PhotoSanitizer.call(exif_photo, detector: detector)

    assert_not_nil detector.seen
    assert_equal "\xFF\xD8".b, detector.seen.byteslice(0, 2)
    assert_not PhotoMetadata.read(detector.seen).exif?
    assert_not_includes detector.seen.b, "FakeCam"
  end

  test "blurs detected regions into a mosaic" do
    original = decode(exif_photo)
    result = sanitize(exif_photo, FACE)
    sanitized = decode(result.data)

    before = deviation_in(original, INSIDE)
    after = deviation_in(sanitized, INSIDE)

    assert_operator before, :>, 30, "fixture should be noisy"
    assert_operator after, :<, before * 0.35, "region should be flattened (was #{before.round(1)}, now #{after.round(1)})"
  end

  test "leaves the rest of the photo alone" do
    original = decode(exif_photo)
    sanitized = decode(sanitize(exif_photo, FACE).data)

    assert_operator deviation_in(sanitized, OUTSIDE), :>, deviation_in(original, OUTSIDE) * 0.7
  end

  test "without regions nothing is blurred and nothing is reported" do
    original = decode(exif_photo)
    result = sanitize

    assert_operator deviation_in(decode(result.data), INSIDE), :>, deviation_in(original, INSIDE) * 0.7
    assert_equal({}, result.redactions)
  end

  test "counts redactions by kind" do
    result = sanitize(exif_photo, FACE, FACE.merge(kind: "face", x: 0.6), FACE.merge(kind: "license_plate", y: 0.6))

    assert_equal({ "face" => 2, "license_plate" => 1 }, result.redactions)
  end

  test "redacts several regions, including ones at the edge of the image" do
    edge = { kind: "face", x: 0.9, y: 0.9, width: 0.2, height: 0.2 } # sticks out of the bottom-right corner
    sanitized = decode(sanitize(exif_photo, FACE, edge).data)

    assert_operator deviation_in(sanitized, INSIDE), :<, 20
    assert_operator deviation_in(sanitized, [185, 138, 15, 12]), :<, 20
  end

  test "applies the EXIF rotation before anything else" do
    result = sanitize(file_fixture("exif_rotated.jpg").binread) # stored 120x80 with Orientation=6

    assert_equal [80, 120], [result.width, result.height]
    image = decode(result.data)
    assert_equal [80, 120], [image.width, image.height]
    metadata = PhotoMetadata.read(result.data)
    assert_equal 1, metadata.orientation # the pixels are already upright, so viewers must not rotate again
    assert_equal [80, 120], [metadata.pixel_width, metadata.pixel_height]
  end

  test "shrinks big photos to the maximum dimension, keeping the aspect ratio" do
    big = Vips::Image.black(3000, 2000, bands: 3).write_to_buffer(".jpg")

    result = sanitize(big)

    assert_equal PhotoSanitizer::MAX_DIMENSION, result.width
    assert_in_delta 1365, result.height, 1
  end

  test "does not enlarge small photos" do
    result = sanitize(file_fixture("plain.jpg").binread)

    assert_equal [64, 48], [result.width, result.height]
  end

  test "flattens transparency onto white and outputs a 3-band JPEG" do
    rgb = Vips::Image.black(40, 40, bands: 3).copy(interpretation: :srgb)
    transparent_png = rgb.bandjoin(0).write_to_buffer(".png") # fully transparent black pixels

    image = decode(sanitize(transparent_png).data)

    assert_equal 3, image.bands
    assert_in_delta 255, image.avg, 3
  end

  test "turns grayscale photos into 3-band RGB" do
    gray = Vips::Image.black(30, 30).write_to_buffer(".jpg")

    assert_equal 3, decode(sanitize(gray).data).bands
  end

  test "raises InvalidImage for bytes that are not an image" do
    assert_raises(PhotoSanitizer::InvalidImage) { sanitize("definitely not an image") }
    assert_raises(PhotoSanitizer::InvalidImage) { sanitize(file_fixture("not_an_image.pdf").binread) }
    assert_raises(PhotoSanitizer::InvalidImage) { sanitize(exif_photo.byteslice(0, 30)) } # truncated file
  end

  test "fails closed: a detector error means no output at all" do
    detector = Object.new
    def detector.detect(_bytes) = raise("detector is down")

    error = assert_raises(RuntimeError) { PhotoSanitizer.call(exif_photo, detector: detector) }
    assert_equal "detector is down", error.message
  end
end
