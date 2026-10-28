# "Já foi limpo": a report can be a cleanup (a photo of a place that was dirty and is clean now).
# heat_cells.cleaned_at remembers the latest confirmed cleanup, so the map can show the place in green.
class AddCleanupSupport < ActiveRecord::Migration[8.0]
  def change
    add_column :trashes, :kind, :string, null: false, default: "dirty" unless column_exists?(:trashes, :kind)
    add_column :heat_cells, :cleaned_at, :datetime unless column_exists?(:heat_cells, :cleaned_at)
  end
end
