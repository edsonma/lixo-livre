require "test_helper"

class PrivacyRegionTest < ActiveSupport::TestCase
  test "builds a region from symbol or string keys" do
    a = PrivacyRegion.from_hash(kind: "face", x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    b = PrivacyRegion.from_hash("kind" => "face", "x" => 0.1, "y" => 0.2, "width" => 0.3, "height" => 0.4)

    assert_equal a, b
    assert_equal "face", a.kind
    assert_in_delta 0.1, a.x
    assert_in_delta 0.2, a.y
    assert_in_delta 0.3, a.width
    assert_in_delta 0.4, a.height
  end

  test "accepts numbers sent as strings" do
    region = PrivacyRegion.from_hash(kind: "face", x: "0.5", y: "0.5", width: "0.25", height: "0.25")

    assert_in_delta 0.5, region.x
    assert_in_delta 0.25, region.width
  end

  test "unknown kinds are kept and still redacted as other" do
    assert_equal "other", PrivacyRegion.from_hash(kind: "banana", x: 0, y: 0, width: 0.1, height: 0.1).kind
    assert_equal "other", PrivacyRegion.from_hash(x: 0, y: 0, width: 0.1, height: 0.1).kind
    assert_equal "license_plate", PrivacyRegion.from_hash(kind: :license_plate, x: 0, y: 0, width: 0.1, height: 0.1).kind
  end

  test "clamps boxes that stick out of the image" do
    region = PrivacyRegion.from_hash(kind: "face", x: -0.1, y: 0.9, width: 0.3, height: 0.3)

    assert_in_delta 0.0, region.x
    assert_in_delta 0.2, region.width
    assert_in_delta 0.9, region.y
    assert_in_delta 0.1, region.height
  end

  test "returns nil for boxes with no area inside the image" do
    assert_nil PrivacyRegion.from_hash(kind: "face", x: 1.2, y: 0.1, width: 0.1, height: 0.1) # right of the image
    assert_nil PrivacyRegion.from_hash(kind: "face", x: -0.5, y: 0.1, width: 0.2, height: 0.1) # left of the image
    assert_nil PrivacyRegion.from_hash(kind: "face", x: 0.1, y: 0.1, width: 0, height: 0.1)
    assert_nil PrivacyRegion.from_hash(kind: "face", x: 0.1, y: 0.1, width: 0.1, height: -0.1)
  end

  test "raises when the hash is malformed, because we cannot guess where to blur" do
    assert_raises(ArgumentError) { PrivacyRegion.from_hash(kind: "face", x: 0.1) } # missing keys
    assert_raises(ArgumentError) { PrivacyRegion.from_hash(kind: "face", x: "oops", y: 0, width: 0.1, height: 0.1) }
    assert_raises(ArgumentError) { PrivacyRegion.from_hash(kind: "face", x: Float::NAN, y: 0, width: 0.1, height: 0.1) }
    assert_raises(ArgumentError) { PrivacyRegion.from_hash(kind: "face", x: 0, y: 0, width: Float::INFINITY, height: 0.1) }
    assert_raises(ArgumentError) { PrivacyRegion.from_hash("a string") }
    assert_raises(TypeError) { PrivacyRegion.from_hash(kind: "face", x: nil, y: 0, width: 0.1, height: 0.1) }
  end

  test "to_pixels grows the box by the padding on every side" do
    region = PrivacyRegion.from_hash(kind: "face", x: 0.25, y: 0.25, width: 0.25, height: 0.25)

    # padding 0.25 -> 0.0625 on each side: x 0.1875..0.5625 of 200 = 37.5..112.5, y of 150 = 28.125..84.375
    assert_equal [37, 28, 76, 57], region.to_pixels(200, 150, padding: 0.25)
    assert_equal [25, 25, 50, 50], PrivacyRegion.from_hash(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                                                .to_pixels(100, 100, padding: 0)
  end

  test "to_pixels uses a default padding so the box covers the edges of a face" do
    region = PrivacyRegion.from_hash(kind: "face", x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    left, top, width, height = region.to_pixels(1000, 1000)

    assert_operator left, :<, 400
    assert_operator top, :<, 400
    assert_operator left + width, :>, 600
    assert_operator top + height, :>, 600
  end

  test "to_pixels never leaves the image" do
    corner = PrivacyRegion.from_hash(kind: "face", x: 0, y: 0, width: 0.125, height: 0.125)
    assert_equal [0, 0, 19, 19], corner.to_pixels(100, 100, padding: 0.5)

    far = PrivacyRegion.from_hash(kind: "face", x: 0.875, y: 0.875, width: 0.125, height: 0.125)
    assert_equal [81, 81, 19, 19], far.to_pixels(100, 100, padding: 0.5)

    whole = PrivacyRegion.from_hash(kind: "other", x: 0, y: 0, width: 1, height: 1)
    assert_equal [0, 0, 100, 80], whole.to_pixels(100, 80)
  end

  test "to_pixels is at least one pixel in each direction" do
    tiny = PrivacyRegion.from_hash(kind: "face", x: 0.5, y: 0.5, width: 0.000001, height: 0.000001)

    assert_equal [50, 50, 1, 1], tiny.to_pixels(100, 100, padding: 0)
  end
end
