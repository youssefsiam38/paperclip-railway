# Security

## What the template closes

| Upstream behaviour on a public URL | This template |
|---|---|
| Fresh `authenticated` instance: the first person to sign up can claim it (`private` mode), or the owner has to run a CLI command in the container and copy an invite from the logs (`public` mode). | The owner is created from `ADMIN_EMAIL` / generated `ADMIN_PASSWORD` and made instance admin through Paperclip's own bootstrap-invite flow **before** the public port opens. Browser claiming is disabled (`public` exposure). |
| Better Auth sign-up is open to anyone. `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` closes it, but also breaks invitation links (invitees sign up on the invite page). | A Caddy `forward_auth` gate allows `POST /api/auth/sign-up*` only when the request comes from `/invite/<token>` and Paperclip reports that invite as live, unused and open to humans. `closed` and `open` modes are available. |
| Better Auth trusts only the origin of the public URL read at start; after a Railway domain rename (no redeploy) every sign-in fails with "Invalid origin". | Caddy presents a request whose `Origin` equals its own `Host` (same-origin by definition; Railway only routes the service's own domains) as the configured origin. Cross-site origins are untouched and still refused. |
| Behind Railway's proxy, Better Auth sees no usable client IP and rate-limits every visitor from one shared bucket, so one client can lock everyone out of sign-in. | Caddy forwards a single resolved client IP (`X-Forwarded-For`), so rate limits are per client. |

## Trust boundaries

- **Only Caddy listens on the network.** Paperclip binds `127.0.0.1:3101` and the sign-up gate `127.0.0.1:3102`.
- **PostgreSQL and RustFS** have no public domain; they are reachable only over Railway's private network. Files
  are streamed to browsers through Paperclip's authenticated API, never from the bucket directly.
- **Agents run inside the `paperclip` container** as the `node` user, with the same filesystem, network and
  environment access as the server. Paperclip hands agent processes its own environment minus `PAPERCLIP_*`
  variables, so agents can read `DATABASE_URL`, `BETTER_AUTH_SECRET`, the storage keys and your provider keys
  (the template keeps `ADMIN_*` out of it). Railway provides no nested sandbox.
  Anyone who can make an agent run arbitrary commands (an admin, or someone with agent-management permissions in a
  company) effectively has a shell on the service. Grant those permissions accordingly. For isolation, use one of
  Paperclip's remote sandbox providers (external services, not configured here).
- **Secrets** are generated per deploy by Railway. `PAPERCLIP_SECRETS_MASTER_KEY` encrypts company secrets at rest
  in PostgreSQL; losing or changing it makes them unreadable.

## Limits of the sign-up gate

- The gate relies on the browser's `Referer` on the invite page. Browsers send it for same-origin requests by
  default and Paperclip does not disable it. A forged `Referer` gains nothing: it still has to name a live invite
  token, which is the secret.
- An invite link is usable by whoever holds it until it is accepted, revoked or expires (Paperclip's own semantics).
  Send links privately; revoke unused ones.
- Accounts that existed before the template (e.g. after switching `PAPERCLIP_SIGNUP_MODE` from `open`) are kept.

## Reporting

Template issues: open an issue on https://github.com/youssefsiam38/paperclip-railway. Paperclip vulnerabilities:
follow https://github.com/paperclipai/paperclip/blob/master/SECURITY.md.
