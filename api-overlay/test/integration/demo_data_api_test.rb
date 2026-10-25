require "test_helper"

# What the demo page does against a freshly seeded database.
class DemoDataApiTest < ActionDispatch::IntegrationTest
  setup { DemoSeeder.call(count: 60) }

  test "the heatmap near the demo center has cells" do
    lat, lng = DemoMode.center
    get "/api/v1/heatmap", params: { bbox: [lng - 0.2, lat - 0.2, lng + 0.2, lat + 0.2].join(",") }

    assert_response :success
    assert_operator response.parsed_body["features"].size, :>, 0
  end

  test "clicking on a hot cell lists reports with photos that can be fetched" do
    cell = HeatCell.order(score: :desc).first
    get "/api/v1/trashes", params: { lat: cell.lonlat.y, lng: cell.lonlat.x, radius: 200 }

    assert_response :success
    reports = response.parsed_body
    assert_operator reports.size, :>, 0
    assert reports.all? { |r| r["photo_url"].present? && r["severity"].between?(0, 100) }

    get URI(reports.first["photo_url"]).request_uri
    assert_response :redirect
  end
end
