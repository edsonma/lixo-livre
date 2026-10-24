require "test_helper"

class GeoTest < ActiveSupport::TestCase
  test "distance between a point and itself is zero" do
    assert_in_delta 0, Geo.distance_m(-15.7942, -47.8825, -15.7942, -47.8825), 0.001
  end

  test "one degree of latitude is about 111 km" do
    assert_in_delta 111_195, Geo.distance_m(0, 0, 1, 0), 10
  end

  test "Brasilia to Sao Paulo is about 872 km, in either direction" do
    forward = Geo.distance_m(-15.7942, -47.8825, -23.5505, -46.6333)
    backward = Geo.distance_m(-23.5505, -46.6333, -15.7942, -47.8825)

    assert_in_delta 872_303, forward, 500
    assert_in_delta forward, backward, 0.001
  end

  test "short distances are accurate" do
    assert_in_delta 55.6, Geo.distance_m(-15.7942, -47.8825, -15.7937, -47.8825), 0.5
  end

  test "antipodal points do not blow up the arcsine" do
    assert_in_delta 20_015_114, Geo.distance_m(0, 0, 0, 180), 50
  end
end
