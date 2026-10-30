# The public address of the site, for links in emails (there is no request when a job runs).
#   APP_ORIGIN=https://lixo-livre.example.com   (Railway also sets RAILWAY_PUBLIC_DOMAIN)
module AppUrl
  def self.base(env = ENV)
    origin = env["APP_ORIGIN"].to_s.strip.chomp("/")
    return origin unless origin.empty?

    domain = env["RAILWAY_PUBLIC_DOMAIN"].to_s.strip
    return "https://#{domain}" unless domain.empty?

    "http://localhost:3000"
  end

  def self.link(query, env = ENV)
    "#{base(env)}/?#{query}"
  end
end
