# Devise, trimmed for an API-only app: the controllers sign people in themselves (Api::V1::SessionsController),
# so none of Devise's own routes, views or mailers are used. See config/routes.rb (devise_for ... skip: :all).
Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = ENV.fetch("MAILER_SENDER", "no-reply@lixo-livre.invalid")
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.navigational_formats = []
  config.sign_out_via = :delete
end
