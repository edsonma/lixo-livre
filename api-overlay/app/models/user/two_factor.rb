# Optional two-factor login (TOTP, with recovery codes). The secret is stored encrypted (Auth::OtpVault).
module User::TwoFactor
  extend ActiveSupport::Concern

  RECOVERY_CODES = 8

  def otp_enabled?
    otp_enabled_at.present?
  end

  def otp_secret_plain
    Auth::OtpVault.decrypt(otp_secret)
  end

  # A fresh secret that is not active until enable_otp! confirms a first code. Returns the secret.
  def start_otp_setup!
    secret = Auth::Totp.generate_secret
    update_columns(otp_secret: Auth::OtpVault.encrypt(secret), otp_enabled_at: nil, otp_last_step: nil, otp_recovery_codes: nil)
    secret
  end

  # Confirms the first code and turns 2FA on. Returns the recovery codes (shown once), or nil if the code is wrong.
  def enable_otp!(code)
    secret = otp_secret_plain
    return nil if secret.nil? || otp_enabled?

    step = Auth::Totp.verify(secret, code) or return nil
    codes = Array.new(RECOVERY_CODES) { SecureRandom.alphanumeric(10).downcase.insert(5, "-") }
    update_columns(otp_enabled_at: Time.current, otp_last_step: step, otp_recovery_codes: codes.map { |c| Digest::SHA256.hexdigest(c) }.to_json)
    codes
  end

  # A 6-digit code from the app (each works once) or an unused recovery code (also once).
  def check_otp(input)
    secret = otp_secret_plain
    return false if secret.nil?

    if (step = Auth::Totp.verify(secret, input, last_step: otp_last_step))
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
end
