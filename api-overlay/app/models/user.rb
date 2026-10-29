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
