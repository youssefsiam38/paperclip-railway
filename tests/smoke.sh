#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Local end-to-end smoke test against a fresh compose stack (the image must already be built).
# Covers: front door, loopback-only internals, owner bootstrap, invite-only sign-up (and its bypass attempts),
# the invitation flow, instance-admin powers, attachments on the volume, an agent run, restart idempotency,
# and the closed sign-up mode.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

OWNER=$TEST_TMP/owner.jar
up_fresh() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  compose up -d >/dev/null 2>&1 || die "compose up failed"
  wait_for_code "$APP_URL/api/health" 200 || { compose logs --tail 80 paperclip >&2; die "Paperclip never became healthy"; }
}

section "start-up"
up_fresh
pass "front door answers /api/health"
logs=$(compose logs --no-color paperclip 2>&1)
assert_contains "the owner was created at start-up" "is the owner and instance admin" "$logs"
assert_not_contains "the owner password never reaches the logs" "$OWNER_PASSWORD" "$logs"
assert_contains "the signup gate runs in invite-only mode" "signup gate listening on 127.0.0.1:3102 (mode invite-only)" "$logs"

section "only the front door is reachable"
assert_eq "Paperclip's own port is not reachable from the network" "000" \
  "$(compose exec -T db sh -c 'wget -q -T 5 -O /dev/null http://paperclip:3101/api/health 2>/dev/null && echo 200 || echo 000' | tr -d '\r')"
assert_eq "the gate is not reachable from the network" "000" \
  "$(compose exec -T db sh -c 'wget -q -T 5 -O /dev/null http://paperclip:3102/check 2>/dev/null && echo 200 || echo 000' | tr -d '\r')"
port=$(compose exec -T paperclip printenv PORT | tr -d '\r')
assert_eq "the front door is reachable from the network" "200" \
  "$(compose exec -T db sh -c "wget -q -T 5 -O /dev/null http://paperclip:$port/api/health && echo 200 || echo 000" | tr -d '\r')"

section "owner"
if sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD" "$OWNER"; then pass "owner signs in"; else fail "owner sign-in: HTTP $CODE"; fi
req "$OWNER" GET /api/auth/get-session
assert_eq "the session belongs to the owner" "$OWNER_EMAIL" "$(jq -r '.user.email' <<<"$BODY")"
if sign_in "$OWNER_EMAIL" "wrong-password-$(rand)" "$TEST_TMP/bad.jar"; then fail "a wrong password signs in"; else pass "a wrong password is refused ($CODE)"; fi
req "$OWNER" POST /api/companies "$(jq -nc --arg n "Smoke Co $(rand)" '{name:$n}')"
assert_eq "the owner is instance admin (creates a company)" "201" "$CODE"
CID=$(jq -r .id <<<"$BODY")

section "sign-up is invite-only"
body=$(jq -nc --arg e "stranger-$(rand)@example.com" '{name:"Stranger", email:$e, password:"stranger-password-123"}')
req "" POST /api/auth/sign-up/email "$body"
assert_eq "anonymous sign-up is refused" "403" "$CODE"
assert_eq "with a clear error code" "SIGN_UP_INVITE_REQUIRED" "$(jq -r .code <<<"$BODY")"
for p in /API/AUTH/SIGN-UP/EMAIL '/api/auth/sign-up%2Femail' '/api//auth/sign-up/email' '/api/auth/sign-up/email/'; do
  req "" POST "$p" "$body"
  assert_eq "path variant $p is gated" "403" "$CODE"
done
req "" POST /api/auth/./sign-up/email "$body" --path-as-is
assert_eq "dot-segment variant is gated" "403" "$CODE"
req "" POST /api/auth/sign-up/email "$body" -H "Referer: $APP_URL/invite/pcp_invite_$(rand)$(rand)"
assert_eq "a forged Referer with a made-up token is refused" "403" "$CODE"
if sign_in "$(jq -r .email <<<"$body")" stranger-password-123 "$TEST_TMP/s.jar"; then fail "the refused stranger can sign in"; else pass "no stranger account was created"; fi

section "invitations"
req "$OWNER" POST "/api/companies/$CID/invites" '{"allowedJoinTypes":"human"}'
assert_eq "owner creates a human invite" "201" "$CODE"
TOKEN=$(invite_token_from "$BODY")
INVITEE=$TEST_TMP/invitee.jar
INVITEE_EMAIL="invitee-$(rand)@example.com"
sign_up Invitee "$INVITEE_EMAIL" invitee-password-123 "$INVITEE" "$APP_URL/invite/$TOKEN"
assert_eq "the invitee signs up from the invite page" "200" "$CODE"
req "$INVITEE" POST "/api/invites/$TOKEN/accept" '{"requestType":"human"}'
assert_eq "the invitee accepts the invite" "202" "$CODE"
req "$INVITEE" GET "/api/companies/$CID"
assert_eq "the invitee can open the company" "200" "$CODE"
sign_up Reuse "reuse-$(rand)@example.com" reuse-password-1234 "$TEST_TMP/r.jar" "$APP_URL/invite/$TOKEN"
assert_eq "a used invite link cannot sign up anyone else" "403" "$CODE"
req "$INVITEE" POST /api/companies '{"name":"Not allowed"}'
assert_eq "an invited member is not instance admin" "403" "$CODE"

