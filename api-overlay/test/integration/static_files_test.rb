require "test_helper"

# The demo page is served by Rails itself (public/). What it ships with matters as much as the API.
class StaticFilesTest < ActionDispatch::IntegrationTest
  test "the page cannot be framed by other sites, is not sniffed, and does not leak its address" do
    get "/index.html"

    assert_response :success
    assert_equal "SAMEORIGIN", response.get_header("x-frame-options")
    assert_equal "nosniff", response.get_header("x-content-type-options")
    assert_equal "strict-origin-when-cross-origin", response.get_header("referrer-policy")
    assert_equal "no-cache", response.get_header("cache-control")
  end

  test "the page loads no script from another site: the map library is served from here" do
    html = Rails.root.join("public/index.html").read

    assert_no_match(%r{<script[^>]+src=["']https?://}, html)
    assert_no_match(%r{<link[^>]+href=["']https?://unpkg}, html)
    get "/vendor/maplibre-gl-4.7.1/maplibre-gl.js"
    assert_response :success
  end
end
