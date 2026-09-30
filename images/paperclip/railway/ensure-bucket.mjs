// Makes sure the S3 bucket for Paperclip's uploads exists before Paperclip starts (Paperclip does not create it).
// Runs only when PAPERCLIP_STORAGE_PROVIDER=s3. Waits for the storage service, which may still be starting on the
// first deploy, then creates the bucket if it is missing. Credentials come from AWS_ACCESS_KEY_ID /
// AWS_SECRET_ACCESS_KEY, exactly as Paperclip's own S3 client reads them. Never prints them.
import { createRequire } from "node:module";

const require = createRequire("/app/server/package.json");
const { S3Client, HeadBucketCommand, CreateBucketCommand } = require("@aws-sdk/client-s3");

const log = (msg) => process.stderr.write(`paperclip-railway: ${msg}\n`);
const bucket = (process.env.PAPERCLIP_STORAGE_S3_BUCKET || "paperclip").trim();
const endpoint = process.env.PAPERCLIP_STORAGE_S3_ENDPOINT || undefined;
const timeoutSec = Number(process.env.PAPERCLIP_STORAGE_WAIT_SEC || "600");

const client = new S3Client({
  region: process.env.PAPERCLIP_STORAGE_S3_REGION || "us-east-1",
  endpoint,
  forcePathStyle: process.env.PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE === "true",
});

const started = Date.now();
let lastError = "";
for (;;) {
  try {
    await client.send(new HeadBucketCommand({ Bucket: bucket }));
    log(`storage bucket "${bucket}" is ready`);
    process.exit(0);
  } catch (err) {
    const status = err?.$metadata?.httpStatusCode;
    if (status === 404 || err?.name === "NotFound" || err?.name === "NoSuchBucket") {
      try {
        await client.send(new CreateBucketCommand({ Bucket: bucket }));
        log(`created storage bucket "${bucket}"`);
        process.exit(0);
      } catch (createErr) {
        lastError = `create failed: ${createErr?.name ?? "error"} (HTTP ${createErr?.$metadata?.httpStatusCode ?? "?"})`;
      }
    } else if (status === 403) {
      log(`storage refused the credentials for bucket "${bucket}" (HTTP 403); check AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY`);
      process.exit(1);
    } else {
      lastError = `${err?.name ?? "error"}${status ? ` (HTTP ${status})` : ""}: ${err?.code ?? err?.message ?? ""}`.slice(0, 200);
    }
  }
  if ((Date.now() - started) / 1000 >= timeoutSec) {
    log(`storage at ${endpoint ?? "AWS"} not ready after ${timeoutSec}s (${lastError})`);
    process.exit(1);
  }
  await new Promise((r) => setTimeout(r, 3000));
}
