# Upstream and pinned versions

## Paperclip

- Project: https://github.com/paperclipai/paperclip
- Licence: MIT (`licenses/PAPERCLIP-LICENSE`)
- Official image: `ghcr.io/paperclipai/paperclip` (multi-arch; ~7 GB unpacked, includes the Claude Code, Codex,
  OpenCode, Gemini and Kimi CLIs)
- Pinned: `ghcr.io/paperclipai/paperclip:2026.916.1` (release `v2026.916.1`, commit `d554c4789ed3930f8a53ac9fdf6503b3187097da`)
  - digest `sha256:a02ac35ac41df911af477422ea0e781cf41d2b2c600c66f0a5ac9d8c63f52c2c`
  - schema: 278 migrations, last `0279_tired_deathstrike.sql` (image labels)
- Used unmodified. The wrapper replaces only the entrypoint/command with `images/paperclip/railway/` and keeps
  upstream's `tini` and `docker-entrypoint.sh`.

### Upstream contracts the wrapper depends on

Check these on every bump (the smoke test exercises all of them):

| Contract | Where upstream |
|---|---|
| `instance_user_roles(role='instance_admin')` marks the admin | `packages/db/src/schema/instance_user_roles.ts` |
| `invites` columns and the `bootstrap_ceo` sha256 token hash | `cli/src/commands/auth-bootstrap-ceo.ts` |
| `POST /api/invites/:token/accept {requestType:"human"}` claims the instance for a bootstrap invite | `server/src/routes/access.ts` |
| `GET /api/invites/:token` → 404 unless live; `joinRequestStatus` non-null once used; `allowedJoinTypes` | `server/src/routes/access.ts` |
| Better Auth mounted at `/api/auth/*`, email sign-up at `/api/auth/sign-up/email` | `server/src/app.ts`, `ui/src/api/auth.ts` |
| The invite page signs up from `/invite/<token>` without disabling `Referer` | `ui/src/pages/InviteLanding.tsx` |
| `TRUST_PROXY`, `PAPERCLIP_BIND`, `HOST`, `PORT`, `PAPERCLIP_MIGRATION_AUTO_APPLY` | `server/src/config.ts`, `server/src/index.ts` |
| Server command `node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js` in `/app` | `Dockerfile` |
| `postgres` npm package resolvable from `/app/packages/db` | `packages/db/package.json` |

## Caddy

- Image: `caddy:2.10.2` (official), binary copied into the wrapper
  - digest `sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb`
- Licence: Apache-2.0

## PostgreSQL

- Pinned: `postgres:18.2-alpine3.23`
  - digest `sha256:035b9ab53cfa147d7202b61f5f7782b939ae815b7d6bc81c96b7b42ff1fca950`

## Refreshing a digest

```bash
git ls-remote --tags https://github.com/paperclipai/paperclip.git | grep -E 'refs/tags/v[0-9.]+$' | sort -V -k2 | tail -3
docker buildx imagetools inspect ghcr.io/paperclipai/paperclip:<version> --format '{{json .Manifest}}' | jq -r .digest
```

Stable releases publish `:<version>` (e.g. `2026.916.1`) and move `:latest`; `beta`/`nightly` are separate lanes.
