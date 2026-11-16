# A person with an account. What they can do is split by concern, each in app/models/user/:
#   Credentials   passwords, and taking them back          TwoFactor     TOTP and recovery codes
#   EmailTokens   verification and reset links             TermsConsent  accepting the Terms
#   AdminRole     who becomes an admin            Profile       picture, bio, website, gender
class User < ApplicationRecord
  # Login is email + password (Devise), Google, or a passkey (fingerprint / face). Sessions are
  # cookies handled by Warden; the controllers under Api::V1 do the signing in (see SessionsController).
  devise :database_authenticatable, :validatable

  NAME_MAX = 100

  enum :role, { user: 0, moderator: 1, admin: 2 }, default: :user

  has_many :devices, dependent: :nullify
  has_many :trashes, dependent: :nullify
  has_many :passkeys, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :notifications, dependent: :destroy

  include AdminRole
  include Credentials
  include EmailTokens
  include Profile
  include TermsConsent
  include TwoFactor

  before_validation :set_defaults

  private

  def set_defaults
    self.name = email.to_s.split("@").first if name.blank?
    self.name = name.to_s.strip.slice(0, NAME_MAX) # no one-megabyte names (sign-up, Google, or the part before the @)
    self.webauthn_id ||= WebAuthn.generate_user_id
  end
end
