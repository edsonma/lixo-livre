require "test_helper"

class PlacesApiTest < ActionDispatch::IntegrationTest
  def place(h3) = get("/api/v1/places/#{h3}")

  test "a place has its latest report, its history and its photos" do
    old = create_published_trash(severity: 80, taken_at: 40.days.ago)
    recent = create_published_trash(severity: 30, taken_at: 1.day.ago)
    h3 = recent.h3_index
    RefreshHeatCellJob.perform_now(h3)

    place(h3)

    assert_response :success
    body = response.parsed_body
    assert_equal h3, body["h3"]
    assert_equal 2, body["reports_count"]
    assert_equal recent.id, body["latest"]["id"]
    assert_equal [recent.id, old.id], body["photos"].map { |t| t["id"] }
    assert_operator body["history"].size, :>=, 1
    assert_equal %w[average month reports], body["history"].first.keys.sort
    assert_in_delta(-15.7942, body["center"]["lat"], 0.001)
    assert_not_nil body["score"]
  end

  test "drafts, pending and hidden reports are not part of a place" do
    published = create_published_trash
    create_draft_trash
    create_trash
    create_published_trash.tap(&:hide!)

    place(published.h3_index)

    assert_equal [published.id], response.parsed_body["photos"].map { |t| t["id"] }
    assert_equal 1, response.parsed_body["reports_count"]
  end

  test "a place with nothing published is a 404" do
    draft = create_draft_trash
    place(draft.h3_index)
    assert_response :not_found
  end

  test "nonsense identifiers are a 404, not an error" do
    ["nope", "89a8c24f44fffff00", "89A8C24F44FFFFF"].each do |h3|
      get "/api/v1/places/#{h3}"
      assert_response :not_found, "expected 404 for #{h3.inspect}"
    end
  end

  test "photo urls are there for each photo, and no private details leak" do
    trash = create_published_trash
    place(trash.h3_index)
    photo = response.parsed_body["photos"].first
    assert_match(/active_storage/, photo["photo_url"])
    assert_not photo.key?("device_id")
  end
end
