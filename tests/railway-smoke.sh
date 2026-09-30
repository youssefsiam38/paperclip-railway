#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Live end-to-end test against a deployed template, over HTTPS.
#
#   APP_URL=https://<domain> OWNER_EMAIL=<ADMIN_EMAIL> OWNER_PASSWORD_FILE=<file holding ADMIN_PASSWORD> \
#     STATE_FILE=/tmp/pc-live.json tests/railway-smoke.sh            # full run; records what it created
#   ... tests/railway-smoke.sh --verify                               # after a redeploy: is it all still there?
#
# Never prints the password, cookies or invite tokens.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
[ -n "${APP_URL:-}" ] || { echo "set APP_URL=https://<your-domain>" >&2; exit 2; }
[ -n "${OWNER_EMAIL:-}" ] || { echo "set OWNER_EMAIL (the template's ADMIN_EMAIL)" >&2; exit 2; }
[ -n "${OWNER_PASSWORD_FILE:-}" ] && OWNER_PASSWORD=$(cat "$OWNER_PASSWORD_FILE")
[ -n "${OWNER_PASSWORD:-}" ] || { echo "set OWNER_PASSWORD_FILE" >&2; exit 2; }
APP_URL=${APP_URL%/}
: "${STATE_FILE:=$(mktemp)}"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

OWNER=$TEST_TMP/owner.jar
MODE=${1:-full}

section "front door"
assert_eq "HTTPS /api/health" "200" "$(http_code "$APP_URL/api/health")"
assert_eq "the SPA is served" "200" "$(http_code "$APP_URL/")"

section "owner"
if sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD" "$OWNER"; then pass "owner signs in over HTTPS"; else fail "owner sign-in: HTTP $CODE"; fi
case "$APP_URL" in
  https://*) assert_eq "the session cookie is Secure" "TRUE" "$(awk '/session_token/ {print $4; exit}' "$OWNER")" ;;
esac
req "$OWNER" GET /api/auth/get-session
assert_eq "the session belongs to the owner" "$(tr '[:upper:]' '[:lower:]' <<<"$OWNER_EMAIL")" "$(jq -r '.user.email' <<<"$BODY")"

if [ "$MODE" = "--verify" ]; then
  section "after redeploy"
  CID=$(jq -r .companyId "$STATE_FILE"); ATT=$(jq -r .attachmentId "$STATE_FILE")
  req "$OWNER" GET "/api/companies/$CID"
  assert_eq "the company survived" "$(jq -r .companyName "$STATE_FILE")" "$(jq -r .name <<<"$BODY")"
  req "$OWNER" GET "/api/attachments/$ATT/content"
  assert_eq "the attachment survived" "$(jq -r .attachmentContent "$STATE_FILE")" "$BODY"
  INVITEE=$TEST_TMP/invitee.jar
  if sign_in "$(jq -r .inviteeEmail "$STATE_FILE")" "$(jq -r .inviteePassword "$STATE_FILE")" "$INVITEE"; then pass "the invited member signs in"; else fail "member sign-in: HTTP $CODE"; fi
  summary; exit $?
fi

if sign_in "$OWNER_EMAIL" "wrong-$(rand)" "$TEST_TMP/bad.jar"; then fail "a wrong password signs in"; else pass "a wrong password is refused ($CODE)"; fi
NAME="Live Co $(rand)"
req "$OWNER" POST /api/companies "$(jq -nc --arg n "$NAME" '{name:$n}')"
assert_eq "the owner is instance admin (creates a company)" "201" "$CODE"
CID=$(jq -r .id <<<"$BODY")

section "sign-up is invite-only"
body=$(jq -nc --arg e "stranger-$(rand)@example.com" '{name:"Stranger", email:$e, password:"stranger-password-123"}')
req "" POST /api/auth/sign-up/email "$body"
assert_eq "anonymous sign-up is refused" "403" "$CODE"
for p in /API/AUTH/SIGN-UP/EMAIL '/api/auth/sign-up%2Femail' '/api//auth/sign-up/email'; do
  req "" POST "$p" "$body"; assert_eq "path variant $p is gated" "403" "$CODE"
