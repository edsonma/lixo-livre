# Acceptance of the current Terms of Use and Privacy Policy (see Terms for the version).
module User::TermsConsent
  def terms_current?
    consented_at.present? && terms_version == Terms::VERSION
  end

  def accept_terms(now = Time.current)
    self.consented_at = now
    self.terms_version = Terms::VERSION
  end
end
