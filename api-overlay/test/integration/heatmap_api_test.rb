require "test_helper"

class HeatmapApiTest < ActionDispatch::IntegrationTest
  BBOX = "-48.0,-16.0,-47.7,-15.6".freeze # around Brasilia

  def cell(lng:, lat:, score:, count: 1)
    h3 = H3.to_string(H3.from_geo_coordinates([lat, lng], 9))
    HeatCell.create!(h3_index: h3, resolution: 9, lonlat: Trash.point(lng, lat), score: score, reports_count: count)
  end

  test "returns the cells in the box as a GeoJSON FeatureCollection" do
    cell(lng: -47.88, lat: -15.79, score: 55.5, count: 3)

    get "/api/v1/heatmap", params: { bbox: BBOX }

    assert_response :success
    body = response.parsed_body
    assert_equal "FeatureCollection", body["type"]
    assert_equal 1, body["features"].size
    feature = body["features"].first
    assert_equal "Feature", feature["type"]
    assert_in_delta 55.5, feature["properties"]["score"]
    assert_equal 3, feature["properties"]["count"]
    assert_in_delta(-47.88, feature["geometry"]["coordinates"][0], 1e-6)
    assert_in_delta(-15.79, feature["geometry"]["coordinates"][1], 1e-6)
  end

  test "leaves out cells outside the box" do
    cell(lng: -46.63, lat: -23.55, score: 9) # Sao Paulo

    get "/api/v1/heatmap", params: { bbox: BBOX }

    assert_empty response.parsed_body["features"]
  end

  test "leaves out cells that have cooled down to almost nothing" do
    cell(lng: -47.88, lat: -15.79, score: 1)
    hot = cell(lng: -47.85, lat: -15.75, score: 40)

    get "/api/v1/heatmap", params: { bbox: BBOX }

    assert_equal [hot.h3_index], response.parsed_body["features"].map { |f| f["properties"]["h3"] }
  end

  test "needs a bounding box" do
    get "/api/v1/heatmap"

    assert_response :bad_request
    assert response.parsed_body["errors"].key?("bbox")
  end

  test "needs no login: the map is public" do
    cell(lng: -47.88, lat: -15.79, score: 1)

    get "/api/v1/heatmap", params: { bbox: BBOX } # no device token

    assert_response :success
  end
end
