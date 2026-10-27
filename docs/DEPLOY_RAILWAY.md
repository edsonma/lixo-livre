# Deploying on Railway

This gets a public URL with the heat map, fake reports with photos, and a working upload API.
The AI is fake and nothing is blurred, so this is for trying and showing the product, not for real users.

## What you need

- A Railway account and this repo on GitHub.
- Nothing installed locally. If `api/` is not committed, the Docker build generates the Rails app from `api-overlay/` (the same steps as `setup.fish`).

## Steps

1. **New project** → *Deploy from GitHub repo* → pick `lixo-livre`. Railway finds the `Dockerfile` through `railway.toml`.
2. **Add a database with PostGIS.** Railway's default PostgreSQL does not include the extension, and a PostGIS template may not be in the catalogue, so run the official image as its own service:
   1. *New* → *Docker Image* → `postgis/postgis:16-3.4`.
   2. In that service's variables: `POSTGRES_PASSWORD` (use only letters and digits, for example the output of `openssl rand -hex 16`: characters like `@ # / :` break a URL), `POSTGRES_DB=lixo_livre`, and `PGDATA=/var/lib/postgresql/data/pgdata` (a Railway volume contains `lost+found`, which makes Postgres refuse to start without this).
   3. Add a volume mounted at `/var/lib/postgresql/data`.
   4. Do not generate a public domain: the API reaches it over the private network.
   5. If your catalogue does list a PostGIS template, you can use that instead.

   The first migration runs `CREATE EXTENSION postgis`.
3. **Variables** on the API service:

   | Variable | Value | Notes |
   |---|---|---|
   | `DATABASE_URL` | `postgres://postgres:${{<db-service>.POSTGRES_PASSWORD}}@<db-service>.railway.internal:5432/lixo_livre` | Replace `<db-service>` with your database service's name. With a Railway Postgres template, use `${{Postgres.DATABASE_URL}}` instead. The `postgres://` scheme is rewritten to `postgis://` at boot. |
   | `SECRET_KEY_BASE` | output of `openssl rand -hex 64` | Required. |
   | `DEMO_MODE` | `true` | Fake AI, no face/plate detection. |
   | `SEED_DEMO_DATA` | `true` | Loads fake reports at start, only if there are none yet. |
   | `TRASH_VISION_PROVIDER` | `anthropic` | Optional: use a real AI for the analysis (works with `DEMO_MODE`). Also set `ANTHROPIC_API_KEY`. For `openai` set `OPENAI_API_KEY` and `TRASH_VISION_MODEL`. |
   | `EXIF_MAX_DISTANCE_M` | `1000` | Optional: how far (meters) a photo's EXIF GPS may be from the chosen spot before the report is held for review. Raise it (e.g. `50000`) when testing with gallery photos. |
   | `ADMIN_EMAILS` | `you@example.com` | Optional, comma separated. These emails become admins when they sign up or log in. Or run `bin/rails users:promote EMAIL=you@example.com` in the Railway shell. |
   | `GOOGLE_CLIENT_ID` | `123-abc.apps.googleusercontent.com` | Optional: shows the "Continuar com o Google" button. Create an *OAuth client ID* of type *Web application* in Google Cloud Console (APIs & Services → Credentials) and add your Railway domain (`https://<your-domain>`) under *Authorized JavaScript origins*. No client secret is needed. |
   | `APP_ORIGIN` | `https://<your-domain>` | Optional: the site's public origin, used by passkeys (fingerprint / face). Defaults to the address of the request, which is right on Railway. |
   | `AUTO_PUBLISH` | `true` | Optional. Skip the "Publicar" step: reports go to the map as soon as the AI validates them. |
   | `DEMO_COUNT` | `220` | Optional. |
   | `DEMO_CENTER` | `-23.55,-46.63` | Optional, `lat,lng`. Default is Brasília. |
   | `RAILS_LOG_TO_STDOUT` | `true` | Optional, logs in the Railway panel. |

