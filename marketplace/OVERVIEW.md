# Deploy and Host Paperclip on Railway

Paperclip is the open-source app for running a company of AI agents: hire Claude Code, Codex, OpenCode or Gemini
agents into an org chart, give them goals and budgets, approve their work and audit every run from one board. This
template deploys it ready for the internet: you are the owner from the first second, and nobody can create an
account without your invitation. It is a community-maintained template and is not affiliated with the Paperclip
project.

## About Hosting Paperclip

Paperclip is a Node.js server with a bundled web UI, backed by PostgreSQL. It runs agents as processes inside its
own container, using the agent CLIs that ship in its official image, and keeps uploads, agent workspaces and run
logs on disk.

A stock Paperclip on a public URL has two problems: someone has to become the first admin (either whoever signs up
first, or an operator running a CLI command and copying an invite from the logs), and anyone who finds the URL can
create an account. Paperclip's only switch against the second problem also breaks its invitation links.

This template creates your owner account from the email you enter and a generated password, and makes it the
instance admin before the app answers on its URL. Sign-up is then allowed only from a live invitation link, so
inviting teammates keeps working while walk-up sign-up is refused. Everything else runs from the official
Paperclip image, pinned by digest and unmodified.

## Common Use Cases

- Keep a team of AI agents working on scheduled heartbeats around the clock, not only while your laptop is open
- Put Claude Code and Codex agents on real tickets with per-agent budgets that stop runaway spend
- Give your team one shared board to assign work to agents, approve actions and review every run
- Run several AI "companies" side by side, each with its own goals, org chart and costs

## Dependencies for Paperclip Hosting

- PostgreSQL: included, on Railway's private network
- RustFS (S3-compatible object storage) for uploads: included, private
- An AI provider credential for your agents (optional at deploy time): an Anthropic key or Claude subscription
  token, an OpenAI key, or a Gemini key. You can also add keys later, per agent, inside Paperclip.

### Deployment Dependencies

- Paperclip (MIT): https://github.com/paperclipai/paperclip
- Paperclip documentation: https://docs.paperclip.ing
- Template source, image and tests: https://github.com/youssefsiam38/paperclip-railway

### Implementation Details

**First sign-in:** after the deploy turns green, open the `paperclip` service's Variables, copy `ADMIN_PASSWORD`,
and sign in at the service's domain with the email you entered as `ADMIN_EMAIL`. Change the password in Paperclip's
profile if you like; the variable is only the initial password.

**Inviting teammates:** in Paperclip, create a human invite and send the link. The invitee creates an account on
that page. `PAPERCLIP_SIGNUP_MODE` can also be `closed` (nobody else can create an account) or `open` (upstream
behaviour).

**What's configured for you:** `authenticated` + `public` mode, the public URL from your Railway domain, four
generated signing and encryption secrets, database migrations on every start, per-client sign-in rate limiting
behind Railway's proxy, a private RustFS bucket for uploads, a volume at `/paperclip` for agent workspaces and
logs, and a private PostgreSQL. Paperclip
listens on loopback behind a small Caddy front door that only adds the sign-up check.

**Agents:** agents run inside the Paperclip container. Railway has no nested containers, so there is no per-agent
sandbox, and Paperclip passes its server environment on to agents; treat the ability to run agents like shell
access to the service.

**Custom domain:** add it in Railway, then set `PAPERCLIP_PUBLIC_URL` to `https://your.domain`.

Tested on a live deployment of this template: owner sign-in, refused walk-up sign-up, the full invitation flow,
file uploads, an agent run calling back into Paperclip, and a redeploy keeping everything.

## Why Deploy Paperclip on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you
don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Paperclip on Railway, you are one step closer to supporting a complete full-stack application with
minimal burden. Host your servers, databases, AI agents, and more on Railway.
