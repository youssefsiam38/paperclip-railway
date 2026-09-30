# Third-party notices

This template packages and runs the following third-party software. Each keeps its own licence; the template's own
files are MIT (see `LICENSE`).

## Paperclip

- Source: https://github.com/paperclipai/paperclip
- Licence: MIT, full text in `licenses/PAPERCLIP-LICENSE`
- Used unmodified from the official image `ghcr.io/paperclipai/paperclip` (pinned in `UPSTREAM.md`). The image also
  contains third-party agent CLIs installed by upstream (Claude Code, Codex, OpenCode, Gemini CLI, Kimi Code), each
  under its own terms; their use with a provider account is governed by that provider's terms.
- `assets/icon.png` is Paperclip's app icon from the upstream repository (`ui/public/android-chrome-512x512.png`).

## RustFS

- Source: https://github.com/rustfs/rustfs, licence Apache-2.0 (`licenses/RUSTFS-LICENSE`). The official image is
  used unmodified; the wrapper adds `su-exec` and a start-up script that prepares the volume.

## Caddy

- Source: https://github.com/caddyserver/caddy, licence Apache-2.0. The official binary is copied unmodified.

## PostgreSQL

- Source: https://www.postgresql.org, official Docker image `postgres`, PostgreSQL License.

---

"Paperclip" is the name of its project. This template is community-maintained and is not affiliated with, or
endorsed by, the Paperclip project.