done
req "" POST /api/auth/sign-up/email "$body" -H "Referer: $APP_URL/invite/pcp_invite_$(rand)$(rand)"
assert_eq "a forged Referer is refused" "403" "$CODE"

section "invitations"
req "$OWNER" POST "/api/companies/$CID/invites" '{"allowedJoinTypes":"human"}'
assert_eq "owner creates a human invite" "201" "$CODE"
assert_contains "the invite URL uses the public domain" "^$APP_URL/invite/" "$(jq -r .inviteUrl <<<"$BODY")"
TOKEN=$(invite_token_from "$BODY")
INVITEE=$TEST_TMP/invitee.jar; INVITEE_EMAIL="invitee-$(rand)@example.com"; INVITEE_PASSWORD="invitee-$(rand)"
sign_up Invitee "$INVITEE_EMAIL" "$INVITEE_PASSWORD" "$INVITEE" "$APP_URL/invite/$TOKEN"
assert_eq "the invitee signs up from the invite page" "200" "$CODE"
req "$INVITEE" POST "/api/invites/$TOKEN/accept" '{"requestType":"human"}'
assert_eq "the invitee accepts" "202" "$CODE"
req "$INVITEE" GET "/api/companies/$CID"
assert_eq "the invitee can open the company" "200" "$CODE"
sign_up Reuse "reuse-$(rand)@example.com" "reuse-$(rand)" "$TEST_TMP/r.jar" "$APP_URL/invite/$TOKEN"
assert_eq "the used link cannot sign up anyone else" "403" "$CODE"

section "attachments"
req "$OWNER" POST "/api/companies/$CID/issues" '{"title":"Live issue"}'
assert_eq "owner creates an issue" "201" "$CODE"
IID=$(jq -r .id <<<"$BODY")
CONTENT="paperclip-railway live $(rand)"
printf '%s\n' "$CONTENT" >"$TEST_TMP/a.txt"
req "$OWNER" POST "/api/companies/$CID/issues/$IID/attachments" "" -F "file=@$TEST_TMP/a.txt;type=text/plain"
assert_eq "owner uploads an attachment" "201" "$CODE"
ATT=$(jq -r .id <<<"$BODY")
req "$OWNER" GET "/api/attachments/$ATT/content"
assert_eq "the attachment downloads intact" "$CONTENT" "$BODY"

section "agent run"
script='curl -fsS -H "Authorization: Bearer $PAPERCLIP_API_KEY" "$PAPERCLIP_API_URL/api/agents/me" | grep -q "\"id\"" && echo agent-probe-ok'
req "$OWNER" POST "/api/companies/$CID/agents" "$(jq -nc --arg s "$script" '{name:"Probe", role:"engineer", adapterType:"process", adapterConfig:{command:"sh", args:["-c",$s], timeoutSec:60}}')"
assert_eq "owner hires a process agent" "201" "$CODE"
AID=$(jq -r .id <<<"$BODY")
req "$OWNER" POST "/api/agents/$AID/heartbeat/invoke" '{}'
RID=$(jq -r .id <<<"$BODY"); st=""
for _ in $(seq 1 60); do
  req "$OWNER" GET "/api/heartbeat-runs/$RID"; st=$(jq -r .status <<<"$BODY")
  case $st in succeeded|failed|timed_out|cancelled) break ;; esac
  sleep 2
done
assert_eq "the heartbeat run succeeds" "succeeded" "$st"
req "$OWNER" GET "/api/heartbeat-runs/$RID/log"
assert_contains "the agent reached the API through the public URL" "agent-probe-ok" "$BODY"

jq -n --arg c "$CID" --arg n "$NAME" --arg a "$ATT" --arg t "$CONTENT" --arg e "$INVITEE_EMAIL" --arg p "$INVITEE_PASSWORD" \
  '{companyId:$c, companyName:$n, attachmentId:$a, attachmentContent:$t, inviteeEmail:$e, inviteePassword:$p}' >"$STATE_FILE"
chmod 600 "$STATE_FILE"
summary
