require "test_helper"

class UserProfileTest < ActiveSupport::TestCase
  test "the profile fields are optional and clean themselves" do
    user = create_user(bio: "  Moro na Asa Sul  ", website: "lixolivre.com", gender: "Non_Binary")

    assert_equal ["Moro na Asa Sul", "https://lixolivre.com", "non_binary"], [user.bio, user.website, user.gender]
    assert_nil create_user.bio
  end

  test "a bio has a limit" do
    user = create_user
    user.bio = "a" * (ProfileText::BIO_MAX + 1)

    assert_not user.valid?
    assert_includes user.errors[:bio].join, "too long"
    user.bio = "a" * ProfileText::BIO_MAX
    assert user.valid?
  end

  test "a website must be a real web address, never a script" do
    user = create_user
    ["javascript:alert(1)", "nada", "https://user:senha@exemplo.com", "ftp://exemplo.com"].each do |bad|
      user.website = bad
      assert_not user.valid?, bad
      assert user.errors.of_kind?(:website, :invalid) || user.errors[:website].any?, bad
    end
  end

  test "a gender is one of the listed values, or empty" do
    user = create_user
    user.gender = "robot"
    assert_not user.valid?
    ProfileText::GENDERS.each { |g| user.gender = g; assert user.valid?, g }
    user.gender = ""
    assert user.valid?
    assert_nil user.gender
  end
end
