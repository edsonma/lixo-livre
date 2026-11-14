# Backend architecture

The Rails API (`api-overlay/`) is organised so that each file has one reason to change and the dependency
arrows point one way: **controllers → use cases → models / services**. Nothing below knows about what is above it.

```
HTTP request
  controllers/api/v1/*        parse params, call ONE object, choose the status code and JSON
    controllers/concerns/     cross-cutting rules: auth guards, error mapping, CSRF-style origin check
    serializers/              turn records into JSON (no queries, no business rules)
  use_cases/                  one business action each (login, register, submit a report, review a report)
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

## Not yet done

`public/app.js` is still one 1,600-line closure. Its sections are marked (`// ---- Section ----`), but they
share about thirty mutable variables (`me`, `map`, `place`, `draft`, `stream`, ...) and every section calls
four to six others, so a safe split needs a shared-state module and a browser test harness first.
