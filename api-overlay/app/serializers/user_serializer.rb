# A person, as the pages see them. Never the password digest or any secret.
class UserSerializer < ApplicationSerializer
  def as_json(*)
    {
      id: record.id, name: record.name, email: record.email, role: record.role,
      admin: record.admin?, moderator: record.privileged?,
      passkeys: record.passkeys.count, google: record.provider == "google",
      terms_ok: record.terms_current?, email_verified: record.email_verified?, two_factor: record.otp_enabled?,
      bio: record.bio, website: record.website, gender: record.gender, avatar_url: avatar_path
    }
  end

  private

  # A path on this site (not a full URL: there is no request here), made the way the app delivers photos,
  # so it follows ACTIVE_STORAGE_DELIVERY. nil without a picture.
  def avatar_path
    return unless record.avatar.attached?

    Rails.application.routes.url_helpers.public_send(:"#{ActiveStorage.resolve_model_to_route}_path", record.avatar.blob)
  end
end
