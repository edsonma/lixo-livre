# The version of the Terms of Use and Privacy Policy shown in the app (public/app.js, LEGAL).
# When the text changes in a way people must agree to again, change this date: everybody is asked
# to accept again before their next report.
module Terms
  VERSION = "2026-10-29".freeze

  def self.accepted_param?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end
end
