# syntax=docker/dockerfile:1
# Lixo Livre API, for Railway or any Docker host. See docs/DEPLOY_RAILWAY.md.
#
# The Rails app is built by deploy/build_app.sh: the committed api/ if there is one, otherwise
# generated from api-overlay/ (so you can deploy without Ruby installed locally).
FROM ruby:3.3-slim-bookworm

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    LANG=C.UTF-8

# build-essential, cmake: native gems (h3 needs cmake). libvips: photo processing.
# libgeos: lets rgeo use GEOS, as it does on a typical dev machine. postgresql-client: dbconsole.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl cmake pkg-config libpq-dev libyaml-dev libgeos-dev libvips42 postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY . /src
RUN bash /src/deploy/build_app.sh /src /app

# Runs as root on purpose: a Railway volume mounted at storage/ is root-owned, and a non-root
# user could not write the photos there. Before going beyond a demo, move photos to S3-compatible
# storage (ACTIVE_STORAGE_SERVICE=s3) and add a non-root USER.
WORKDIR /app/api
EXPOSE 3000
CMD ["bin/railway-start"]
