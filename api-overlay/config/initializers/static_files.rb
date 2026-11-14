# The demo page (public/index.html, js/, app.css) is served by Rails itself. Without this, a phone can
# keep an old copy for hours after a deploy. "no-cache" means: always ask the server, and reuse the
# copy only if it answers "not modified" (a cheap check, the files are small).
#
# The other headers are the ones Rails already puts on API answers but not on files from public/:
# the page cannot be shown inside another site's frame (clickjacking on "delete account" and the like),
# browsers must not guess a file's type, and the address of a page (it can carry a reset or
# verification token) is not sent to other sites except as a bare origin.
Rails.application.config.public_file_server.headers = {
  "cache-control" => "no-cache",
  "x-content-type-options" => "nosniff",
  "x-frame-options" => "SAMEORIGIN",
  "referrer-policy" => "strict-origin-when-cross-origin"
}
