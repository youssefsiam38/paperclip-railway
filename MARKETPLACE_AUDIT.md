# Marketplace audit

## Identity

- Template: **Paperclip** (orchestration for teams of AI agents).
- Upstream: [paperclipai/paperclip](https://github.com/paperclipai/paperclip), MIT, very active (stable releases
  every one to two weeks, official multi-arch image on GHCR).
- About 18 other Paperclip templates exist on Railway (checked 2026-09-30). Each leaves one of three doors open:
  a first-visitor admin claim (`/setup` wrapper pages or `private` mode), an invite link in the deploy logs, or open
  sign-up. This one is differentiated by a seeded owner plus an invitation-aware sign-up gate.

## Licence

- Paperclip: MIT (`licenses/PAPERCLIP-LICENSE`); used unmodified from the official image. The image's bundled agent
  CLIs are installed by upstream; their use is governed by each provider's terms.
- RustFS, Caddy: Apache-2.0. PostgreSQL: PostgreSQL License. See `THIRD_PARTY_NOTICES.md`.
- No brand policy found upstream; the icon is Paperclip's app icon from the MIT repository, with a non-affiliation
  notice in the README, overview and notices.

## Security review

- **No first-visitor race.** The owner is created and made instance admin through Paperclip's bootstrap-invite flow
  while Paperclip listens only on loopback; the public port opens afterwards. `public` exposure disables the browser
  claim.
- **Invite-only sign-up that keeps invitations working.** A Caddy `forward_auth` gate admits
  `/api/auth/sign-up*` only from a live, unused, human invite. Path variants (case, `%2F`, `//`, `/./`), forged
  referers, used, revoked and agent-only invites are all refused in the tests.
- **Per-client auth rate limiting** behind Railway's proxy (single-IP `X-Forwarded-For`).
- **Generated secrets**: owner password, Better Auth secret, agent JWT secret, tool-action signing secret, secrets
  master key, PostgreSQL password. None in images or the repository; tests never print them.
- **Private database and object storage**, no public domains; files are served only through Paperclip's API.
- **Disclosed trust boundary**: agents run inside the app container (no nested sandbox on Railway). Documented in
  README, SECURITY and the overview.

## Tests

- `tests/static.sh` (42): syntax, shellcheck, compose shape, digest pins, bind addresses, start-up order, gate
  coverage, secret scan.
- `tests/smoke.sh` (49): front door, loopback-only internals, owner bootstrap, bucket creation, sign-up gate and
  bypass attempts, invitation flow, instance-admin powers, attachments stored in RustFS (not on the app volume), a `process` agent calling the API with its
  injected key, the bundled agent CLIs, restart idempotency, `closed` mode.
- `tests/persistence.sh` (6): company, attachment and owner survive recreating every service.
- `tests/railway-smoke.sh` (24, `--verify` 8): the same flows over HTTPS. Run on a clean-room deploy of the template, again after redeploying all three services, and on a deploy of the published code (2026-10-01).

Not covered: an LLM-backed agent (Claude Code, Codex) against a real provider; the UI was checked in a browser only
as far as the sign-in page (no password typing by the tester).

## Verdict

Shippable. Self-contained (Paperclip + PostgreSQL + RustFS), reproducible (digest-pinned), owner seeded, invite-only.
