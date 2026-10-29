require "test_helper"

class ConsentApiTest < ActionDispatch::IntegrationTest
  def json_post(path, body)
    post path, params: body.to_json, headers: { "Content-Type" => "application/json" }
  end

  test "signing up without accepting the terms is refused" do
    json_post "/api/v1/users", { email: "a@example.com", password: "longenough1" }
    assert_response :unprocessable_entity
    assert_equal "terms_required", response.parsed_body["error"]
    assert_nil User.find_by(email: "a@example.com")

    json_post "/api/v1/users", { email: "a@example.com", password: "longenough1", accepted_terms: false }
    assert_response :unprocessable_entity
  end

  test "signing up with the terms accepted records when and which version" do
    json_post "/api/v1/users", { email: "a@example.com", password: "longenough1", accepted_terms: true }
    assert_response :created
    user = User.find_by!(email: "a@example.com")
    assert_equal Terms::VERSION, user.terms_version
    assert_in_delta Time.current, user.consented_at, 5
    assert_equal true, response.parsed_body.dig("user", "terms_ok")
  end

  test "an account without consent cannot report until it accepts" do
    user = create_user(consented_at: nil, terms_version: nil)
    device = create_device(user: user)
    sign_in user

    post "/api/v1/trashes", params: { photo: uploaded_photo, lat: -15.79, lng: -47.88, taken_at: Time.current.iso8601 },
                            headers: { "X-Device-Token" => device.token }
    assert_response :forbidden
    assert_equal "terms_required", response.parsed_body["error"]

    json_post "/api/v1/consent", { accepted_terms: false }
    assert_response :unprocessable_entity

    json_post "/api/v1/consent", { accepted_terms: true }
    assert_response :success
    assert_predicate user.reload, :terms_current?
  end

  test "a new version of the terms asks again" do
    user = create_user(terms_version: "2020-01-01")
    assert_not user.terms_current?
  end

  test "status tells the app which terms version and who is responsible" do
    with_env("LEGAL_NAME" => "Lixo Livre Ltda", "LEGAL_EMAIL" => "oi@example.com") do
      get "/api/v1/status"
    end
    assert_equal({ "version" => Terms::VERSION, "name" => "Lixo Livre Ltda", "email" => "oi@example.com" }, response.parsed_body["legal"])
  end

  test "deleting the account removes the person and their reports" do
    user = create_user
    device = create_device(user: user)
    create_published_trash(device: device, user: user, severity: 70)
    other = create_published_trash(severity: 30)
    sign_in user

    assert_difference -> { Trash.count }, -1 do
      delete "/api/v1/account"
    end
    assert_response :no_content
    assert_nil User.find_by(id: user.id)
    assert Trash.exists?(other.id)
  end

  test "deleting needs a login" do
    delete "/api/v1/account"
    assert_response :unauthorized
  end
end
