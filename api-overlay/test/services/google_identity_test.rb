require "test_helper"

class GoogleIdentityTest < ActiveSupport::TestCase
  CLIENT = "abc.apps.googleusercontent.com".freeze

  def claims(**overrides)
    { "aud" => CLIENT, "iss" => "https://accounts.google.com", "sub" => "1234", "email" => "Ana@Example.com",
      "email_verified" => "true", "name" => "Ana" }.merge(overrides.transform_keys(&:to_s))
  end

  def verify(body, status: 200)
    with_env("GOOGLE_CLIENT_ID" => CLIENT) do
      GoogleIdentity.verify("credential", transport: ->(_token) { [status, JSON.generate(body)] })
    end
  end

  test "a good token gives the Google id, the lowercased email and the name" do
    identity = verify(claims)

    assert_equal ["1234", "ana@example.com", "Ana"], [identity.uid, identity.email, identity.name]
  end

  test "both spellings of the issuer are accepted" do
    assert verify(claims(iss: "accounts.google.com"))
  end

  test "a token issued for another app is refused" do
    assert_raises(GoogleIdentity::Invalid) { verify(claims(aud: "somebody-else")) }
  end

  test "an unverified email is refused" do
    assert_raises(GoogleIdentity::Invalid) { verify(claims(email_verified: "false")) }
  end

  test "a token Google rejects is refused" do
    assert_raises(GoogleIdentity::Invalid) { verify({ "error" => "invalid_token" }, status: 400) }
  end

  test "an unexpected issuer is refused" do
    assert_raises(GoogleIdentity::Invalid) { verify(claims(iss: "https://evil.example")) }
  end

  test "an empty credential is refused" do
    with_env("GOOGLE_CLIENT_ID" => CLIENT) do
      assert_raises(GoogleIdentity::Invalid) { GoogleIdentity.verify("", transport: ->(_) { flunk "no request expected" }) }
    end
  end

  test "without a client id it is not configured" do
    with_env("GOOGLE_CLIENT_ID" => nil) do
      assert_raises(GoogleIdentity::NotConfigured) { GoogleIdentity.verify("x") }
    end
  end
end
