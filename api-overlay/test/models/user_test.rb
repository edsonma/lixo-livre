require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "needs a unique email" do
    create_user(email: "ana@example.com")

    assert_not User.new(email: nil).valid?
    assert_not User.new(email: "ana@example.com").valid?
    assert User.new(email: "bia@example.com").valid?
  end

  test "is a plain user by default and can be a moderator or admin" do
    user = create_user

    assert_predicate user, :user?
    assert_predicate create_user(role: :moderator), :moderator?
    assert_predicate create_user(role: :admin), :admin?
  end

  test "deleting a user keeps their devices and reports, anonymized" do
    user = create_user
    device = create_device(user: user)
    trash = create_trash(device: device, user: user)

    user.destroy!

    assert_nil device.reload.user_id
    assert_nil trash.reload.user_id
  end
end
