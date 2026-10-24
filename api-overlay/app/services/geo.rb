module Geo
  EARTH_RADIUS_M = 6_371_008.8

  # Great-circle distance in meters (haversine).
  def self.distance_m(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    d_lat = (lat2 - lat1) * rad
    d_lng = (lng2 - lng1) * rad
    a = Math.sin(d_lat / 2)**2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(d_lng / 2)**2
    2 * EARTH_RADIUS_M * Math.asin(Math.sqrt([a, 1.0].min))
  end
end
