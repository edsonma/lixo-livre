# Keeps the TOTP secret encrypted in the database (key derived from SECRET_KEY_BASE), so a copy of the
# database alone is not enough to generate codes.
module OtpVault
  module_function

  def encrypt(plain)
    encryptor.encrypt_and_sign(plain, purpose: "otp_secret")
  end

  def decrypt(token)
    return nil if token.blank?

    encryptor.decrypt_and_verify(token, purpose: "otp_secret")
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("lixo-livre otp secrets", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
