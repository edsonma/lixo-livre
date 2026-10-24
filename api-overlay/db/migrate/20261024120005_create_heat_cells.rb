class CreateHeatCells < ActiveRecord::Migration[8.0]
  def change
    # Precomputed grid for the web heatmap (score = recency-weighted severity)
    create_table :heat_cells do |t|
      t.string  :h3_index, null: false
      t.integer :resolution, null: false, default: 9 # ~170 m hexagons
      t.st_point :lonlat, geographic: true, null: false # cell center
      t.float   :score, null: false, default: 0
      t.integer :reports_count, null: false, default: 0
      t.datetime :computed_at
      t.timestamps
    end

    add_index :heat_cells, [:h3_index, :resolution], unique: true
    add_index :heat_cells, :lonlat, using: :gist
    add_index :heat_cells, :score
  end
end
