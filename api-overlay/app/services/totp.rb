require "openssl"
require "securerandom"

# Time-based one-time passwords (RFC 6238), as used by Google Authenticator, Authy, 1Password...
# 6 digits, 30 seconds, HMAC-SHA1: the defaults every authenticator app understands.
module Totp
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze
  DIGITS = 6
  PERIOD = 30
  DRIFT = 1 # accept the previous and the next 30 seconds (clocks are never exact)

  module_function

  def generate_secret
    base32_encode(SecureRandom.random_bytes(20))
  end

  def base32_encode(bytes)
    bits = bytes.unpack1("B*")
    bits += "0" * ((5 - bits.length % 5) % 5)
    bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
  end

  def base32_decode(text)
    bits = text.to_s.upcase.delete("= ").chars.map do |c|
      index = ALPHABET.index(c) or raise ArgumentError, "not base32: #{c.inspect}"
      index.to_s(2).rjust(5, "0")
    end.join
    [bits[0, bits.length / 8 * 8]].pack("B*")
  end

  def step(time = Time.now)
    time.to_i / PERIOD
  end

  def code(secret, step)
    digest = OpenSSL::HMAC.digest("SHA1", base32_decode(secret), [step].pack("Q>"))
    offset = digest.bytes.last & 0x0f
    number = digest[offset, 4].unpack1("N") & 0x7fffffff
    (number % 10**DIGITS).to_s.rjust(DIGITS, "0")
  end

  # The step the code belongs to, or nil. A step at or before last_step is refused: a code works once.
  def verify(secret, input, last_step: nil, time: Time.now)
    input = input.to_s.delete(" ")
    return nil unless input.match?(/\A\d{#{DIGITS}}\z/)

    current = step(time)
    (-DRIFT..DRIFT).each do |shift|
      candidate = current + shift
      next if last_step && candidate <= last_step

      return candidate if OpenSSL.fixed_length_secure_compare(code(secret, candidate), input)
    end
    nil
  end

  # otpauth://totp/Lixo%20Livre:ana@x.com?secret=...&issuer=Lixo%20Livre : opens in the authenticator app
  def uri(secret, account, issuer: "Lixo Livre")
    label = URI.encode_www_form_component("#{issuer}:#{account}").gsub("+", "%20")
    "otpauth://totp/#{label}?secret=#{secret}&issuer=#{URI.encode_www_form_component(issuer).gsub('+', '%20')}&digits=#{DIGITS}&period=#{PERIOD}"
  end
end
