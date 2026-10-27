# Everything that talks to the webauthn gem lives here, so the controllers stay plain.
#
# Flow (both directions): the server makes a one-time challenge and keeps it in the session, the phone
# signs it with the key that only unlocks with fingerprint/face, and the server verifies the signature.
class PasskeyService
  class Failed < StandardError; end

  def initialize(request)
    origin = ENV["APP_ORIGIN"].presence || request.base_url
    @relying_party = WebAuthn::RelyingParty.new(
      allowed_origins: [origin],
      id: URI.parse(origin).host,
      name: "Lixo Livre"
    )
  end

  # Options for navigator.credentials.create(). Returns [options_hash, challenge].
  def registration_options(user)
    user.update!(webauthn_id: WebAuthn.generate_user_id) if user.webauthn_id.blank? # accounts older than passkeys
    options = @relying_party.options_for_registration(
      user: { id: user.webauthn_id, name: user.email, display_name: user.name },
      exclude: user.passkeys.pluck(:external_id),
      authenticator_selection: { resident_key: "required", user_verification: "required" }
    )
    [JSON.parse(options.to_json), options.challenge]
  end

  # Verifies the phone's answer to registration_options and stores the new passkey.
  def register(user, credential_params, challenge, nickname: nil)
    credential = WebAuthn::Credential.from_create(credential_params, relying_party: @relying_party)
    credential.verify(challenge, user_verification: true)
    user.passkeys.create!(
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      nickname: nickname.to_s.strip.presence&.slice(0, 60)
    )
  rescue WebAuthn::Error, KeyError, TypeError => e
    raise Failed, e.message
  end

  # Options for navigator.credentials.get(). No allow-list: the phone offers the passkeys it holds
  # for this site, so nobody has to type an email first. Returns [options_hash, challenge].
  def authentication_options
    options = @relying_party.options_for_authentication(user_verification: "required")
    [JSON.parse(options.to_json), options.challenge]
  end

  # Verifies the phone's signature. Returns the user it belongs to.
  def authenticate(credential_params, challenge)
    credential = WebAuthn::Credential.from_get(credential_params, relying_party: @relying_party)
    passkey = Passkey.includes(:user).find_by(external_id: credential.id) or raise Failed, "unknown passkey"
    credential.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    passkey.user
  rescue WebAuthn::Error, KeyError, TypeError => e
    raise Failed, e.message
  end
end
