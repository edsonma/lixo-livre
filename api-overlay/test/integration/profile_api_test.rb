require "test_helper"

class ProfileApiTest < ActionDispatch::IntegrationTest
  def sign_in_as(user)
    post "/api/v1/session", params: { email: user.email, password: PASSWORD }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :success
  end

  def patch_profile(params = {})
    patch "/api/v1/profile", params: params
  end

  test "you must be signed in" do
    patch_profile(name: "Quem")

    assert_response :unauthorized
  end

  test "a person edits their name, bio, website and gender and gets the updated profile back" do
    user = create_user(email: "ana@example.com", name: "Ana")
    sign_in_as user

    patch_profile(name: "Ana Souza", bio: "Cuido do bairro", website: "ana.example.com", gender: "female")

    assert_response :success
    json = response.parsed_body["user"]
    assert_equal ["Ana Souza", "Cuido do bairro", "https://ana.example.com", "female", nil], json.values_at("name", "bio", "website", "gender", "avatar_url")
    assert_equal "ana@example.com", json["email"]
  end

  test "the email and the role cannot be changed here, whatever is sent" do
    user = create_user(email: "ana@example.com")
    sign_in_as user

    patch_profile(name: "Ana", email: "outro@example.com", role: "admin", admin: true, password: "outra-senha-1")

    assert_response :success
    user.reload
    assert_equal ["ana@example.com", "user"], [user.email, user.role]
    assert user.valid_password?(PASSWORD)
  end

  test "bad values are answered with 422 and a message per field" do
    sign_in_as create_user

    patch_profile(website: "javascript:alert(1)", gender: "robot", bio: "a" * 200, name: " ")

    assert_response :unprocessable_entity
    assert_equal %w[bio gender name website], response.parsed_body["errors"].keys.sort
  end

  test "a picture is stored and its address is on this site" do
    user = create_user
    sign_in_as user

    patch_profile(avatar: uploaded_photo("exif_gps.jpg"))

    assert_response :success
    url = response.parsed_body.dig("user", "avatar_url")
    assert_match %r{\A/rails/active_storage/blobs/}, url
    assert_predicate user.reload.avatar, :attached?

    get url
    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  test "the picture can be removed" do
    user = create_user
    sign_in_as user
    patch_profile(avatar: uploaded_photo)

    patch_profile(remove_avatar: "true")

    assert_response :success
    assert_nil response.parsed_body.dig("user", "avatar_url")
  end

  test "a file that is not a picture is refused" do
    sign_in_as create_user

    patch_profile(avatar: Rack::Test::UploadedFile.new(file_fixture("not_an_image.pdf").to_s, "image/jpeg"))

    assert_response :unprocessable_entity
    assert_equal ["is not a usable image"], response.parsed_body.dig("errors", "avatar")
  end

  test "an edit from another site is refused" do
    sign_in_as create_user

    patch "/api/v1/profile", params: { name: "X" }, headers: { "Origin" => "https://evil.example" }

    assert_response :forbidden
  end

  test "the session endpoint now carries the profile too" do
    user = create_user(bio: "Oi", website: "x.example.com")
    sign_in_as user

    get "/api/v1/session"

    assert_equal ["Oi", "https://x.example.com"], response.parsed_body["user"].values_at("bio", "website")
  end
end
