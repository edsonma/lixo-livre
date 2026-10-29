namespace :db do
  desc "Upload a pg_dump of the database to BACKUP_BUCKET and keep the newest BACKUP_KEEP copies"
  task backup: :environment do
    key = DatabaseBackup.from_env.run
    puts "Backup uploaded: #{key}"
  end
end
