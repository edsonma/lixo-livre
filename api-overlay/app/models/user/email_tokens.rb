# Emails: verification and password-reset links are signed, expiring tokens (no column needed).
module User::EmailTokens
  extend ActiveSupport::Concern

  included do
    generates_token_for :email_verification, expires_in: 3.days do
      email
    end

    # tied to the current password: once it changes, an old link stops working
    generates_token_for :password_reset, expires_in: 1.hour do
      encrypted_password.to_s.last(12)
    end
  end

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    return if email_verified?

    update_column(:email_verified_at, Time.current)
    save! if admin_eligible? && !admin? # a listed address that has just proven it is theirs
  end
end
