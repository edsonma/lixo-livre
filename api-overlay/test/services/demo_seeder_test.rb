require "test_helper"

class DemoSeederTest < ActiveSupport::TestCase
  test "creates published reports with photos, heat cells and a mix of users and anonymous devices" do
    result = DemoSeeder.call(count: 30)

    assert_not result[:skipped]
    assert_equal 30, Trash.count
    assert_equal 30, Trash.for_heatmap.count, "every demo report is publicly visible"
    assert Trash.all.all? { |t| t.photo.attached? }
    assert Trash.all.all? { |t| t.sanitized_at.present? && t.severity.between?(1, 5) }
    assert_operator HeatCell.count, :>, 0
    assert_operator Trash.where(user_id: nil).count, :>, 0
    assert_operator Trash.where.not(user_id: nil).count, :>, 0
  end

  test "does not touch the AI or the privacy detector" do
    TrashVision.provider = ->(_) { flunk "AI should not be called" }
    PrivacyDetector.provider = ->(_) { flunk "detector should not be called" }

    assert_no_enqueued_jobs { DemoSeeder.call(count: 10) }
  end

  test "does nothing when there are already reports" do
    create_published_trash

    result = DemoSeeder.call(count: 10)

    assert result[:skipped]
    assert_equal 1, Trash.count
  end

  test "force adds reports even when there are some" do
    create_published_trash

    DemoSeeder.call(count: 10, force: true)

    assert_equal 11, Trash.count
  end

  test "running twice with force reuses the demo users and devices" do
    DemoSeeder.call(count: 10)
    users = User.count
    devices = Device.count

    DemoSeeder.call(count: 10, force: true)

    assert_equal users, User.count
    assert_equal devices, Device.count
  end

  test "reset removes only the demo data" do
    real = create_published_trash
    DemoSeeder.call(count: 10, force: true)

    DemoSeeder.reset!

    assert_equal [real.id], Trash.pluck(:id)
    assert_equal 0, User.where("email LIKE ?", "%@#{DemoSeeder::USER_DOMAIN}").count
    assert_equal 0, Device.where("token LIKE ?", "#{DemoSeeder::TOKEN_PREFIX}%").count
  end
end
