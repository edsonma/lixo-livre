#!/usr/bin/env fish
# Lixo Livre: generates the Rails API in ./api and applies api-overlay/ on top.
# Prerequisites: Ruby 3.3+, PostgreSQL with PostGIS installed
# (macOS: brew install postgis vips | Ubuntu: sudo apt install postgresql-16-postgis-3 libvips42)
# libvips is used to sanitize photos (strip EXIF, blur faces and plates).

set root (cd (dirname (status filename)); and pwd)
cd $root

if test -d api
    echo "api/ already exists, aborting so nothing is overwritten."
    exit 1
end

# Preflight: fail early and clearly instead of halfway through bundle install
if not command -q ruby
    echo "ruby not found. Install Ruby 3.3+ (mise, rbenv or Homebrew) and retry."
    exit 1
end
if not ruby -e 'exit(Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3") ? 0 : 1)'
    echo "Ruby 3.3+ is required, found "(ruby -e 'print RUBY_VERSION')" at "(command -s ruby)
    echo "If you use rbenv or mise, check that this folder is using the version you expect."
    exit 1
end
# gem and bundle must belong to the same Ruby as `ruby`, or gems get installed where bundler cannot see them
set ruby_bin (ruby -e 'print RbConfig.ruby')
set gem_bin (gem env | string match -r 'RUBY EXECUTABLE: (.*)' | tail -n 1)
if test "$gem_bin" != "$ruby_bin"
    echo "gem uses a different Ruby than ruby does:"
    echo "  ruby: $ruby_bin"
    echo "  gem:  $gem_bin"
    echo "This often causes 'Could not find nokogiri ... in locally installed gems'."
    echo "Continuing, but if bundler fails, fix your PATH (see: which -a ruby gem bundle) and retry."
end
# libvips is loaded by the ruby-vips gem when Rails boots, so without it nothing runs
if not command -q vips
    echo "libvips not found. Photo processing needs it. Install it and retry:"
    echo "  macOS:  brew install vips"
    echo "  Ubuntu: sudo apt install libvips42"
    exit 1
end
for tool in pg_config cmake
    command -q $tool; or echo "warning: $tool not found (needed for PostgreSQL client libs and the h3 gem)"
end

gem install rails --no-document
or exit 1

rails new api --api -d postgresql --skip-git --skip-docker --skip-kamal --skip-thruster --skip-solid
or exit 1

cd api

# PostGIS adapter replaces the plain postgresql adapter
# Add only the gems the generated Gemfile does not already have (it may list image_processing)
for g in activerecord-postgis-adapter h3 rack-cors rack-attack image_processing ruby-vips devise webauthn sentry-ruby sentry-rails
    if not grep -Eq "^[[:space:]]*gem ['\"]"$g"['\"]" Gemfile
        bundle add $g
        or exit 1
    end
end
if not grep -Eq "^[[:space:]]*gem ['\"]aws-sdk-s3['\"]" Gemfile
    bundle add aws-sdk-s3 --require=false
    or exit 1
end

# Active Storage tables (photos): created by a fixed migration in api-overlay/db/migrate
# (do not run active_storage:install, it stamps a new version every time)

# Copy our migrations, models, controllers, jobs, routes and config over the generated app
cp -R ../api-overlay/. .

# PostGIS adapter in database.yml, and DATABASE_URL scheme fix for hosts like Railway
ruby ../tools/patch_generated_app.rb .
or exit 1
chmod +x bin/railway-start

bin/rails db:create db:migrate
or exit 1

echo ""
echo "Done. Start the API with:  cd api; bin/rails server"
