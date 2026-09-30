# Maintenance

## Releasing a new version

1. **Bump the pins** (see `UPSTREAM.md`): `ARG PAPERCLIP_IMAGE` in `images/paperclip/Dockerfile`, `UPSTREAM.md`.
   Re-read the "upstream contracts" table against the new release's diff (`server/src/routes/access.ts`,
   `server/src/config.ts`, `cli/src/commands/auth-bootstrap-ceo.ts`).
2. **Run the tests locally.**
   ```bash
   docker compose build
   tests/static.sh && tests/smoke.sh && tests/persistence.sh
   ```
3. **Tag and push.** `git tag vX.Y.Z && git push --tags`. The `publish-image` workflow re-runs the tests against
   the candidate and pushes `:X.Y.Z`, `:X.Y` and `:latest` to GHCR.
4. **Update the template** image tag (see `RAILWAY_TEMPLATE.md`), deploy it into a scratch project and run
   `tests/railway-smoke.sh` against it before announcing.

Paperclip ships stable releases roughly every one to two weeks and applies its migrations on start, so a bump is a
redeploy; there is no manual migration step.

## Rebuilding the Railway template

The exact configuration is in `RAILWAY_TEMPLATE.md`; the generator spec is `_audit/spec_paperclip.py` in the
workspace, used with `_audit/tplkit.py`. Volumes, domains and health checks are only set by the skeleton step.

## Gotchas

- **`PORT` is the front door.** Railway routes the edge and the health check to `PORT` (3100, Caddy). Paperclip's
  own port is `PAPERCLIP_INTERNAL_PORT` (3101, loopback). Don't point the domain at 3101.
- **The first boot is slow.** ~280 migrations plus a 7 GB image pull; the health check timeout is 900 s.
- **Loopback public URLs are rewritten.** Paperclip replaces the port of a `localhost` public URL with its listen
  port, which breaks auth origins behind a proxy. The local stack uses `paperclip.test`; Railway domains are fine.
- **Better Auth rate limiting needs a single-IP `X-Forwarded-For`.** Keep `header_up X-Forwarded-For {client_ip}`
  in the Caddyfile.
- **`ADMIN_PASSWORD` is only the initial password.** Once an instance admin exists, the bootstrap does nothing.
