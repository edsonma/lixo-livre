# Backend architecture

The Rails API (`api-overlay/`) is organised so that each file has one reason to change and the dependency
arrows point one way: **controllers → use cases → models / services**. Nothing below knows about what is above it.

```
HTTP request
  controllers/api/v1/*        parse params, call ONE object, choose the status code and JSON
    controllers/concerns/     cross-cutting rules: auth guards, error mapping, CSRF-style origin check
    serializers/              turn records into JSON (no queries, no business rules)
  use_cases/                  one business action each (login, register, submit a report, review a report, update a profile)
  queries/                    read-side questions that are more than a scope (the moderation queues)
  models/                     data, validations, and behaviour that belongs to one record
    models/user/, trash/      the model's cohesive concerns (Publishing, Moderation, TwoFactor, ...)
  services/<domain>/          integrations and algorithms, grouped by domain (below)
  jobs/                       the background pipeline; each job calls services and models
```

## Where does new code go?

| If it is... | it goes in |
|---|---|
| reading params, picking a status code | the controller (keep actions to a few lines) |
| a rule about *who may call* an endpoint | `controllers/concerns/account_guards.rb` |
| JSON shape of a record | `serializers/` |
| a business action with several steps or expected failures | `use_cases/` (return `Outcome`) |
| "which records belong in this list" | `queries/` |
| something one record knows about itself | a concern under `models/<model>/` |
| talking to an outside system, or a self-contained algorithm | `services/<domain>/` |

## Use cases

A use case is a plain object with `self.call(...)`. Expected failures (wrong password, terms not accepted)
come back as `Outcome.failure(:symbol)`; the controller maps the symbol to a response. Programming or
validation errors raise and are handled by `ApiErrorHandling`. A use case never touches `params`, `render`
or the session, so it can be tested without HTTP.

Not every action needs one. Single-statement actions (consents, follows, destroying the account) stay in
their controller: a wrapper object would only add indirection.

## Service domains (`app/services`)

| Namespace | Holds |
|---|---|
| `Photos` | `Sanitizer` (strip metadata, blur faces/plates), `Metadata`, `ExifPreserver`, `PrivacyDetector`, `PrivacyRegion` |
| `Heat` | `Query` (map cells), `Score`, `PlaceHistory` |
| `Auth` | `Totp`, `OtpVault`, `PasskeyService`, `GoogleIdentity` |
| `Messaging` | `Mailer`, `UserEmails`, `AppUrl`, `FollowAlerts` |
| `Ops` | `DatabaseBackup`, `PipelineRecovery` |
| `Demo` | `Mode`, `Plan`, `Seeder` |
| `TrashVision` | the AI analysis and its provider adapters |
| `Geo` | distance helper shared by several domains |

Folders are namespaces (Zeitwerk): `services/photos/sanitizer.rb` defines `Photos::Sanitizer`. Tests mirror
the folders under `test/services/`.

## Conventions

- Fully qualify service constants (`Photos::Sanitizer`, not `Sanitizer`) so a reader can tell the domain.
- Model concerns declare their own exceptions (`Trash::NotReviewable`), so callers rescue a name that exists
  on the model.
- Controllers rescue specific domain errors; they never rescue `StandardError`.
- Keep behaviour changes out of structural commits. These refactors were made in small steps, each of which
  leaves the existing tests untouched.

# Web app architecture (`public/`)

The page is plain ES modules with no build step: `index.html` loads `js/main.js` with
`<script type="module">`. One module per screen, plus a few shared ones.

| Module | Holds |
|---|---|
| `main.js` | Calls each module's `boot()` in the order the page has always wired itself |
| `core.js`, `map.js`, `map_filters.js`, `search.js` | Start-up and server status; the map, heat layer, hexagon pins and (from zoom 14) one pin per photo; period/type filters; address search |
| `navigation.js`, `explore.js`, `place.js`, `my_photos.js`, `settings.js` | The three pages (Explorar, Mapa, Perfil), the place screen, the profile grid |
| `auth.js`, `passkeys.js`, `email_links.js`, `two_factor.js`, `terms.js`, `account_deletion.js`, `edit_profile.js` (+ `avatar.js`, the round picture) | Everything about accounts |
| `notifications.js`, `moderation.js` | Following places and alerts; the moderator queues |
| `report.js`, `camera.js`, `report_flow.js`, `analysis.js`, `analysis_types.js` | Reporting a photo: place, camera, upload, AI result |
| `dom.js`, `api.js`, `state.js`, `back_button.js` | Small DOM helpers, JSON requests and the device token, shared state, the phone's back button |

How it fits together:

- A module that needs something from another one `import`s it by name. A variable only its own module writes
  is a live `export`, so importers always see the current value.
- A variable that **more than one module writes** lives in `state.js` as `state.x`. Adding a key there is the
  deliberate way to share mutable state, so it stays visible in one place. Prefer passing values to functions.
- Code that wires buttons (`$("x").onclick = ...`) runs in the module's `boot()`, never at import time, so
  import order cannot change behaviour. `main.js` is the single place that decides the order. It matters where
  two handlers use the same element or event, and `loadMe()` starts only after the earlier wiring.
- Modules never reach into another screen's DOM. Use the owner's exported function (`openAuth`, `openPlace`).

Served by Rails as static files with `no-cache`, so a deploy is picked up on the next load; the browser
revalidates each module (a cheap "not modified"). If the number of modules grows a lot, bundle them.

## Testing the web app

`tools/test/frontend_smoke.py` serves `public/` with a small fake API and drives the real screens in headless
Chromium (boot, tabs, sign-in, profile, settings, moderation, tapping a pin, the whole report flow). For each
of 35 steps it records the open screen, key texts, the API calls made and console errors.

```fish
pip install playwright; playwright install chromium     # once
python3 tools/test/frontend_smoke.py --check tools/test/frontend_smoke.expected.json
```

It prints `frontend trace identical` or a diff. When you change behaviour on purpose, regenerate the expected
file (`python3 tools/test/frontend_smoke.py > tools/test/frontend_smoke.expected.json`) and review the diff.
Run it before and after any refactor of `public/js`.

## Profile editing

`PATCH /api/v1/profile` (`ProfilesController` -> `UpdateProfile`) lets a signed-in person change only their full name,
bio (160 characters), website, gender and picture. The email is the login and is never read from the request, nor is the
role. Rules for the text live in `ProfileText` (plain functions) and are enforced by `User::Profile`; the website must
be an http(s) address. The picture goes through `Photos::Avatar`: centred 512 px square JPEG, EXIF orientation applied,
all metadata stripped. Gender is private: it is sent only to its owner. The picture is delivered by path like report
photos (`ACTIVE_STORAGE_DELIVERY`). Run `bin/rails db:migrate` for the three new columns.
