require "test_helper"

class PhotoMetadataTest < ActiveSupport::TestCase
  test "reads time and GPS from a little-endian EXIF block" do
    metadata = PhotoMetadata.read(file_fixture("exif_gps.jpg").binread)

    assert_predicate metadata, :exif?
    assert_predicate metadata, :gps?
    assert_in_delta(-15.7942, metadata.lat, 1e-6) # south is negative
    assert_in_delta(-47.8825, metadata.lng, 1e-6) # west is negative
    assert_equal Time.utc(2026, 10, 20, 14, 30, 0), metadata.taken_at
  end

  test "reads a big-endian EXIF block" do
    metadata = PhotoMetadata.read(file_fixture("exif_gps_bigendian.jpg").binread)

    assert_predicate metadata, :exif?
    assert_in_delta 40.7128, metadata.lat, 1e-5 # north is positive
    assert_in_delta(-74.0060, metadata.lng, 1e-5)
    assert_equal Time.utc(2025, 1, 2, 3, 4, 5), metadata.taken_at
  end

  test "a photo without EXIF has no metadata" do
    metadata = PhotoMetadata.read(file_fixture("plain.jpg").binread)

    assert_not metadata.exif?
    assert_not metadata.gps?
    assert_nil metadata.taken_at
    assert_nil metadata.lat
    assert_nil metadata.lng
  end

  test "never raises on input that is not a JPEG" do
    [nil, "", "hello", "\xFF\xD8".b, file_fixture("not_an_image.pdf").binread].each do |junk|
      metadata = PhotoMetadata.read(junk)

      assert_not metadata.exif?, "#{junk.inspect[0, 30]} should not look like EXIF"
    end
  end

  test "a truncated EXIF block still reports that EXIF is there, with no values" do
    metadata = PhotoMetadata.read(file_fixture("exif_gps.jpg").binread.byteslice(0, 100))

    assert_predicate metadata, :exif?
    assert_not metadata.gps?
    assert_nil metadata.taken_at
  end

  test "survives corrupted EXIF data" do
    original = file_fixture("exif_gps.jpg").binread
    random = Random.new(42)

    300.times do
      corrupted = original.dup
      random.rand(1..6).times { corrupted.setbyte(random.rand(0...300), random.rand(256)) } # hits the EXIF block

      assert_nothing_raised { PhotoMetadata.read(corrupted) }
    end
  end
end
