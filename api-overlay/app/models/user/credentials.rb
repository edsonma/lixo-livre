# Passwords, and taking them back.
module User::Credentials
  extend ActiveSupport::Concern

  class_methods do
    # Same time as a real password check, for a login with an email that has no account: "no such account"
    # must not answer faster than "wrong password".
    def fake_password_check(password)
      @fake_digest ||= BCrypt::Password.create("not-a-real-password", cost: Devise.stretches)
      @fake_digest.is_password?(password.to_s)
      false
    end
  end

  # Accounts created without a password (Google) or with a passkey are fine; passwords are only checked
  # by the registration endpoint. (Devise still validates the length of a password that is given.)
  def password_required?
    false
  end

  # Sets the new password from a reset link. Reading the link's email proves the address is theirs.
  def reset_password!(new_password)
    self.password = new_password
    self.email_verified_at ||= Time.current
    save!
  end

  # Google has just proven that this email belongs to its owner, but the account was made with it by
  # someone who never confirmed it (maybe not the owner). Whatever they set up (password, passkeys,
  # second factor) must not survive: only the owner, through Google, keeps access.
  def reset_credentials!
    transaction do
      self.password = Devise.friendly_token(32)
      save!
      passkeys.destroy_all
      disable_otp!
    end
  end
end
