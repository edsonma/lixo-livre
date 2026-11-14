# A published report, as anybody sees it on the map. Only for reports in Trash.for_heatmap.
class TrashSerializer < ApplicationSerializer
  def initialize(record, urls:)
    super
    @urls = urls
  end

  def as_json(*)
    {
      id: record.id,
      kind: record.kind,
      severity: record.severity,
      trash_types: record.trash_types,
      extra_info: record.extra_info,
      taken_at: record.taken_at,
      lat: record.lonlat.y,
      lng: record.lonlat.x,
      photo_url: @urls.url_for(record.photo),
      uploader: record.user ? { id: record.user_id, name: record.user.name } : nil # nil = anonymous
    }
  end
end
