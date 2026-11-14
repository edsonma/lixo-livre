# Who becomes an admin. Emails in ADMIN_EMAILS (comma separated) become admins when they sign up or sign in.
module User::AdminRole
  extend ActiveSupport::Concern

  included do
    before_save :promote_if_listed
  end

  class_methods do
    def admin_emails
      ENV.fetch("ADMIN_EMAILS", "").split(",").map { |e| e.strip.downcase }.reject(&:empty?)
    end
  end

  def listed_as_admin?
    self.class.admin_emails.include?(email.to_s.downcase)
  end

  # A listed address becomes admin only once it is proven to be the person's: anyone can type any email at
  # sign-up, so without this the first one to register the owner's address would be the admin.
  # Without email delivery (no RESEND_API_KEY) nothing can be verified, so, as elsewhere, the check is off.
  def admin_eligible?
    listed_as_admin? && (email_verified? || !Messaging::Mailer.configured?)
  end

  def privileged?
    admin? || moderator?
  end

  # ADMIN_EMAILS may have changed since the person signed up: sign-in promotes them if they are listed now.
  def promote_if_eligible!
    save! if admin_eligible? && !admin?
  end

  private

  def promote_if_listed
    self.role = :admin if admin_eligible? && !admin?
  end
end
