#!/usr/bin/env ruby
# Two edits to a freshly generated Rails app that cannot live in api-overlay/ because they change
# files Rails generates. Used by both setup.fish and the Docker build. Safe to run twice.
#
#   ruby tools/patch_generated_app.rb [path/to/api]
#
# 1. config/database.yml: use the PostGIS adapter instead of plain postgresql.
# 2. config/boot.rb: hosts (Railway, Heroku, ...) hand out postgres:// or postgresql:// URLs in
#    DATABASE_URL, but the PostGIS adapter only takes over for postgis:// URLs, so the scheme is
#    rewritten before Rails reads it.

BOOT_MARKER = "# lixo-livre: DATABASE_URL scheme".freeze
BOOT_SNIPPET = <<~RUBY.freeze
  #{BOOT_MARKER}
  # Hosts give out postgres:// or postgresql:// URLs; the PostGIS adapter needs postgis://.
  if (url = ENV["DATABASE_URL"]) && url.match?(/\\Apostgres(ql)?:/)
    ENV["DATABASE_URL"] = url.sub(/\\Apostgres(ql)?:/, "postgis:")
  end

RUBY

def fail_with(message)
  warn "patch_generated_app: #{message}"
  exit 1
end

root = File.expand_path(ARGV.fetch(0, "."))
database_yml = File.join(root, "config", "database.yml")
boot_rb = File.join(root, "config", "boot.rb")
fail_with("#{database_yml} not found: run this inside the generated Rails app") unless File.file?(database_yml)
fail_with("#{boot_rb} not found: run this inside the generated Rails app") unless File.file?(boot_rb)

yml = File.read(database_yml)
if yml.include?("adapter: postgis")
  puts "database.yml: already uses postgis"
elsif yml.include?("adapter: postgresql")
  File.write(database_yml, yml.gsub("adapter: postgresql", "adapter: postgis"))
  puts "database.yml: adapter set to postgis"
else
  fail_with("could not find 'adapter: postgresql' in #{database_yml}")
end

boot = File.read(boot_rb)
if boot.include?(BOOT_MARKER)
  puts "boot.rb: DATABASE_URL rewrite already present"
else
  File.write(boot_rb, BOOT_SNIPPET + boot)
  puts "boot.rb: added DATABASE_URL rewrite"
end
