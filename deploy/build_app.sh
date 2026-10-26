#!/usr/bin/env bash
# Called by the Dockerfile:  build_app.sh SRC DEST
# Leaves a ready-to-run Rails app in DEST/api.
#
#  - If the repo has a committed api/ (you ran setup.fish and committed the result), that app is
#    used as it is: reproducible, because its Gemfile.lock is pinned.
#  - Otherwise the Rails app is generated here from api-overlay/, with the same steps as
#    setup.fish, so you can deploy without Ruby installed locally. Gem versions then float
#    within Rails 8, so for anything beyond a demo commit api/ instead.
set -euo pipefail

src=${1:?usage: build_app.sh SRC DEST}
dest=${2:?usage: build_app.sh SRC DEST}
mkdir -p "$dest"
export SECRET_KEY_BASE_DUMMY=1 # lets Rails boot during the build without real secrets

if [ -f "$src/api/Gemfile" ]; then
  echo "==> Using the committed api/ directory"
  cp -R "$src/api" "$dest/api"
  cd "$dest/api"
  bundle install --jobs 4
  [ -f bin/railway-start ] || cp "$src/api-overlay/bin/railway-start" bin/railway-start
else
  echo "==> No api/ in the repo: generating the Rails app from api-overlay/"
  gem install rails -v '~> 8.0' --no-document
  cd "$dest"
  rails new api --api -d postgresql --skip-git --skip-docker --skip-kamal --skip-thruster --skip-solid
  cd api
  # Add only the gems the generated Gemfile does not already have (it may list image_processing)
  for g in activerecord-postgis-adapter h3 rack-cors rack-attack image_processing ruby-vips; do
    grep -Eq "^[[:space:]]*gem ['\"]$g['\"]" Gemfile || bundle add "$g"
  done
  grep -Eq "^[[:space:]]*gem ['\"]aws-sdk-s3['\"]" Gemfile || bundle add aws-sdk-s3 --require=false
  # No active_storage:install: its migration gets a new timestamp on every build. The overlay has a fixed one.
  cp -R "$src/api-overlay/." .
  ruby "$src/tools/patch_generated_app.rb" .
fi

chmod +x bin/railway-start
echo "==> App ready in $dest/api"
