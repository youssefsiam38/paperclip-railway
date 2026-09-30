#!/usr/bin/env bash
# Railway start-up, second stage (runs as `node`). Order matters:
#   0. with S3 storage, the bucket is created if missing
#   1. Paperclip starts on 127.0.0.1:$PAPERCLIP_INTERNAL_PORT (nothing is reachable from outside yet)
#   2. the owner is seeded and made instance admin
#   3. the signup gate and Caddy start; only now does $PORT answer, so nobody can race the owner
# If any process exits, the others are stopped and the container exits so Railway restarts it.
set -euo pipefail

log() { printf 'paperclip-railway: %s\n' "$*" >&2; }

INTERNAL_PORT=${PAPERCLIP_INTERNAL_PORT:-3101}
BOOT_TIMEOUT=${PAPERCLIP_BOOT_TIMEOUT_SEC:-900}
RAILWAY_DIR=/opt/paperclip-railway

pids=()
shutdown() {
  trap - TERM INT
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap 'shutdown; exit 143' TERM INT

cd /app

if [ "${PAPERCLIP_STORAGE_PROVIDER:-local_disk}" = "s3" ]; then
  node "$RAILWAY_DIR/ensure-bucket.mjs" || { log "object storage is not usable; not starting"; exit 1; }
fi

# Paperclip always has Better Auth sign-up enabled; who may sign up is decided by the gate in front of it.
# PAPERCLIP_BIND=loopback keeps it off every non-loopback interface regardless of what HOST Railway injects.
# ADMIN_* stay out of its environment: Paperclip passes its environment on to agent processes.
env -u ADMIN_EMAIL -u ADMIN_PASSWORD -u ADMIN_NAME HOST=127.0.0.1 PAPERCLIP_BIND=loopback PORT="$INTERNAL_PORT" PAPERCLIP_AUTH_DISABLE_SIGN_UP=false \
  node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js &
app_pid=$!
pids+=("$app_pid")

log "waiting for Paperclip on 127.0.0.1:$INTERNAL_PORT (first start applies database migrations)"
start=$(date +%s)
until curl -fsS -o /dev/null --max-time 5 "http://127.0.0.1:$INTERNAL_PORT/api/health"; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid" || code=$?
    log "Paperclip exited during start-up (code ${code:-0})"
    exit "${code:-1}"
  fi
  if [ $(( $(date +%s) - start )) -ge "$BOOT_TIMEOUT" ]; then
    log "Paperclip did not become healthy within ${BOOT_TIMEOUT}s"
    shutdown; exit 1
  fi
  sleep 2
done
log "Paperclip is up"

if ! node "$RAILWAY_DIR/bootstrap-owner.mjs"; then
  log "owner bootstrap failed; not exposing the instance"
  shutdown; exit 1
fi

node "$RAILWAY_DIR/signup-gate.mjs" &
pids+=("$!")
caddy run --adapter caddyfile --config "$RAILWAY_DIR/Caddyfile" &
pids+=("$!")
log "listening on :${PORT} (sign-up mode: ${PAPERCLIP_SIGNUP_MODE:-invite-only})"

set +e
wait -n "${pids[@]}"
code=$?
set -e
log "a process exited (code $code); stopping the others"
shutdown
exit "$code"
