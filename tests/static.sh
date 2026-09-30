#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose, image pins and security defaults. No Docker build.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "syntax"
for f in tests/*.sh images/paperclip/railway/supervisor.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in images/paperclip/railway/start.sh images/storage/entrypoint.sh; do
  if sh -n "$f"; then pass "parses: $f (POSIX sh)"; else fail "syntax error: $f"; fi
done
if command -v node >/dev/null; then
  for f in images/paperclip/railway/*.mjs; do
    if node --check "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
  done
else
  echo "  SKIP  node not installed"
fi

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh images/paperclip/railway/supervisor.sh; then pass "shellcheck bash"; else fail "shellcheck bash"; fi
  if shellcheck -s sh images/paperclip/railway/start.sh images/storage/entrypoint.sh; then pass "shellcheck sh"; else fail "shellcheck sh"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "three services" "db paperclip storage" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "only paperclip publishes a port" "paperclip" "$(jq -r '[.services | to_entries[] | select(.value.ports) | .key] | join(" ")' <<<"$cfg")"
assert_eq "the port binds to loopback" "127.0.0.1" "$(jq -r '[.services.paperclip.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the published port is the front door (\$PORT)" "$(jq -r '.services.paperclip.environment.PORT' <<<"$cfg")" "$(jq -r '[.services.paperclip.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the paperclip data volume is mounted" "/paperclip" "$(jq -r '[.services.paperclip.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the storage volume is mounted" "/data" "$(jq -r '[.services.storage.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "uploads go to S3 storage" "s3" "$(jq -r '.services.paperclip.environment.PAPERCLIP_STORAGE_PROVIDER' <<<"$cfg")"
assert_eq "the S3 client uses path-style URLs" "true" "$(jq -r '.services.paperclip.environment.PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE' <<<"$cfg")"
assert_eq "the database volume is mounted at the parent dir" "/var/lib/postgresql" "$(jq -r '[.services.db.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_contains "postgres is pinned by tag and digest" '@sha256:[0-9a-f]\{64\}$' "$(jq -r '.services.db.image' <<<"$cfg")"
assert_contains "the DB connection string is set" '^postgres://' "$(jq -r '.services.paperclip.environment.DATABASE_URL' <<<"$cfg")"
assert_eq "the storage service publishes no port" "" "$(jq -r '[.services.storage.ports[]?] | length | select(. > 0)' <<<"$cfg")"
assert_contains "the compose admin password is a placeholder" 'local-test-only' "$(jq -r '.services.paperclip.environment.ADMIN_PASSWORD' <<<"$cfg")"

section "image"
df=images/paperclip/Dockerfile
assert_contains "paperclip base pinned by digest" '^ARG PAPERCLIP_IMAGE=ghcr.io/paperclipai/paperclip:.*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG PAPERCLIP_IMAGE=' "$df")"
assert_contains "rustfs pinned by digest" '^ARG RUSTFS_IMAGE=.*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG RUSTFS_IMAGE=' images/storage/Dockerfile)"
assert_contains "caddy pinned by digest" '^ARG CADDY_IMAGE=.*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG CADDY_IMAGE=' "$df")"
assert_contains "authenticated mode" 'PAPERCLIP_DEPLOYMENT_MODE=authenticated' "$(cat "$df")"
assert_contains "public exposure (browser claim disabled)" 'PAPERCLIP_DEPLOYMENT_EXPOSURE=public' "$(cat "$df")"
assert_contains "invite-only sign-up by default" 'PAPERCLIP_SIGNUP_MODE=invite-only' "$(cat "$df")"
assert_contains "upstream tini stays PID 1" '"/usr/bin/tini", "--"' "$(cat "$df")"

section "front door"
sup=images/paperclip/railway/supervisor.sh
cf=images/paperclip/railway/Caddyfile
assert_contains "Paperclip binds loopback only" 'HOST=127.0.0.1 PAPERCLIP_BIND=loopback' "$(cat "$sup")"
assert_contains "the gate binds loopback only" 'listen(port, "127.0.0.1"' "$(cat images/paperclip/railway/signup-gate.mjs)"
# The owner must be seeded before Caddy (the only public listener) starts.
boot_line=$(grep -n 'bootstrap-owner.mjs' "$sup" | head -1 | cut -d: -f1)
caddy_line=$(grep -n '^caddy run' "$sup" | head -1 | cut -d: -f1)
if [ -n "$boot_line" ] && [ -n "$caddy_line" ] && [ "$boot_line" -lt "$caddy_line" ]; then pass "owner bootstrap runs before Caddy listens"; else fail "owner bootstrap must run before Caddy"; fi
assert_contains "every sign-up path is gated" '@signup path /api/auth/sign-up\*' "$(cat "$cf")"
assert_contains "the gate is a forward_auth" 'forward_auth 127.0.0.1:{$PAPERCLIP_GATE_PORT}' "$(cat "$cf")"
assert_contains "the admin API is off" 'admin off' "$(cat "$cf")"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*' -not -path './test-output/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi
assert_not_contains "bootstrap never logs the password" 'log(.*\${password' "$(cat images/paperclip/railway/bootstrap-owner.mjs)"

summary
