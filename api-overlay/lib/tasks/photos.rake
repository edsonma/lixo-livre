namespace :photos do
  desc "List reports whose photo file is missing from storage (e.g. uploaded before S3 was turned on, on a disk that was wiped). " \
       "CONFIRM=yes also deletes those reports and re-scores their map cells."
  task missing: :environment do
    gone = Trash.with_attached_photo.find_each.select do |trash|
      trash.photo.attached? && !trash.photo.blob.service.exist?(trash.photo.blob.key)
    end

    if gone.empty?
      puts "Every photo file is there."
      next
    end

    gone.each do |trash|
      puts "report #{trash.id}  #{trash.ai_status}#{trash.published? ? ' (published)' : ''}  taken #{trash.taken_at.to_date}  storage: #{trash.photo.blob.service_name}"
    end
    puts "#{gone.size} report(s) with a missing photo file."

    if ENV["CONFIRM"] == "yes"
      cells = gone.filter_map { |trash| trash.h3_index if trash.published? }.uniq
      gone.each(&:destroy)
      cells.each { |h3| RefreshHeatCellJob.perform_now(h3) } # in this process, so it finishes before the task exits
      puts "Deleted them and re-scored #{cells.size} map cell(s)."
    else
      puts "Nothing was deleted. To delete these reports: CONFIRM=yes bin/rails photos:missing"
    end
  end
end
