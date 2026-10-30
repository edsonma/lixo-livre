class User < ApplicationRecord
  # Login is email + password (Devise), Google, or a passkey (fingerprint / face). Sessions are
  # cookies handled by Warden; the controllers under Api::V1 do the signing in (see SessionsController).
  devise :database_authenticatable, :validatable

  enum :role, { user: 0, moderator: 1, admin: 2 }, default: :user

  has_many :devices, dependent: :nullify
  has_many :trashes, dependent: :nullify
  has_many :passkeys, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :notifications, dependent: :destroy

  before_validation :set_defaults
  before_save :promote_if_listed

  # Accounts created without a password (Google) or with a passkey are fine; passwords are only checked
  # by the registration endpoint. (Devise still validates the length of a password that is given.)
  def password_required?
    false
  end

  # Emails in ADMIN_EMAILS (comma separated) become admins when they sign up or sign in.
  def self.admin_emails
    ENV.fetch("ADMIN_EMAILS", "").split(",").map { |e| e.strip.downcase }.reject(&:empty?)
  end

  def listed_as_admin?
    self.class.admin_emails.include?(email.to_s.downcase)
  end

  def privileged?
    admin? || moderator?
  end

  # --- emails: verification and password reset links are signed, expiring tokens (no column needed) ---
  generates_token_for :email_verification, expires_in: 3.days do
    email
  end

  # tied to the current password: once it changes, an old link stops working
  generates_token_for :password_reset, expires_in: 1.hour do
    encrypted_password.to_s.last(12)
  end

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update_column(:email_verified_at, Time.current) unless email_verified?
  end

  # --- optional two-factor login (TOTP) ---
  RECOVERY_CODES = 8

  def otp_enabled?
    otp_enabled_at.present?
  end

  def otp_secret_plain
    OtpVault.decrypt(otp_secret)
  end

  # A fresh secret that is not active until enable_otp! confirms a first code. Returns the secret.
  def start_otp_setup!
    secret = Totp.generate_secret
    update_columns(otp_secret: OtpVault.encrypt(secret), otp_enabled_at: nil, otp_last_step: nil, otp_recovery_codes: nil)
    secret
  end

  # Confirms the first code and turns 2FA on. Returns the recovery codes (shown once), or nil if the code is wrong.
  def enable_otp!(code)
    secret = otp_secret_plain
    return nil if secret.nil? || otp_enabled?

    step = Totp.verify(secret, code) or return nil
    codes = Array.new(RECOVERY_CODES) { SecureRandom.alphanumeric(10).downcase.insert(5, "-") }
    update_columns(otp_enabled_at: Time.current, otp_last_step: step, otp_recovery_codes: codes.map { |c| Digest::SHA256.hexdigest(c) }.to_json)
    codes
  end

  # A 6-digit code from the app (each works once) or an unused recovery code (also once).
  def check_otp(input)
    secret = otp_secret_plain
    return false if secret.nil?

    if (step = Totp.verify(secret, input, last_step: otp_last_step))
      update_column(:otp_last_step, step)
      return true
    end

    digest = Digest::SHA256.hexdigest(input.to_s.strip.downcase)
    codes = JSON.parse(otp_recovery_codes.presence || "[]")
    return false unless codes.include?(digest)

    update_column(:otp_recovery_codes, (codes - [digest]).to_json)
    true
  end

  def disable_otp!
    update_columns(otp_secret: nil, otp_enabled_at: nil, otp_last_step: nil, otp_recovery_codes: nil)
  end

  def terms_current?
    consented_at.present? && terms_version == Terms::VERSION
  end

  def accept_terms(now = Time.current)
    self.consented_at = now
    self.terms_version = Terms::VERSION
  end

  private

  def set_defaults
    self.name = email.to_s.split("@").first if name.blank?
    self.webauthn_id ||= WebAuthn.generate_user_id
  end

  def promote_if_listed
    self.role = :admin if listed_as_admin? && !admin?
  end
end
