require "test_helper"

class UpdateProfileTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @user = create_user(name: "Ana Souza", email: "ana@example.com") }

  def update(**args) = UpdateProfile.call(user: @user, **args)

  def avatar_upload(name = "plain.jpg") = Rack::Test::UploadedFile.new(file_fixture(name).to_s, "image/jpeg")

  test "changes the name, bio, website and gender" do
    update(fields: { name: "Ana Maria Souza", bio: "Cuido da quadra", website: "ana.example.com", gender: "female" })

    @user.reload
    assert_equal ["Ana Maria Souza", "Cuido da quadra", "https://ana.example.com", "female"], [@user.name, @user.bio, @user.website, @user.gender]
  end

  test "the email, the role and everything else can never be changed through it" do
    update(fields: { name: "Nova", email: "outro@example.com", role: "admin", password: "hacked-pass-1", terms_version: "x" })

    @user.reload
    assert_equal ["ana@example.com", "user", "Nova"], [@user.email, @user.role, @user.name]
    assert @user.valid_password?(PASSWORD)
  end

  test "a field that is not sent is left alone, and a blank one clears it" do
    update(fields: { bio: "Antes", website: "ana.example.com" })
    update(fields: { bio: "" })

    @user.reload
    assert_nil @user.bio
    assert_equal "https://ana.example.com", @user.website
    assert_equal "Ana Souza", @user.name
  end

  test "the full name cannot be emptied" do
    error = assert_raises(ActiveRecord::RecordInvalid) { update(fields: { name: "   " }) }

    assert_includes error.record.errors[:name], "can't be blank"
    assert_equal "Ana Souza", @user.reload.name
  end

  test "one bad field saves nothing" do
    assert_raises(ActiveRecord::RecordInvalid) { update(fields: { name: "Outro Nome", bio: "Boa", website: "javascript:alert(1)" }) }

    @user.reload
    assert_equal "Ana Souza", @user.name
    assert_nil @user.bio
  end

  test "a picture is processed, stored, and can be replaced or removed" do
    update(avatar: avatar_upload)
    assert_predicate @user.reload.avatar, :attached?
    assert_equal "image/jpeg", @user.avatar.content_type
    first = @user.avatar.blob

    update(avatar: avatar_upload("exif_gps.jpg"))
    assert_not_equal first, @user.reload.avatar.blob

    update(remove_avatar: true)
    assert_not_predicate @user.reload.avatar, :attached?
  end

  test "a picture without GPS comes out of one that had it" do
    update(avatar: avatar_upload("exif_gps.jpg"))

    assert_not Photos::Metadata.read(@user.reload.avatar.download).exif?
  end

  test "something that is not a picture is refused and the rest is not saved" do
    error = assert_raises(ActiveRecord::RecordInvalid) { update(fields: { bio: "Nova bio" }, avatar: Rack::Test::UploadedFile.new(file_fixture("not_an_image.pdf").to_s, "image/jpeg")) }

    assert_includes error.record.errors[:avatar], "is not a usable image"
    assert_nil @user.reload.bio
    assert_not_predicate @user.avatar, :attached?
  end
end
