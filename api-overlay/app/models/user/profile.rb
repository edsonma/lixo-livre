# What shows on a person's profile: a picture, a bio, a website and a gender (the last one is private:
# it is never shown to anyone else). The full name is User#name. The email is the login, so it is not
# part of the profile and nothing here can change it.
module User::Profile
  extend ActiveSupport::Concern

  included do
    has_one_attached :avatar

    before_validation :clean_profile_text

    validates :bio, length: { maximum: ProfileText::BIO_MAX }
    validates :website, length: { maximum: ProfileText::WEBSITE_MAX }
    validates :gender, inclusion: { in: ProfileText::GENDERS }, allow_nil: true
    validate :website_is_a_web_address
  end

  private

  def clean_profile_text
    self.bio = ProfileText.bio(bio)
    self.website = ProfileText.website(website)
    self.gender = ProfileText.gender(gender)
  end

  def website_is_a_web_address
    return if website.nil? || ProfileText.web_address?(website)

    errors.add(:website, "is not a valid web address")
  end
end
