# Severity used to be 1..5; it is now 0..100. Existing values are multiplied by 20 (1 -> 20 ... 5 -> 100).
# A heat cell's score is linear in severity, so it scales by the same factor and needs no recompute.
class RescaleSeverityTo100 < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE trashes SET severity = severity * 20 WHERE severity BETWEEN 1 AND 5"
    execute "UPDATE heat_cells SET score = score * 20"
  end

  def down
    execute "UPDATE heat_cells SET score = score / 20"
    execute "UPDATE trashes SET severity = GREATEST(1, ROUND(severity / 20.0)) WHERE severity IS NOT NULL"
  end
end