req "$OWNER" POST "/api/companies/$CID/invites" '{"allowedJoinTypes":"human"}'
REVOKED_TOKEN=$(invite_token_from "$BODY"); REVOKED_ID=$(jq -r .id <<<"$BODY")
req "$OWNER" POST "/api/invites/$REVOKED_ID/revoke" '{}'
assert_eq "owner revokes an invite" "200" "$CODE"
sign_up Late "late-$(rand)@example.com" late-password-1234 "$TEST_TMP/l.jar" "$APP_URL/invite/$REVOKED_TOKEN"
assert_eq "a revoked invite cannot sign anyone up" "403" "$CODE"
req "$OWNER" POST "/api/companies/$CID/invites" '{"allowedJoinTypes":"agent"}'
AGENT_TOKEN=$(invite_token_from "$BODY")
sign_up Bot "bot-$(rand)@example.com" bot-password-12345 "$TEST_TMP/b.jar" "$APP_URL/invite/$AGENT_TOKEN"
assert_eq "an agent-only invite cannot sign up a human" "403" "$CODE"

section "attachments on the volume"
req "$OWNER" POST "/api/companies/$CID/issues" '{"title":"Smoke issue"}'
assert_eq "owner creates an issue" "201" "$CODE"
IID=$(jq -r .id <<<"$BODY")
printf 'paperclip-railway smoke %s\n' "$(rand)" >"$TEST_TMP/attachment.txt"
req "$OWNER" POST "/api/companies/$CID/issues/$IID/attachments" "" -F "file=@$TEST_TMP/attachment.txt;type=text/plain"
assert_eq "owner uploads an attachment" "201" "$CODE"
ATT=$(jq -r .id <<<"$BODY")
req "$OWNER" GET "/api/attachments/$ATT/content"
assert_eq "the attachment downloads intact" "$(cat "$TEST_TMP/attachment.txt")" "$BODY"
assert_contains "the file is stored on the /paperclip volume" "/paperclip/instances/default/data/storage/" \
  "$(compose exec -T paperclip sh -c 'find /paperclip/instances/default/data/storage -type f -name "*attachment.txt"')"

section "agent run"
# A process agent that calls back into the Paperclip API with its injected short-lived key, through
# PAPERCLIP_API_URL (the public URL, i.e. the front door): the same loop Claude Code or Codex agents use.
script='curl -fsS -H "Authorization: Bearer $PAPERCLIP_API_KEY" "$PAPERCLIP_API_URL/api/agents/me" | grep -q "\"id\"" && echo agent-probe-ok'
req "$OWNER" POST "/api/companies/$CID/agents" "$(jq -nc --arg s "$script" '{name:"Probe", role:"engineer", adapterType:"process", adapterConfig:{command:"sh", args:["-c",$s], timeoutSec:60}}')"
assert_eq "owner hires a process agent" "201" "$CODE"
AID=$(jq -r .id <<<"$BODY")
req "$OWNER" POST "/api/agents/$AID/heartbeat/invoke" '{}'
assert_eq "owner invokes a heartbeat" "202" "$CODE"
RID=$(jq -r .id <<<"$BODY")
st=""
for _ in $(seq 1 60); do
  req "$OWNER" GET "/api/heartbeat-runs/$RID"; st=$(jq -r .status <<<"$BODY")
  case $st in succeeded|failed|timed_out|cancelled) break ;; esac
  sleep 2
done
assert_eq "the heartbeat run succeeds" "succeeded" "$st"
req "$OWNER" GET "/api/heartbeat-runs/$RID/log"
assert_contains "the agent reached the API with its own key" "agent-probe-ok" "$BODY"
for cli in claude codex opencode gemini; do
  if compose exec -T paperclip gosu node sh -c "command -v $cli" >/dev/null 2>&1; then pass "the $cli CLI is installed for local adapters"; else fail "the $cli CLI is missing"; fi
done

section "restart"
compose restart paperclip >/dev/null 2>&1
wait_for_code "$APP_URL/api/health" 200 || die "Paperclip did not come back after a restart"
assert_contains "the owner bootstrap is skipped once an admin exists" "owner bootstrap skipped" "$(compose logs --no-color --since 5m paperclip 2>&1)"
if sign_in "$OWNER_EMAIL" "$OWNER_PASSWORD" "$OWNER"; then pass "owner signs in after a restart"; else fail "owner sign-in after restart: HTTP $CODE"; fi
req "$OWNER" GET "/api/attachments/$ATT/content"
assert_eq "the attachment survives a restart" "$(cat "$TEST_TMP/attachment.txt")" "$BODY"

section "closed sign-up mode"
PAPERCLIP_TEST_SIGNUP_MODE=closed compose up -d paperclip >/dev/null 2>&1
wait_for_code "$APP_URL/api/health" 200 || die "Paperclip did not come back in closed mode"
req "$OWNER" POST "/api/companies/$CID/invites" '{"allowedJoinTypes":"human"}'
CLOSED_TOKEN=$(invite_token_from "$BODY")
sign_up Closed "closed-$(rand)@example.com" closed-password-123 "$TEST_TMP/c.jar" "$APP_URL/invite/$CLOSED_TOKEN"
assert_eq "closed mode refuses even a live invite" "403" "$CODE"
if sign_in "$INVITEE_EMAIL" invitee-password-123 "$INVITEE"; then pass "existing members still sign in"; else fail "member sign-in in closed mode: HTTP $CODE"; fi
compose up -d paperclip >/dev/null 2>&1
wait_for_code "$APP_URL/api/health" 200 || die "Paperclip did not come back in invite-only mode"

summary
