# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Paperclip AI Teams |
| Code | `paperclip-ai-teams` (`paperclip` is taken; the code is the slug of the name, which comes from the skeleton project name) |
| Template id | `ca295d6a-a952-40a8-a05a-79e0c4e706d0` |
| Deploy URL | https://railway.com/deploy/paperclip-ai-teams |
| Category | AI/ML |
| Card description | Run AI agent teams (Claude Code, Codex). Owner seeded, invite-only sign-up. |
| Icon | `assets/icon.png` via `https://raw.githubusercontent.com/youssefsiam38/paperclip-railway/v1.1.0/assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings; no angle-bracket placeholders) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL. Images are referenced by tag because the template generator rejects digests; `UPSTREAM.md` and the
GHCR packages record the digests.

## Services

### `db`

| Field | Value |
|---|---|
| Source | `postgres:18.2-alpine3.23` |
| Public domain | none |
| Volume | `/var/lib/postgresql` (the parent of PGDATA; Railway volumes carry `lost+found`) |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `POSTGRES_USER` | `paperclip` |
| `POSTGRES_DB` | `paperclip` |
| `POSTGRES_PASSWORD` | generated, alnum48 |

### `storage`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/paperclip-railway-storage:1.2.0` |
| Public domain | none |
| Volume | `/data` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `9000` |
| `RUSTFS_ACCESS_KEY` | generated, alnum20 |
| `RUSTFS_SECRET_KEY` | generated, alnum48 |

### `paperclip`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/paperclip-railway:1.2.0` |
| Public domain | target port 3100 (Caddy) |
| Volume | `/paperclip` |
| Healthcheck | `/api/health`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `ADMIN_EMAIL` | required input |
| `ADMIN_PASSWORD` | generated, alnum24 |
| `ADMIN_NAME` | `Owner` |
| `PAPERCLIP_SIGNUP_MODE` | `invite-only` |
| `DATABASE_URL` | `postgres://paperclip:${{db.POSTGRES_PASSWORD}}@${{db.RAILWAY_PRIVATE_DOMAIN}}:5432/paperclip` |
| `PAPERCLIP_PUBLIC_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` |
| `BETTER_AUTH_SECRET` | generated, hex64 |
| `PAPERCLIP_AGENT_JWT_SECRET` | generated, hex64 |
| `PAPERCLIP_TOOL_ACTION_SIGNING_SECRET` | generated, hex64 |
| `PAPERCLIP_SECRETS_MASTER_KEY` | generated, hex64 |
| `PAPERCLIP_STORAGE_PROVIDER` | `s3` |
| `PAPERCLIP_STORAGE_S3_ENDPOINT` | `http://${{storage.RAILWAY_PRIVATE_DOMAIN}}:9000` |
| `PAPERCLIP_STORAGE_S3_BUCKET` | `paperclip` |
| `PAPERCLIP_STORAGE_S3_REGION` | `us-east-1` |
| `PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE` | `true` |
| `AWS_ACCESS_KEY_ID` | `${{storage.RUSTFS_ACCESS_KEY}}` |
| `AWS_SECRET_ACCESS_KEY` | `${{storage.RUSTFS_SECRET_KEY}}` |
| `PORT` | `3100` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `900` |
| `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, `GEMINI_API_KEY` | optional, unset |

## Notes

- `PORT` is Caddy's port and the domain target. Paperclip itself listens on `127.0.0.1:3101`.
- No `RAILWAY_RUN_UID`: the image starts as root and upstream's entrypoint chowns `/paperclip`, then drops to `node`.
- Deployment mode, exposure, migration auto-apply, trust-proxy and the internal ports are baked into the image as
  `ENV` defaults, so they are not template inputs.
