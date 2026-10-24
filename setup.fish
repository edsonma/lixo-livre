#!/usr/bin/env fish
# Lixo Livre: generates the Rails API in ./api and applies api-overlay/ on top.
# Prerequisites: Ruby 3.3+, PostgreSQL with PostGIS installed
# (macOS: brew install postgis | Ubuntu: sudo apt install postgresql-16-postgis-3)

set root (cd (dirname (status filename)); and pwd)
cd $root

if test -d api
    echo "api/ already exists, aborting so nothing is overwritten."
    exit 1
end

gem install rails --no-document
or exit 1

rails new api --api -d postgresql --skip-git
or exit 1

cd api

# PostGIS adapter replaces the plain postgresql adapter
bundle add activerecord-postgis-adapter h3 rack-cors rack-attack image_processing
or exit 1
sed -i.bak 's/adapter: postgresql/adapter: postgis/' config/database.yml
rm config/database.yml.bak

# Active Storage tables (photos)
rails active_storage:install

# Copy our migrations, models, controllers, jobs, routes and config over the generated app
cp -R ../api-overlay/. .

rails db:create db:migrate

echo ""
echo "Done. Start the API with:  cd api; bin/rails server"
