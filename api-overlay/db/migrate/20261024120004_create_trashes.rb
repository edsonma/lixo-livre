class CreateTrashes < ActiveRecord::Migration[8.0]
  def change
    create_table :trashes do |t|
      t.references :device, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true # nil = anonymous

      t.st_point :lonlat, geographic: true, null: false # x = longitude, y = latitude
      t.string   :h3_index, null: false                 # H3 cell (resolution 9), set from lonlat
      t.datetime :taken_at, null: false                 # when the photo was taken

      t.integer  :severity                              # 1..5, set by the AI only
      t.string   :trash_types, array: true, default: [] # filled by the AI
      t.text     :extra_info                            # free text from the person

      t.string   :ai_status, null: false, default: "pending"
      t.float    :ai_confidence
      t.jsonb    :ai_payload, default: {}               # raw AI response, for debugging
      t.datetime :validated_at
      t.datetime :hidden_at                             # set when flags hide the report

      t.timestamps
    end

    add_index :trashes, :lonlat, using: :gist
    add_index :trashes, :trash_types, using: :gin
    add_index :trashes, :h3_index
    add_index :trashes, [:ai_status, :taken_at]
  end
end
