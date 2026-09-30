// Caddy forward_auth target for every request to /api/auth/sign-up*.
//
// Paperclip's only switch (PAPERCLIP_AUTH_DISABLE_SIGN_UP) turns Better Auth sign-up off for everyone, which also
// breaks its invitation links: an invitee creates their account from the /invite/<token> page. This gate keeps
// sign-up open only for those pages, according to PAPERCLIP_SIGNUP_MODE:
//   invite-only (default)  allowed when the Referer is /invite/<token> and Paperclip reports that invite as live
//                          (not revoked, expired or already used by a join request) and open to humans
//   closed                 always refused; the owner is still seeded, nobody else can create an account
//   open                   always allowed (Paperclip's upstream behaviour)
// Forging a Referer gains nothing: it still has to name a live invite token, which is the secret.
import http from "node:http";

const mode = process.env.PAPERCLIP_SIGNUP_MODE || "invite-only";
const port = Number(process.env.PAPERCLIP_GATE_PORT || "3102");
const internal = `http://127.0.0.1:${process.env.PAPERCLIP_INTERNAL_PORT || "3101"}`;
const publicHost = new URL(process.env.PAPERCLIP_PUBLIC_URL).host;
const TOKEN_RE = /^\/invite\/([A-Za-z0-9_-]{8,200})\/?$/;

function refuse(res, message) {
  const body = JSON.stringify({ code: "SIGN_UP_INVITE_REQUIRED", message });
  res.writeHead(403, { "content-type": "application/json", "content-length": Buffer.byteLength(body) });
  res.end(body);
}

function allow(res) {
  res.writeHead(204);
  res.end();
}

async function liveHumanInvite(token) {
  const res = await fetch(`${internal}/api/invites/${encodeURIComponent(token)}`, {
    headers: { host: publicHost, accept: "application/json" },
    signal: AbortSignal.timeout(5000),
  });
  if (res.status !== 200) return false;
  const invite = await res.json().catch(() => null);
  if (!invite || typeof invite !== "object") return false;
  // Paperclip keeps answering 200 for an invite after it is accepted (so the invitee can see their join status);
  // a join request on it means the link is used up.
  if (invite.joinRequestStatus != null || invite.joinRequestType != null) return false;
  const joinTypes = invite.allowedJoinTypes;
  return joinTypes === "human" || joinTypes === "both";
}

const server = http.createServer(async (req, res) => {
  try {
    if (mode === "open") return allow(res);
    if (mode === "closed") return refuse(res, "Sign-up is disabled on this Paperclip instance.");
    let token = null;
    try {
      const referer = new URL(req.headers.referer || "");
      token = TOKEN_RE.exec(referer.pathname)?.[1] ?? null;
    } catch { /* missing or malformed Referer */ }
    if (token && (await liveHumanInvite(token))) return allow(res);
    return refuse(res, "Sign-up needs an invitation. Ask an admin of this Paperclip instance for an invite link.");
  } catch {
    return refuse(res, "Sign-up is temporarily unavailable.");
  }
});

server.listen(port, "127.0.0.1", () => {
  process.stderr.write(`paperclip-railway: signup gate listening on 127.0.0.1:${port} (mode ${mode})\n`);
});
