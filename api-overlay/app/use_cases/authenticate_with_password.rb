# Email + password login, and the second step for people who use an authenticator app.
# Failure errors: :invalid_credentials, :otp_required (the code is needed, none was sent), :invalid_otp.
# Signing the person in (the session) is the controller's job: this only decides whether they may be.
class AuthenticateWithPassword
  def self.call(**args) = new(**args).call

  def initialize(email:, password:, otp: nil)
    @email = email
    @password = password
    @otp = otp
  end

  def call
    user = User.find_for_database_authentication(email: @email)
    User.fake_password_check(@password) unless user # same time whether or not the account exists
    return Outcome.failure(:invalid_credentials) unless user&.valid_password?(@password)
    return second_factor(user) if user.otp_enabled?

    Outcome.success(user)
  end

  private

  # the 6-digit code from the authenticator app, or a recovery code
  def second_factor(user)
    code = @otp.to_s.strip
    return Outcome.failure(:otp_required) if code.empty?
    return Outcome.failure(:invalid_otp) unless user.check_otp(code)

    Outcome.success(user)
  end
end
