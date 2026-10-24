require "test_helper"

class FlagTest < ActiveSupport::TestCase
  setup { @trash = create_published_trash }

  def flag!(reason: "privacy", device: create_device, **attrs)
    Flag.create!(trash: @trash, device: device, reason: reason, **attrs)
  end

  test "reason must be one of the known ones" do
    Flag::REASONS.each { |reason| assert Flag.new(trash: @trash, device: create_device, reason: reason).valid?, reason }
    assert_not Flag.new(trash: @trash, device: create_device, reason: "i dislike it").valid?
    assert_not Flag.new(trash: @trash, device: create_device, reason: nil).valid?
  end

  test "a device can flag a photo only once" do
    device = create_device
    flag!(device: device)
    again = Flag.new(trash: @trash, device: device, reason: "duplicate")

    assert_not again.valid?
    assert again.errors[:device_id].any?
    assert Flag.new(trash: create_published_trash, device: device, reason: "privacy").valid?
  end

  test "starts pending" do
    assert_predicate flag!, :pending?
  end

  test "three pending flags from different devices hide the photo" do
    2.times { flag! }
    assert_nil @trash.reload.hidden_at

    flag!

    assert_not_nil @trash.reload.hidden_at
    assert_not_includes Trash.for_heatmap.pluck(:id), @trash.id
  end

  test "dismissed and resolved flags do not count towards hiding" do
    2.times { flag! }
    flag!(status: :dismissed)
    flag!(status: :resolved)

    assert_nil @trash.reload.hidden_at
  end

  test "hiding re-scores the heat cell" do
    2.times { flag! }

    assert_enqueued_with(job: RefreshHeatCellJob, args: [@trash.h3_index]) { flag! }
  end

  test "flags go away with the report" do
    flag!

    assert_difference("Flag.count", -1) { @trash.destroy! }
  end
end
