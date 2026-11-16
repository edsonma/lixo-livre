require "test_helper"

class Photos::AvatarTest < ActiveSupport::TestCase
  test "any picture becomes a 512 pixel square JPEG" do
    jpeg = Photos::Avatar.call(file_fixture("plain.jpg").binread)
    image = Vips::Image.new_from_buffer(jpeg, "")

    assert_equal [Photos::Avatar::SIZE, Photos::Avatar::SIZE], [image.width, image.height]
    assert_equal "\xFF\xD8".b, jpeg.byteslice(0, 2)
  end

  test "the location and camera data in the original never survive" do
    original = file_fixture("exif_gps.jpg").binread
    assert Photos::Metadata.read(original).gps?, "the fixture must carry GPS for this test to mean anything"

    result = Photos::Avatar.call(original)

    assert_not Photos::Metadata.read(result).exif?
  end

  test "something that is not a picture is refused" do
    assert_raises(Photos::Avatar::Invalid) { Photos::Avatar.call(file_fixture("not_an_image.pdf").binread) }
    assert_raises(Photos::Avatar::Invalid) { Photos::Avatar.call(file_fixture("corrupt.jpg").binread) }
    assert_raises(Photos::Avatar::Invalid) { Photos::Avatar.call("") }
    assert_raises(Photos::Avatar::Invalid) { Photos::Avatar.call(nil) }
  end

  test "a huge upload is refused before it is decoded" do
    assert_raises(Photos::Avatar::Invalid) { Photos::Avatar.call("x" * (Photos::Avatar::MAX_UPLOAD_BYTES + 1)) }
  end
end
