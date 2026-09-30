#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: data written before `compose down` (volumes kept) is still there after `compose up`, the owner can
# still sign in, and the owner bootstrap does not run again. Mirrors a Railway redeploy of every service.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

OWNER=$TEST_TMP/owner.jar

section "write"
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/api/health" 200 || die "Paperclip never became healthy"
sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD" "$OWNER" || die "owner sign-in failed: HTTP $CODE"
NAME="Persist Co $(rand)"
req "$OWNER" POST /api/companies "$(jq -nc --arg n "$NAME" '{name:$n}')"
assert_eq "create a company" "201" "$CODE"
CID=$(jq -r .id <<<"$BODY")
req "$OWNER" POST "/api/companies/$CID/issues" '{"title":"Persisted issue"}'
IID=$(jq -r .id <<<"$BODY")
printf 'persisted %s\n' "$(rand)" >"$TEST_TMP/p.txt"
req "$OWNER" POST "/api/companies/$CID/issues/$IID/attachments" "" -F "file=@$TEST_TMP/p.txt;type=text/plain"
assert_eq "upload an attachment" "201" "$CODE"
ATT=$(jq -r .id <<<"$BODY")

section "recreate every service, keep volumes"
compose down >/dev/null 2>&1
compose up -d >/dev/null 2>&1 || die "compose up failed"
wait_for_code "$APP_URL/api/health" 200 || die "Paperclip never came back"

section "read"
if sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD" "$OWNER"; then pass "owner signs in after recreate"; else fail "owner sign-in: HTTP $CODE"; fi
req "$OWNER" GET "/api/companies/$CID"
assert_eq "the company survived" "$NAME" "$(jq -r .name <<<"$BODY")"
req "$OWNER" GET "/api/attachments/$ATT/content"
assert_eq "the attachment survived" "$(cat "$TEST_TMP/p.txt")" "$BODY"
assert_contains "the bootstrap did not run again" "owner bootstrap skipped" "$(compose logs --no-color paperclip 2>&1)"

summary
