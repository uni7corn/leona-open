import crypto from "node:crypto";

const DEFAULT_ENDPOINT = "https://leona.xiyanshan.com/v1/verdict";

function requireEnv(name) {
  const value = process.env[name];
  if (!value || value.trim() === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

async function main() {
  const secret = requireEnv("LEONA_SECRET_KEY");
  const boxId = requireEnv("BOX_ID");
  const endpoint = process.env.LEONA_ENDPOINT || DEFAULT_ENDPOINT;

  const body = JSON.stringify({ boxId });
  const timestamp = Date.now().toString();
  const nonce = crypto.randomBytes(16).toString("base64url");
  const bodySha256 = crypto.createHash("sha256").update(body).digest("hex");
  const signingText = `${timestamp}\n${nonce}\n${bodySha256}`;
  const signature = crypto
    .createHmac("sha256", secret)
    .update(signingText)
    .digest("base64url");

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${secret}`,
      "Content-Type": "application/json",
      "X-Leona-Timestamp": timestamp,
      "X-Leona-Nonce": nonce,
      "X-Leona-Signature": signature,
    },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Leona query failed: HTTP ${response.status}\n${text}`);
  }
  console.log(text);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
