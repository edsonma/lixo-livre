# "Seguir este local": a person follows a map cell (H3 index) and gets an in-app notification when it
# gets worse or is cleaned. last_score / last_cleaned_at are what the cell looked like at the last check.
class CreateFollowsAndNotifications < ActiveRecord::Migration[8.0]
  def change
    unless table_exists?(:follows)
      create_table :follows do |t|
        t.references :user, null: false, foreign_key: true
        t.string   :h3_index, null: false
        t.float    :last_score, null: false, default: 0
        t.datetime :last_cleaned_at
        t.timestamps
      end
      add_index :follows, %i[user_id h3_index], unique: true
      add_index :follows, :h3_index
    end

    unless table_exists?(:notifications)
      create_table :notifications do |t|
        t.references :user, null: false, foreign_key: true
        t.string   :kind, null: false # worse | cleaned
        t.string   :h3_index, null: false
        t.float    :score
        t.float    :previous_score
        t.float    :lat
        t.float    :lng
        t.datetime :read_at
        t.timestamps
      end
      add_index :notifications, %i[user_id read_at]
    end
  end
end
