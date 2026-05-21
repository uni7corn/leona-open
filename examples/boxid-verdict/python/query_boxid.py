#!/usr/bin/env python3
import base64
import hashlib
import hmac
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request


DEFAULT_ENDPOINT = "https://leona.xiyanshan.com/v1/verdict"


def base64url_no_padding(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def build_signed_request(secret: str, box_id: str, endpoint: str, timestamp: str, nonce: str) -> dict:
    body = json.dumps({"boxId": box_id}, separators=(",", ":")).encode("utf-8")
    body_sha256 = hashlib.sha256(body).hexdigest()
    signing_text = f"{timestamp}\n{nonce}\n{body_sha256}".encode("utf-8")
    signature = base64url_no_padding(
        hmac.new(secret.encode("utf-8"), signing_text, hashlib.sha256).digest()
    )
    return {
        "endpoint": endpoint,
        "body": body.decode("utf-8"),
        "bodySha256": body_sha256,
        "headers": {
            "Authorization": f"Bearer {secret}",
            "Content-Type": "application/json",
            "X-Leona-Timestamp": timestamp,
            "X-Leona-Nonce": nonce,
            "X-Leona-Signature": signature,
        },
    }


def main() -> int:
    secret = require_env("LEONA_SECRET_KEY")
    box_id = require_env("BOX_ID")
    endpoint = os.environ.get("LEONA_ENDPOINT", DEFAULT_ENDPOINT)

    timestamp = os.environ.get("LEONA_TIMESTAMP", str(int(time.time() * 1000)))
    nonce = os.environ.get("LEONA_NONCE", base64url_no_padding(secrets.token_bytes(16)))
    signed = build_signed_request(secret, box_id, endpoint, timestamp, nonce)

    if os.environ.get("LEONA_DRY_RUN") == "1":
        json.dump(signed, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    request = urllib.request.Request(
        endpoint,
        data=signed["body"].encode("utf-8"),
        method="POST",
        headers=signed["headers"],
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            sys.stdout.write(response.read().decode("utf-8"))
            sys.stdout.write("\n")
            return 0
    except urllib.error.HTTPError as exc:
        sys.stderr.write(f"Leona query failed: HTTP {exc.code}\n")
        sys.stderr.write(exc.read().decode("utf-8", errors="replace"))
        sys.stderr.write("\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
