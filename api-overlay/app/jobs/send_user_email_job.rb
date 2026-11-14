# Sends one of the account emails ("verify" or "reset") in the background.
class SendUserEmailJob < ApplicationJob
  queue_as :default

  retry_on Messaging::Mailer::Failed, wait: :polynomially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id, kind)
    return unless Messaging::Mailer.configured?

    user = User.find(user_id)
    mail =
      case kind
      when "verify"
        return if user.email_verified?

        Messaging::UserEmails.verify(user.name, Messaging::AppUrl.link("verify=#{user.generate_token_for(:email_verification)}"))
      when "reset"
        Messaging::UserEmails.reset(user.name, Messaging::AppUrl.link("reset=#{user.generate_token_for(:password_reset)}"))
      else
        raise ArgumentError, "unknown email kind #{kind.inspect}"
      end

    Messaging::Mailer.deliver(to: user.email, **mail)
  end
end
