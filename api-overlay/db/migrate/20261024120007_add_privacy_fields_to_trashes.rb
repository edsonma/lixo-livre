class AddPrivacyFieldsToTrashes < ActiveRecord::Migration[8.0]
  def change
    # Set when the stored photo has been stripped of metadata and had faces/plates blurred.
    # Nothing is shown publicly or sent to the AI before this is set.
    add_column :trashes, :sanitized_at, :datetime

    # What the sanitizer learned: exif_present, exif_taken_at, exif_distance_m, redactions
    add_column :trashes, :photo_meta, :jsonb, null: false, default: {}
  end
end
