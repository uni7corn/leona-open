# Leona BoxId Verdict Examples

These examples show how a customer backend exchanges a mobile SDK `BoxId` for
the collected Leona device/environment evidence.

Do not run these examples in an Android app. `LEONA_SECRET_KEY` is a backend
secret and must never be embedded in an APK.

## Contract

Endpoint:

```text
POST https://leona.xiyanshan.com/v1/verdict
```

Request body:

```json
{"boxId":"01KR0000000000000000000000"}
```

Required headers:

```text
Authorization: Bearer <LEONA_SECRET_KEY>
Content-Type: application/json
X-Leona-Timestamp: <unix-time-ms>
X-Leona-Nonce: <random-nonce>
X-Leona-Signature: <base64url-hmac-sha256>
```

Signature:

```text
signingText = timestamp + "\n" + nonce + "\n" + sha256(requestBody)
signature = base64url_no_padding(HMAC-SHA256(secretKey, signingText))
```

`/v1/verdict` is single-use. A successful query consumes the BoxId. Persist the
returned evidence report in your own backend if your business flow needs to
read it again.

## Environment variables

```bash
export LEONA_SECRET_KEY='your_backend_only_secret_key'
export BOX_ID='01KR0000000000000000000000'
export LEONA_ENDPOINT='https://leona.xiyanshan.com/v1/verdict'
```

`LEONA_ENDPOINT` is optional and defaults to the hosted Leona endpoint above.

## Run

Python:

```bash
python3 python/query_boxid.py
```

Java 11+:

```bash
javac java/QueryBoxId.java
java -cp java QueryBoxId
```

Go:

```bash
go run go/query_boxid.go
```

Node.js 18+:

```bash
node nodejs/query_boxid.mjs
```

C with libcurl + OpenSSL:

```bash
cc c/query_boxid.c -o /tmp/leona-query-c $(pkg-config --cflags --libs openssl libcurl)
/tmp/leona-query-c
```

C++17 with libcurl + OpenSSL:

```bash
c++ -std=c++17 cpp/query_boxid.cpp -o /tmp/leona-query-cpp $(pkg-config --cflags --libs openssl libcurl)
/tmp/leona-query-cpp
```

If `pkg-config` is unavailable, install the OpenSSL and libcurl development
packages and pass their include/library paths explicitly.

## Response fields to persist

- `boxId`
- `deviceFingerprint`
- `canonicalDeviceId`
- `events`
- `authoritativeRiskTags`
- `telemetryRiskTags`
- `riskTagsBySource`
- `provenance`
- `policyExplanation`

Leona returns evidence. The customer backend owns all business actions such as
allow, challenge, deny, honeypot, or manual review.