4. **Volume** (so photos survive a redeploy): service → *Volumes* → mount path `/app/api/storage`. Without it the container's disk is wiped on every deploy while the database keeps its records, so the map would show broken images. If that happens, run `bin/rails demo:reset demo:seed` from the Railway shell.
5. **Networking**: *Generate domain*. Open it: the demo map is at `/`, the health check at `/up`, the status at `/api/v1/status`.

## Try the upload API

```sh
URL=https://your-app.up.railway.app
TOKEN=$(curl -s -X POST $URL/api/v1/devices | jq -r .token)

curl -s -X POST $URL/api/v1/trashes \
  -H "X-Device-Token: $TOKEN" \
  -F photo=@some-photo.jpg -F lat=-15.79 -F lng=-47.88 \
  -F taken_at=$(date -u +%FT%TZ) -F extra_info="test"

curl -s $URL/api/v1/me/trashes -H "X-Device-Token: $TOKEN"
```

The report starts `pending`, is sanitized and scored by the fake AI in a few seconds, then appears on the map.
Note: if the photo carries GPS in its EXIF and it is far from `lat`/`lng`, the report goes to review (by design).

## How it behaves

- Jobs run in the web process (Active Job async adapter). A restart can drop queued jobs, so every 6 hours (`MAINTENANCE_INTERVAL_MINUTES`) a background thread re-queues reports stuck in `pending` and recomputes the heat cells. Set `BACKGROUND_MAINTENANCE=false` to turn it off.
- Boot runs `db:prepare` (migrations), optionally the seed, then the server on `$PORT`.
- Without `DEMO_MODE`, the app refuses to use the fake AI: uploads end in `needs_review` until you plug in real providers.

## Going beyond a demo

- `DEMO_MODE=false`, `SEED_DEMO_DATA` removed, `bin/rails demo:reset` once to clear the fake data.
- Real `TrashVision.provider` and `PrivacyDetector.provider` (see the README).
- Photos on S3-compatible storage: `ACTIVE_STORAGE_SERVICE=s3`, `S3_BUCKET`, `S3_REGION`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, and `S3_ENDPOINT` for R2 or similar. Then the volume is no longer needed.
- Run `./setup.fish` locally and commit `api/` so `Gemfile.lock` pins the gem versions.
- A separate worker for jobs, a non-root `USER` in the Dockerfile, and restrict CORS origins.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Deploy fails at `CREATE EXTENSION postgis` | The database is plain PostgreSQL. Use the `postgis/postgis` image. |
| `connection to server at "69.46.46.69" ... Connection timed out` (any public IP) | The host in `DATABASE_URL` or `PGHOST` is a public address (`*.up.railway.app`, `*.proxy.rlwy.net`). Use the private name `<database-service>.railway.internal` with port 5432 (Settings → Networking → Private Networking on the database service). Do not generate a public domain for the database. |
| `PG::DuplicateTable: relation "active_storage_blobs" already exists` | Fixed in the repo (Active Storage now has one fixed migration that skips tables that exist). Redeploy the latest commit. |
| `could not translate host name` | The service name in `DATABASE_URL` does not match the database service. |
| `DATABASE_URL still contains a Railway reference` | The `${{...}}` part was not filled in: the service name inside it does not match the database service. |
| `DATABASE_URL is not a valid URL`, or `connection_url_resolver.rb` in the error | A special character in the password, or a broken reference. Use a letters-and-digits password, or delete `DATABASE_URL` and set `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` instead: the app builds and encodes the URL itself. |
| Database service crashes on start with a `lost+found` message | `PGDATA` is not set to a subfolder of the volume. |
| `SECRET_KEY_BASE is not set` in the logs | Add the variable. |
| `PG::ConnectionBad` / adapter errors | `DATABASE_URL` missing or not referencing the database service. |
| Healthcheck fails | Check the deploy logs: migrations or the seed raised. The health check waits up to 5 minutes. |
| Map is empty | `SEED_DEMO_DATA` not set, or the map is not near `DEMO_CENTER`. Check `/api/v1/status` for counts. |
| Photos broken after redeploy | No volume on `/app/api/storage`. |
| Uploads stay `needs_review` | `DEMO_MODE` is not `true` and no providers are configured. |
