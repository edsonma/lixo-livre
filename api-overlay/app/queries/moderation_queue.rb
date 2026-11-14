# The two lists moderators work through:
#   held     reports the pipeline would not publish by itself (photo taken far away, AI unsure, a failure)
#   flagged  published photos that people reported
class ModerationQueue
  def held
    Trash.needs_review.order(created_at: :desc)
  end

  def flagged
    Trash.where(id: Flag.pending.select(:trash_id)).order(updated_at: :desc)
  end
end
