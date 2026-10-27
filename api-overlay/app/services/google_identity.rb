require "net/http"
require "json"

# Checks a Google "Sign in with Google" ID token (the `credential` the browser button gives us)
# and returns who it belongs to. Google validates the signature and expiry on its tokeninfo endpoint;
# we check it was issued for OUR client id and that the email is verified.
class GoogleIdentity
  Identity = Struct.new(:uid, :email, :name, keyword_init: true)
  class Invalid < StandardError; end
  class NotConfigured < StandardError; end

  ENDPOINT = "https://oauth2.googleapis.com/tokeninfo".freeze
  ISSUERS = %w[accounts.google.com https://accounts.google.com].freeze

  def self.client_id
    ENV["GOOGLE_CLIENT_ID"].to_s.strip.presence
  end

  def self.verify(credential, transport: nil)
    expected = client_id or raise NotConfigured, "GOOGLE_CLIENT_ID is not set"
    raise Invalid, "missing credential" if credential.to_s.empty?

    status, text = (transport || method(:fetch)).call(credential.to_s)
    claims = JSON.parse(text.to_s) rescue {}
    raise Invalid, "Google did not accept the token" unless status == 200 && claims.is_a?(Hash)
    raise Invalid, "token is for another app" unless claims["aud"] == expected
    raise Invalid, "unexpected issuer" unless ISSUERS.include?(claims["iss"])
    raise Invalid, "email is not verified" unless claims["email_verified"].to_s == "true" && claims["email"].present?
    raise Invalid, "no account id" if claims["sub"].blank?

    Identity.new(uid: claims["sub"], email: claims["email"].downcase, name: claims["name"].presence)
  end

  def self.fetch(credential)
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(id_token: credential)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri) }
    [response.code.to_i, response.body]
  end
end
