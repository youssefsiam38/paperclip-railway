#!/bin/sh
# Railway start-up, first stage (runs as root under tini). Validates the template inputs, then hands over to the
# upstream entrypoint, which fixes /paperclip ownership and drops to the `node` user before running the supervisor.
set -eu

die() { printf 'paperclip-railway: %s\n' "$*" >&2; exit 1; }

[ -n "${DATABASE_URL:-}" ] || die "DATABASE_URL is not set. This template uses the bundled PostgreSQL service."
[ -n "${BETTER_AUTH_SECRET:-}" ] || die "BETTER_AUTH_SECRET is not set."
[ -n "${PAPERCLIP_PUBLIC_URL:-}" ] || die "PAPERCLIP_PUBLIC_URL is not set (e.g. https://your-app.up.railway.app)."
case "$PAPERCLIP_PUBLIC_URL" in
  http://*|https://*) ;;
  *) die "PAPERCLIP_PUBLIC_URL must start with https:// (got a value without a scheme)." ;;
esac
case "${PAPERCLIP_SIGNUP_MODE:-invite-only}" in
  invite-only|open|closed) ;;
  *) die "PAPERCLIP_SIGNUP_MODE must be invite-only, open or closed." ;;
esac
case "${ADMIN_EMAIL:-}" in
  ?*@?*.?*) ;;
  *) die "ADMIN_EMAIL must be the owner's email address." ;;
esac
pw=${ADMIN_PASSWORD:-}
[ "${#pw}" -ge 8 ] || die "ADMIN_PASSWORD must be at least 8 characters."
[ "${#pw}" -le 128 ] || die "ADMIN_PASSWORD must be at most 128 characters."
unset pw

if [ "$(id -u)" -ne 0 ]; then
  exec /opt/paperclip-railway/supervisor.sh
fi
exec /usr/local/bin/docker-entrypoint.sh /opt/paperclip-railway/supervisor.sh
