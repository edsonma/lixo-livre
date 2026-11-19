namespace :data do
  desc "Start over: delete every report (and its photo file), flag, notification and map cell. Accounts are kept. " \
       "WITH_USERS=yes also deletes accounts, follows, devices and passkeys. Needs CONFIRM=yes, otherwise only counts what would go."
  task wipe: :environment do
    counts = { reports: Trash.count, flags: Flag.count, notifications: Notification.count, heat_cells: HeatCell.count }
    counts[:users] = User.count if ENV["WITH_USERS"] == "yes"
    puts "Would delete: #{counts.map { |k, v| "#{v} #{k}" }.join(', ')}"

    unless ENV["CONFIRM"] == "yes"
      puts "Nothing was deleted. To go ahead: CONFIRM=yes bin/rails data:wipe"
      next
    end

    ActiveRecord::Base.transaction do
      Flag.delete_all
      Notification.delete_all
      Trash.find_each(&:destroy)   # destroy (not delete) so the photo files are removed from storage too
      HeatCell.delete_all
      if ENV["WITH_USERS"] == "yes"
        Follow.delete_all
        Device.delete_all
        Passkey.delete_all
        User.find_each(&:destroy)
      end
    end
    puts "Done. The map is empty."
  end
end
