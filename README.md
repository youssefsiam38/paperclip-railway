# Paperclip on Railway

A one-click Railway template for [Paperclip](https://github.com/paperclipai/paperclip), the open-source app for
running a company of AI agents (Claude Code, Codex, OpenCode, Gemini and more) with org charts, goals, budgets and
approvals. It is a community-maintained template and is not affiliated with the Paperclip project.

What makes this template different from a bare `docker run`:

- **You are the owner from the first second.** The owner account is created from `ADMIN_EMAIL` and a generated
  `ADMIN_PASSWORD` and made instance admin *before* the app answers on its public URL. No setup page to race, no
  invite link to fish out of the logs.
- **Sign-up is invite-only.** Stock Paperclip lets anyone who finds the URL create an account. Here a new account
  can only be created from a live invitation link that an admin generated; invites still work normally.
- **Internet-facing configuration.** `authenticated` + `public` mode, HTTPS public URL, four generated secrets,
  per-client auth rate limiting behind Railway's proxy, PostgreSQL on the private network.
- **Uploads in bundled object storage.** Attachments and files go to a private RustFS (S3-compatible) service with
  its own volume; agent workspaces, run logs and database backups stay on the app's volume.
- **Official image, unmodified.** `ghcr.io/paperclipai/paperclip`, pinned by digest. The wrapper only adds a
  start-up script and a Caddy front door.

## Services

| Service | Image | Public | Volume |
|---|---|---|---|
| `paperclip` | `ghcr.io/youssefsiam38/paperclip-railway` (official Paperclip + Caddy) | yes, port 3100 | `/paperclip` |
| `storage` | `ghcr.io/youssefsiam38/paperclip-railway-storage` (official RustFS, volume-ready) | no | `/data` |
| `db` | `postgres:18.2-alpine3.23` | no | `/var/lib/postgresql` |

## After deploying

1. Open the `paperclip` service's **Variables**, copy `ADMIN_PASSWORD`.
2. Open the service's domain and sign in with `ADMIN_EMAIL` and that password. Change the password in Paperclip's
   profile settings if you like; the variable is only the initial password.
3. Create your company, hire agents and give them work.

To let agents run, add a provider key to the `paperclip` service: `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`
(Claude Code), `OPENAI_API_KEY` (Codex), `GEMINI_API_KEY` (Gemini CLI). Keys can also be stored per agent inside
Paperclip as company secrets.

To add teammates: **Company settings → Invites**, create a human invite and send the link. The invitee creates
their account on that page.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_EMAIL` | *required input* | The owner's email. Used to sign in. |
| `ADMIN_PASSWORD` | generated | Initial owner password. Only used when no instance admin exists yet. |
| `ADMIN_NAME` | `Owner` | Display name of the owner account. |
| `PAPERCLIP_SIGNUP_MODE` | `invite-only` | `invite-only`, `closed` (nobody else can create an account) or `open` (upstream behaviour). |
| `PAPERCLIP_PUBLIC_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` | Change it when you add a custom domain. |
| `BETTER_AUTH_SECRET`, `PAPERCLIP_AGENT_JWT_SECRET`, `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` | generated | Changing them signs everyone out / invalidates agent tokens. |
| `PAPERCLIP_SECRETS_MASTER_KEY` | generated | Encrypts stored secrets. **Never change it** after secrets are saved. |
| `PAPERCLIP_STORAGE_*`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | wired to `storage` | S3 settings for the bundled RustFS (bucket `paperclip`, created at start). |
| `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY` (on `storage`) | generated | RustFS credentials; the app reads them by reference. |
| `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY` | unset | Optional agent credentials. |

## How agents run

Paperclip runs local agents (Claude Code, Codex, OpenCode, Gemini CLI, shell commands) as processes **inside the
`paperclip` container**, with workspaces on the `/paperclip` volume. Railway has no nested containers, so there is
no per-agent sandbox: an agent can do anything the container can, and Paperclip passes its server environment
(database URL, auth secrets, storage keys, provider keys) on to agent processes. Treat agent access like shell
access to the service. Paperclip's remote sandbox plugins (Daytona, E2B, Modal, ...) are optional external services and are not
configured by this template. See `SECURITY.md`.

## Repository layout

| Path | What |
|---|---|
| `images/paperclip/` | The wrapper image: Dockerfile, start-up scripts, sign-up gate, Caddyfile |
| `compose.yaml` | Local stack mirroring the Railway services |
| `tests/` | `static.sh`, `smoke.sh`, `persistence.sh`, `railway-smoke.sh` (live) |
| `marketplace/OVERVIEW.md` | The template's marketplace page |
| `RAILWAY_TEMPLATE.md` | The template's exact configuration |

## Local run

```bash
docker compose build
tests/static.sh && tests/smoke.sh && tests/persistence.sh
```

The local stack answers at `http://paperclip.test:18100` (the tests resolve that name to 127.0.0.1 themselves;
add it to `/etc/hosts` to use a browser). Owner: `owner@example.com` / `local-test-only-admin-password`.

## Licence

The template's own files are MIT (`LICENSE`). Paperclip is MIT (`licenses/PAPERCLIP-LICENSE`), RustFS is
Apache-2.0 (`licenses/RUSTFS-LICENSE`); see
`THIRD_PARTY_NOTICES.md`.
