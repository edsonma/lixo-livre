require "net/http"
require "json"

# Sends email through Resend's HTTP API (no gem needed).
#
#   RESEND_API_KEY=re_...                     from https://resend.com/api-keys
#   MAIL_FROM="Lixo Livre <no-reply@lixolivre.com>"   a domain verified in Resend
#                                              (default onboarding@resend.dev only delivers to your own Resend account)
#
# Without RESEND_API_KEY nothing is sent (Mailer.configured? is false) and the app does not require
# verified emails, so development and demos keep working.
class Mailer
  class Failed < StandardError; end

  ENDPOINT = "https://api.resend.com/emails".freeze
  DEFAULT_FROM = "Lixo Livre <onboarding@resend.dev>".freeze

  def self.configured?(env = ENV)
    !env["RESEND_API_KEY"].to_s.strip.empty?
  end

  # transport: ->(url, headers, body_hash) { [status, body_string] }, replaceable in tests
  def self.deliver(to:, subject:, html:, text:, env: ENV, transport: nil)
    return false unless configured?(env)

    transport ||= method(:http_post)
    status, body = transport.call(
      ENDPOINT,
      { "Authorization" => "Bearer #{env['RESEND_API_KEY'].strip}" },
      { from: env["MAIL_FROM"].presence || DEFAULT_FROM, to: [to], subject: subject, html: html, text: text }
    )
    return true if status.between?(200, 299)

    detail = begin
      JSON.parse(body.to_s)["message"]
    rescue JSON::ParserError
      body.to_s
    end
    raise Failed, "Resend answered HTTP #{status}: #{detail.to_s[0, 200]}"
  end

  def self.http_post(url, headers, body)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 20
    request = Net::HTTP::Post.new(uri.request_uri, headers.merge("content-type" => "application/json"))
    request.body = JSON.generate(body)
    response = http.request(request)
    [response.code.to_i, response.body]
  end
end
