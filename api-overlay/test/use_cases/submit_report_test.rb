require "test_helper"

class SubmitReportTest < ActiveSupport::TestCase
  def submit(**overrides)
    SubmitReport.call(**{
      device: create_device, user: create_user, photo: photo_attachable, lat: -15.7942, lng: -47.8825,
      taken_at: 1.hour.ago.iso8601
    }.merge(overrides))
  end

  test "stores a pending report for the device and the person, and starts the pipeline" do
    user = create_user
    device = create_device(user: user)

    trash = assert_enqueued_with(job: SanitizePhotoJob) { submit(device: device, user: user, extra_info: "bags") }

    assert_predicate trash, :persisted?
    assert_equal [device, user, "pending", "dirty", "bags"], [trash.device, trash.user, trash.ai_status, trash.kind, trash.extra_info]
    assert_in_delta(-15.7942, trash.lonlat.y, 0.0001)
  end

  test "a cleanup stays a cleanup, and a blank kind means dirty" do
    assert_equal "cleanup", submit(kind: "cleanup").kind
    assert_equal "dirty", submit(kind: "").kind
  end

  test "a position that does not exist is refused, whatever it looks like" do
    [[91, 0], [-91, 0], [0, 181], [0, "abc"], ["NaN", 0], [nil, 0]].each do |lat, lng|
      assert_raises(SubmitReport::InvalidPosition, "#{lat.inspect}, #{lng.inspect}") { submit(lat: lat, lng: lng) }
    end
  end

  test "a time in the future is refused by the model" do
    assert_raises(ActiveRecord::RecordInvalid) { submit(taken_at: 3.days.from_now.iso8601) }
  end
end
