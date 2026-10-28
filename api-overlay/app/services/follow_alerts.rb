# After a cell is re-scored: tell the people following it if it got clearly worse or was cleaned.
class FollowAlerts
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
end
