# Architecture

```
Railway edge (HTTPS)
      │  $PORT = 3100
      ▼
┌──────────────────────── paperclip container (tini → start.sh → gosu node → supervisor.sh) ────────────────────────┐
│  Caddy :3100 ── /api/auth/sign-up* ── forward_auth ──► signup-gate.mjs 127.0.0.1:3102 ──► GET /api/invites/:token │
│     │                                                                                                              │
│     └──────────── everything else (HTTP, WebSocket, SSE) ──► Paperclip 127.0.0.1:3101 (official server + UI)       │
│                                                             │  agent processes (claude, codex, opencode, gemini,   │
│                                                             │  shell) with workspaces on /paperclip                │
└─────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────┘
                                                              ▼  private network
                                                        db: PostgreSQL 18
```

## Start-up order

1. `start.sh` (root) validates the inputs and runs upstream's `docker-entrypoint.sh`, which fixes ownership of the
   `/paperclip` volume and drops to `node`.
2. `supervisor.sh` starts Paperclip on loopback with `PAPERCLIP_MIGRATION_AUTO_APPLY=true` and waits for
   `/api/health`. The first start applies ~280 migrations.
3. `bootstrap-owner.mjs` runs if no instance admin exists: Better Auth sign-up (or sign-in, if a previous start
   created the account), a one-time `bootstrap_ceo` invite written exactly like `paperclipai auth bootstrap-ceo`,
   and `POST /api/invites/:token/accept`, which calls Paperclip's `claimFirstInstanceAdmin`.
4. Only then do the sign-up gate and Caddy start. Railway's health check (`/api/health` through Caddy) turns green.
5. If any of the three processes exits, the supervisor stops the others and exits; Railway restarts the container.

## Why a front door at all

Paperclip has no setting that keeps invitation sign-up working while refusing walk-up sign-up, and none that tells
Better Auth which proxy header to trust. Both need a layer in front of it; Caddy handles WebSockets and streaming
without configuration, and the gate is ~60 lines that only ask Paperclip's own public invite endpoint.

## Why agents call the public URL

Paperclip derives `PAPERCLIP_API_URL` (injected into agent processes) from `PAPERCLIP_PUBLIC_URL`. Agents therefore
reach the API through Railway's edge and Caddy. That keeps remote agents and invite onboarding text correct; the
local test stack mirrors it by resolving `paperclip.test` to the container's own loopback.
