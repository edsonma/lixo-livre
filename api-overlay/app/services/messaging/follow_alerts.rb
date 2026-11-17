# After a cell is re-scored: tell the people following it if it got clearly worse or was cleaned.
class Messaging::FollowAlerts
  WORSE_STEP = 15 # points of 100 above what the follower last saw

  # :cleaned, :worse or nil. Pure, so it is easy to test.
  def self.decide(last_score:, last_cleaned_at:, score:, cleaned_at:)
    return :cleaned if cleaned_at && (last_cleaned_at.nil? || cleaned_at > last_cleaned_at)
    return :worse if score - last_score >= WORSE_STEP

    nil
  end

  def self.run(cell)
    Follow.where(h3_index: cell.h3_index).find_each do |follow|
      kind = decide(last_score: follow.last_score, last_cleaned_at: follow.last_cleaned_at,
                    score: cell.score, cleaned_at: cell.cleaned_at)
      if kind
        Notification.create!(user_id: follow.user_id, kind: kind.to_s, h3_index: cell.h3_index, score: cell.score,
                             previous_score: follow.last_score, lat: cell.lonlat&.y, lng: cell.lonlat&.x)
      end
      # a drop in score is remembered too, so a later rise is measured from the new low
      follow.update!(last_score: cell.score, last_cleaned_at: cell.cleaned_at || follow.last_cleaned_at)
    end
  end

  # A published report was withdrawn or hidden: take back the alerts it could have caused, so the list does not
  # say "this place got worse" about a picture that is gone. `since` is when that report was published; only
  # alerts made after it are looked at. A "worse" alert goes when the cell now scores clearly below what the
  # alert announced (so a place still held up by other reports keeps it); a "cleaned" alert goes when the cell
  # no longer has a cleanup. Returns how many were removed.
  def self.retract(cell, since:)
    worse = Notification.where(h3_index: cell.h3_index, kind: "worse").where("created_at >= ?", since)
                        .where("score > ?", cell.score.to_f + WORSE_STEP)
    cleaned = cell.cleaned_at ? Notification.none : Notification.where(h3_index: cell.h3_index, kind: "cleaned").where("created_at >= ?", since)
    worse.delete_all + cleaned.delete_all
  end
end
