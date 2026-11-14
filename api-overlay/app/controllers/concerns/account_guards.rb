# Who may do what. Each guard answers the request itself when the person is not allowed, which stops the
# action (use them as before_action). They rely on DeviceAuthentication having set @device.
module AccountGuards
  private

  # Reporting needs an account. Also ties this device to the account: a device nobody owns yet is
  # claimed (so anonymous history is kept); one that belongs to somebody else is not used.
  def require_login!
    return render(json: { error: "login_required" }, status: :unauthorized) unless current_user

    return unless @device

    if @device.user_id.nil?
      @device.claim_by!(current_user)
    elsif @device.user_id != current_user.id
      @device = nil # the phone's token belongs to another account: the app asks for a new one
    end
  end

  # Reporting also needs the current Terms and Privacy Policy accepted (older accounts are asked once).
  def require_terms!
    render(json: { error: "terms_required" }, status: :forbidden) unless current_user&.terms_current?
  end

  # With email configured (Resend), reporting also needs a confirmed email address.
  def require_verified_email!
    render(json: { error: "email_unverified" }, status: :forbidden) if Mailer.configured? && !current_user&.email_verified?
  end

  def require_admin!
    require_account_that(&:admin?)
  end

  def require_moderator!
    require_account_that(&:privileged?)
  end

  # 401 when nobody is logged in, 403 when the person is not allowed (the block says whether they are).
  def require_account_that
    return render(json: { error: "login_required" }, status: :unauthorized) unless current_user

    render(json: { error: "forbidden" }, status: :forbidden) unless yield(current_user)
  end
end
