#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2034
# Shared helpers for paperclip-railway tests. Source this file; do not execute it.
# Secrets are never echoed. Only names, counts, and pass/fail results are printed.

: "${APP_URL:=http://paperclip.test:${PAPERCLIP_TEST_PORT:-18100}}"
: "${TEST_TIMEOUT:=900}"
: "${OWNER_EMAIL:=${PAPERCLIP_TEST_ADMIN_EMAIL:-owner@example.com}}"
: "${OWNER_PASSWORD:=${PAPERCLIP_TEST_ADMIN_PASSWORD:-local-test-only-admin-password}}"

# The local stack's public name is paperclip.test (see compose.yaml); point it at loopback without touching /etc/hosts.
CURL_EXTRA=()
case "$APP_URL" in
  http://paperclip.test:*) CURL_EXTRA=(--resolve "paperclip.test:${APP_URL##*:}:127.0.0.1") ;;
esac

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
export TEST_TMP
_PASS=0; _FAIL=0
CODE=""; BODY=""

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }
assert_not_contains() { if grep -q -- "$2" <<<"$3"; then fail "$1: found forbidden [$2]"; else pass "$1"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${CURL_EXTRA[@]}" "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# req JAR METHOD PATH [JSON] [extra curl args...]  -> sets CODE and BODY. JAR may be "" for an anonymous request.
# Mutations carry the app's Origin, as a browser would (Paperclip's board-mutation guard requires it).
req() {
  local jar=$1 method=$2 path=$3 data=${4:-}
  shift 3; [ $# -gt 0 ] && shift
  local args=(-s -o "$TEST_TMP/body" -w '%{http_code}' --max-time 60 -X "$method" -H "Origin: $APP_URL" -H 'Accept: application/json')
  [ -n "$jar" ] && args+=(-b "$jar" -c "$jar")
  [ -n "$data" ] && args+=(-H 'Content-Type: application/json' --data "$data")
  CODE=$(curl "${args[@]}" "${CURL_EXTRA[@]}" "$@" "$APP_URL$path" || true)
  BODY=$(cat "$TEST_TMP/body" 2>/dev/null || true)
}

# sign_in EMAIL PASSWORD JAR -> 0 on success; the session cookie lands in JAR.
sign_in() {
  rm -f "$3"
  req "$3" POST /api/auth/sign-in/email "$(jq -nc --arg e "$1" --arg p "$2" '{email:$e, password:$p}')"
  [ "$CODE" = "200" ]
}

# sign_up NAME EMAIL PASSWORD JAR [REFERER] -> sets CODE/BODY.
sign_up() {
  local extra=()
  rm -f "$4"
  [ -n "${5:-}" ] && extra=(-H "Referer: $5")
  req "$4" POST /api/auth/sign-up/email "$(jq -nc --arg n "$1" --arg e "$2" --arg p "$3" '{name:$n, email:$e, password:$p}')" "${extra[@]}"
}

# invite_token_from JSON -> the raw token from an invite-creation response.
invite_token_from() { jq -r '.token // (.inviteUrl // "" | sub(".*/invite/"; "") | sub("[?#].*"; ""))' <<<"$1"; }

rand() { head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
