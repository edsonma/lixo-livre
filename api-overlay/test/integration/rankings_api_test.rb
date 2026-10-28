require "test_helper"

class RankingsApiTest < ActionDispatch::IntegrationTest
  BBOX = "-48.0,-16.0,-47.7,-15.6".freeze

  def report(lng:, lat:, severity:, days_ago: 1, types: %w[plastic])
    create_published_trash(severity: severity, lng: lng, lat: lat, taken_at: days_ago.days.ago).tap do |t|
      t.update_columns(trash_types: types)
    end
  end

  test "lists the worst places near a point, worst first, with a trend and regions" do
    report(lng: -47.88, lat: -15.79, severity: 90)
    report(lng: -47.93, lat: -15.84, severity: 40) # a few km away
    report(lng: -46.63, lat: -23.55, severity: 99) # Sao Paulo: out of range

    get "/api/v1/rankings", params: { lat: -15.79, lng: -47.88, radius_km: 10 }

    assert_response :success
    body = response.parsed_body
    assert_equal 2, body["worst"].size
    assert_operator body["worst"][0]["score"], :>, body["worst"][1]["score"]
    assert_equal "worse", body["worst"].first["trend"]["label"]
    assert_equal 0, body["worst"].first["meters"]
    assert body["regions"].any?
  end

  test "rejects a broken position" do
    get "/api/v1/rankings", params: { lat: "x", lng: "y" }
    assert_response :unprocessable_entity
  end

  test "heatmap can be limited to a period and a type" do
    report(lng: -47.88, lat: -15.79, severity: 90, days_ago: 40, types: %w[glass])
    report(lng: -47.88, lat: -15.79, severity: 50, days_ago: 1, types: %w[plastic])

    get "/api/v1/heatmap", params: { bbox: BBOX, days: 7 }
    features = response.parsed_body["features"]
    assert_equal 1, features.size
    assert_operator features.first["properties"]["score"], :<=, 50

    get "/api/v1/heatmap", params: { bbox: BBOX, type: "glass", days: 7 }
    assert_empty response.parsed_body["features"]

    get "/api/v1/heatmap", params: { bbox: BBOX, type: "bogus" } # unknown filters are ignored
    assert_response :success
  end
end
