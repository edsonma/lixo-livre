require "test_helper"

# Pure byte handling, no libvips needed. `sanitized` stands in for what PhotoSanitizer encodes:
# a JPEG with no metadata of its own.
class ExifPreserverTest < ActiveSupport::TestCase
  PREVIEW_DATA = (0x80..0xFF).to_a.pack("C*").byteslice(0, 32) # binary bytes inside the fixture's fake preview

  def sanitized = file_fixture("plain.jpg").binread
  def phone_photo = file_fixture("exif_thumbnail.jpg").binread

  def copy(original = phone_photo, width: 120, height: 80)
    ExifPreserver.copy(original, into: sanitized, width: width, height: height)
  end

  test "keeps GPS, capture time and camera make and model" do
    result = copy
    metadata = PhotoMetadata.read(result)

    assert_predicate metadata, :exif?
    assert_predicate metadata, :gps?
    assert_in_delta(-15.7942, metadata.lat, 1e-4)
    assert_in_delta(-47.8825, metadata.lng, 1e-4)
    assert_equal Time.utc(2026, 10, 20, 14, 30), metadata.taken_at
    assert_includes result, "FakeCam"
    assert_includes result, "PhotoPhone 9"
  end

  test "works with a big-endian EXIF block too" do
    result = copy(file_fixture("exif_gps_bigendian.jpg").binread)
    metadata = PhotoMetadata.read(result)

    assert_in_delta 40.7128, metadata.lat, 1e-4
    assert_in_delta(-74.0060, metadata.lng, 1e-4)
  end

  test "drops the embedded preview image: it was made from the unblurred original" do
    assert_includes phone_photo, "UNBLURRED-THUMBNAIL-BYTES", "the fixture starts with a preview"

    assert_not_includes copy, "UNBLURRED-THUMBNAIL"
  end

  test "drops the maker note" do
    assert_includes phone_photo, "SECRET-MAKERNOTE-PREVIEW-DATA", "the fixture starts with a maker note"

    assert_not_includes copy, "SECRET-MAKERNOTE"
  end

  test "leaves out owner name, description, serial number and other private fields" do
    original = phone_photo
    %w[SECRET-DESCRIPTION SECRET-ARTIST SECRET-SERIAL].each { |secret| assert_includes original, secret }

    result = copy

    %w[SECRET-DESCRIPTION SECRET-ARTIST SECRET-SERIAL].each { |secret| assert_not_includes result, secret }
  end

  test "keeps the lens name" do
    assert_includes copy, "FakeLens 24mm"
  end

  test "writes a fresh block of its own: far smaller than the original" do
    assert_operator copy.bytesize - sanitized.bytesize, :<, phone_photo.bytesize / 2
  end

  test "resets Orientation to 1 because the pixels are already upright" do
    assert_equal 6, PhotoMetadata.read(phone_photo).orientation

    assert_equal 1, PhotoMetadata.read(copy).orientation
  end

  test "updates the pixel size to the new image" do
    assert_equal [4000, 3000], PhotoMetadata.read(phone_photo).then { |m| [m.pixel_width, m.pixel_height] }

    metadata = PhotoMetadata.read(copy(width: 80, height: 120))

    assert_equal [80, 120], [metadata.pixel_width, metadata.pixel_height]
  end

  test "puts the EXIF right after the start of image and leaves the rest of the JPEG as it was" do
    result = copy

    assert_equal "\xFF\xD8\xFF\xE1".b, result.byteslice(0, 4)
    segment_length = result.byteslice(4, 2).unpack1("n")
    assert_equal sanitized.byteslice(2..), result.byteslice(2 + 2 + segment_length..)
  end

  test "does not modify the original bytes it was given" do
    original = phone_photo
    before = original.dup

    ExifPreserver.copy(original, into: sanitized, width: 120, height: 80)

    assert_equal before, original
  end

  test "a photo without EXIF comes back untouched" do
    assert_equal sanitized, ExifPreserver.copy(sanitized, into: sanitized, width: 64, height: 48)
  end

  test "never raises and never leaks on damaged EXIF: either clean metadata or none" do
    random = Random.new(11)
    200.times do
      corrupted = phone_photo.dup
      random.rand(1..8).times { corrupted.setbyte(random.rand(0...400), random.rand(256)) }

      result = ExifPreserver.copy(corrupted, into: sanitized, width: 120, height: 80)

      assert_not_includes result, PREVIEW_DATA # the binary part of the preview, not just the marker text
      assert_not_includes result, "SECRET-MAKERNOTE"
      assert_not_includes result, "SECRET-SERIAL"
      assert_equal "\xFF\xD8".b, result.byteslice(0, 2)
    end
  end

  test "a truncated EXIF block gives no metadata instead of an error" do
    assert_equal sanitized, ExifPreserver.copy(phone_photo.byteslice(0, 100), into: sanitized, width: 1, height: 1)
  end

  test "input that is not a JPEG is returned as it came" do
    assert_equal "not a jpeg", ExifPreserver.copy(phone_photo, into: "not a jpeg", width: 1, height: 1)
  end

  # --- strip ---

  test "strip removes the EXIF and nothing else" do
    stripped = ExifPreserver.strip(copy)

    assert_not PhotoMetadata.read(stripped).exif?
    assert_equal sanitized, stripped
  end

  test "strip leaves a photo without EXIF byte for byte as it was" do
    assert_equal sanitized, ExifPreserver.strip(sanitized)
  end

  test "strip returns input that is not a JPEG as it came" do
    assert_equal "junk", ExifPreserver.strip("junk")
    assert_equal "", ExifPreserver.strip("")
  end

  test "strip also removes the original uploaded EXIF, preview and all" do
    stripped = ExifPreserver.strip(phone_photo)

    assert_not PhotoMetadata.read(stripped).exif?
    assert_not_includes stripped, "FakeCam"
  end
end
