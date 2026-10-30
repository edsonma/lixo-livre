require "test_helper"

class MailerTest < ActiveSupport::TestCase
  ENV_OK = { "RESEND_API_KEY" => "re_test", "MAIL_FROM" => "Lixo Livre <oi@example.com>" }.freeze

  test "does nothing without an API key" do
    assert_not Mailer.configured?({})
    assert_equal false, Mailer.deliver(to: "a@x.com", subject: "s", html: "h", text: "t", env: {}, transport: ->(*) { flunk "sent" })
  end

  test "posts to Resend with the key, sender and recipient" do
    seen = nil
    ok = Mailer.deliver(to: "a@x.com", subject: "S", html: "<p>h</p>", text: "t", env: ENV_OK,
                        transport: ->(url, headers, body) { seen = [url, headers, body]; [200, "{}"] })
    assert ok
    assert_equal "https://api.resend.com/emails", seen[0]
    assert_equal "Bearer re_test", seen[1]["Authorization"]
    assert_equal ["a@x.com", "Lixo Livre <oi@example.com>", "S"], [seen[2][:to].first, seen[2][:from], seen[2][:subject]]
  end

  test "raises with Resend's message when it refuses" do
    error = assert_raises(Mailer::Failed) do
      Mailer.deliver(to: "a@x.com", subject: "S", html: "h", text: "t", env: ENV_OK,
                     transport: ->(*) { [403, { message: "The domain is not verified" }.to_json] })
    end
    assert_includes error.message, "403"
    assert_includes error.message, "domain is not verified"
  end

  test "emails escape the name and carry the link" do
    mail = UserEmails.reset("<b>Ana</b>", "https://x.test/?reset=abc")
    assert_includes mail[:html], "&lt;b&gt;Ana"
    assert_includes mail[:html], "https://x.test/?reset=abc"
    assert_includes mail[:text], "https://x.test/?reset=abc"
  end

  test "links use APP_ORIGIN, then the Railway domain" do
    assert_equal "https://a.com/?verify=1", AppUrl.link("verify=1", { "APP_ORIGIN" => "https://a.com/" })
    assert_equal "https://b.up.railway.app/?x=1", AppUrl.link("x=1", { "RAILWAY_PUBLIC_DOMAIN" => "b.up.railway.app" })
  end
end
