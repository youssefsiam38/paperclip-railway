// Seeds the owner account and makes it Paperclip's instance admin, before the instance is reachable from outside.
//
// It follows Paperclip's own bootstrap path end to end instead of writing auth rows by hand:
//   1. sign up ADMIN_EMAIL / ADMIN_PASSWORD through Better Auth (or sign in, if that account already exists)
//   2. mint a one-time `bootstrap_ceo` invite (what `paperclipai auth bootstrap-ceo` does: sha256 token hash)
//   3. accept it as that user through POST /api/invites/:token/accept, which runs claimFirstInstanceAdmin
// Runs on every start and does nothing once an instance admin exists, so ADMIN_PASSWORD is the initial password
// only; change it in Paperclip afterwards. Never prints the password or the invite token.
import { createHash, randomBytes } from "node:crypto";
import { createRequire } from "node:module";

const require = createRequire("/app/packages/db/package.json");
const postgres = require("postgres");

const log = (msg) => process.stderr.write(`paperclip-railway: ${msg}\n`);

const internal = `http://127.0.0.1:${process.env.PAPERCLIP_INTERNAL_PORT || "3101"}`;
const publicUrl = new URL(process.env.PAPERCLIP_PUBLIC_URL);
const email = process.env.ADMIN_EMAIL.trim().toLowerCase();
const password = process.env.ADMIN_PASSWORD;
const name = (process.env.ADMIN_NAME || "").trim() || "Owner";

// Requests go straight to the loopback server but carry the public identity, exactly as they would behind Caddy.
const baseHeaders = {
  host: publicUrl.host,
  origin: publicUrl.origin,
  "x-forwarded-proto": publicUrl.protocol.replace(":", ""),
  "x-forwarded-host": publicUrl.host,
  "x-forwarded-for": "127.0.0.1",
  "content-type": "application/json",
  accept: "application/json",
};

async function call(path, body, cookie) {
  const res = await fetch(`${internal}${path}`, {
    method: "POST",
    headers: cookie ? { ...baseHeaders, cookie } : baseHeaders,
    body: JSON.stringify(body),
    redirect: "manual",
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  const cookies = res.headers.getSetCookie().map((c) => c.split(";")[0]).join("; ");
  return { status: res.status, json, cookies };
}

const sql = postgres(process.env.DATABASE_URL, { max: 1, onnotice: () => {} });
try {
  const [{ n }] = await sql`select count(*)::int as n from instance_user_roles where role = 'instance_admin'`;
  if (n > 0) {
    log("an instance admin already exists; owner bootstrap skipped");
    process.exit(0);
  }

  let session;
  const signUp = await call("/api/auth/sign-up/email", { name, email, password });
  if (signUp.status === 200 && signUp.cookies) {
    session = signUp.cookies;
    log(`created the owner account ${email}`);
  } else {
    // The account can already exist if an earlier start stopped between sign-up and the claim.
    const signIn = await call("/api/auth/sign-in/email", { email, password });
    if (signIn.status !== 200 || !signIn.cookies) {
      log(`could not create the owner account (sign-up HTTP ${signUp.status}: ${signUp.json?.message ?? signUp.json?.code ?? "no detail"})`);
      log("if an account with ADMIN_EMAIL already exists, ADMIN_PASSWORD must be its current password");
      process.exit(1);
    }
    session = signIn.cookies;
    log(`signed in to the existing account ${email}`);
  }

  const token = `pcp_bootstrap_${randomBytes(24).toString("hex")}`;
  const tokenHash = createHash("sha256").update(token).digest("hex");
  await sql`
    update invites set revoked_at = now(), updated_at = now()
    where invite_type = 'bootstrap_ceo' and revoked_at is null and accepted_at is null and expires_at > now()`;
  await sql`
    insert into invites (invite_type, token_hash, allowed_join_types, expires_at, invited_by_user_id)
    values ('bootstrap_ceo', ${tokenHash}, 'human', now() + interval '10 minutes', 'system')`;

  const accept = await call(`/api/invites/${token}/accept`, { requestType: "human" }, session);
  if (accept.status !== 202 || accept.json?.bootstrapAccepted !== true) {
    await sql`update invites set revoked_at = now(), updated_at = now() where token_hash = ${tokenHash} and accepted_at is null`;
    log(`claiming the instance failed (HTTP ${accept.status}: ${accept.json?.error ?? accept.json?.message ?? "no detail"})`);
    process.exit(1);
  }

  const [{ admins }] = await sql`select count(*)::int as admins from instance_user_roles where role = 'instance_admin'`;
  if (admins < 1) {
    log("the claim returned success but no instance admin is recorded");
    process.exit(1);
  }
  log(`${email} is the owner and instance admin`);
} finally {
  await sql.end({ timeout: 5 }).catch(() => {});
}
