require "test_helper"

class TotpTest < ActiveSupport::TestCase
  SECRET = Auth::Totp.base32_encode("12345678901234567890") # the RFC 6238 test key

  test "matches the RFC 6238 test vectors" do
    assert_equal "287082", Auth::Totp.code(SECRET, 59 / 30)
    assert_equal "081804", Auth::Totp.code(SECRET, 1_111_111_109 / 30)
  end

  test "base32 round trips" do
    s = Auth::Totp.generate_secret
    assert_equal 32, s.length
    assert_equal s, Auth::Totp.base32_encode(Auth::Totp.base32_decode(s))
  end

  test "verify accepts the current code and one step of clock drift, once" do
    t = Time.at(1_700_000_000)
    step = Auth::Totp.step(t)
    code = Auth::Totp.code(SECRET, step)

    assert_equal step, Auth::Totp.verify(SECRET, code, time: t)
    assert_nil Auth::Totp.verify(SECRET, code, last_step: step, time: t) # already used
    assert_equal step - 1, Auth::Totp.verify(SECRET, Auth::Totp.code(SECRET, step - 1), time: t)
    assert_nil Auth::Totp.verify(SECRET, Auth::Totp.code(SECRET, step + 2), time: t)
    assert_nil Auth::Totp.verify(SECRET, "abcdef", time: t)
    assert_nil Auth::Totp.verify(SECRET, "12345", time: t)
  end

  test "the otpauth uri names the app and the account" do
    uri = Auth::Totp.uri("ABC", "a@x.com")
    assert_includes uri, "otpauth://totp/Lixo%20Livre%3Aa%40x.com?secret=ABC"
    assert_includes uri, "issuer=Lixo%20Livre"
  end

  test "the vault round trips and refuses garbage" do
    token = Auth::OtpVault.encrypt("SECRET")
    assert_not_equal "SECRET", token
    assert_equal "SECRET", Auth::OtpVault.decrypt(token)
    assert_nil Auth::OtpVault.decrypt("garbage")
    assert_nil Auth::OtpVault.decrypt(nil)
  end
end
