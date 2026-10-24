require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  test "gets a unique secret token when created" do
    a = create_device
    b = create_device

    assert_equal 24, a.token.length
    assert_not_equal a.token, b.token
  end

  test "can be anonymous" do
    assert_nil create_device.user
  end

  test "claim_by! gives the user the device and all of its reports" do
    user = create_user
    device = create_device
    mine = create_trash(device: device)
    other_devices = create_trash(device: create_device)

    device.claim_by!(user)

    assert_equal user, device.reload.user
    assert_equal user.id, mine.reload.user_id
    assert_nil other_devices.reload.user_id
  end

  test "cannot be deleted while it still has reports" do
    device = create_device
    create_trash(device: device)

    assert_not device.destroy
    assert Device.exists?(device.id)
  end
end
