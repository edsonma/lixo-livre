# "Sign in with Google": finds the account by Google id, else by the (verified) email, else creates it.
# Raises GoogleIdentity::NotConfigured / ::Invalid when the token cannot be used.
# Failure error: :terms_required (a new account needs consent first).
class SignInWithGoogle
  def self.call(**args) = new(**args).call

  def initialize(credential:, accepted_terms:)
    @credential = credential
    @accepted_terms = accepted_terms
  end

  def call
    identity = GoogleIdentity.verify(@credential)
    user = User.find_by(provider: "google", uid: identity.uid) || claim_by_email(identity)
    return Outcome.failure(:terms_required) if user.nil? && !Terms.accepted_param?(@accepted_terms)

    user ||= User.new(email: identity.email, name: identity.name, password: Devise.friendly_token)
    user.provider ||= "google"
    user.uid ||= identity.uid
    user.accept_terms if user.new_record?
    user.email_verified_at ||= Time.current # Google already verified this address
    user.save!
    Outcome.success(user)
  end

  private

  # Google proves who owns the email, so the owner gets the account made with it. If that account was
  # made by someone who never confirmed the email, whatever they set up must not survive.
  def claim_by_email(identity)
    user = User.find_by(email: identity.email) or return nil
    user.reset_credentials! if Mailer.configured? && !user.email_verified?
    user
  end
end
