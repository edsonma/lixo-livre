# Creates an account with email and password. Failure error: :terms_required.
# The confirmation email is sent when email delivery is configured. Logging the person in is the controller's job.
class RegisterAccount
  def self.call(**args) = new(**args).call

  def initialize(email:, password:, accepted_terms:, name: nil)
    @email = email
    @password = password
    @name = name
    @accepted_terms = accepted_terms
  end

  def call
    user = User.new(email: @email, name: @name.to_s.strip.presence, password: @password)
    return Outcome.failure(:terms_required) unless Terms.accepted_param?(@accepted_terms)

    user.accept_terms
    user.save!
    SendUserEmailJob.perform_later(user.id, "verify") if Mailer.configured?
    Outcome.success(user)
  end
end
