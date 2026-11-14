# A person, as the pages see them. Never the password digest or any secret.
class UserSerializer < ApplicationSerializer
  def as_json(*)
    {
      id: record.id, name: record.name, email: record.email, role: record.role,
      admin: record.admin?, moderator: record.privileged?,
      passkeys: record.passkeys.count, google: record.provider == "google",
      terms_ok: record.terms_current?, email_verified: record.email_verified?, two_factor: record.otp_enabled?
    }
  end
end
