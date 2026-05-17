# Leona Android Public SDK

Leona is an Android runtime security SDK. The public repository contains the Android integration SDK, the sample Android app, public build tooling, and public-safe documentation.

The authoritative business decision is not made inside the APK or by Leona's
default SDK policy. Apps call `Leona.sense()` to collect and report evidence,
receive an opaque `BoxId`, and send that `BoxId` to their own business backend.
The business backend queries the Leona hosted API/backend for environment
evidence and provenance, then applies the customer's own product policy.

## Public Repository Rule

This GitHub repository intentionally keeps only the Android public integration SDK code.

- Open source: Android SDK public API, Android sample app, Gradle build, SDK tests, public-safe docs, CI for the public AAR.
- Not open source: Leona hosted API/backend implementation, private detector catalog, private native runtime, risk weights, tenant policy, internal ops, production deployment, secrets, and closed-source tooling.
- Directory names are kept for orientation, but closed-source directories contain only README placeholders explaining why the code is absent.

This split is deliberate. Publishing backend evidence-processing internals or high-value detector rules would weaken the security model by giving attackers the implementation they need to bypass the system.

## Usage Model

Customers can fully use Leona in their APK through the public Android SDK, but the open-source SDK must be configured with a Leona API key and Leona hosted endpoints.

```text
Android app + Leona SDK
    |
    | sense()
    v
Leona API/backend
    |
    | BoxId
    v
Customer app -> customer backend -> Leona evidence API -> customer decision
```

Client apps should not make final security decisions from local signals. The
client only collects evidence and reports it. Leona provides evidence and
provenance; allow, challenge, deny, honeypot, or other product actions belong to
the customer business policy.

## Repository Layout

```text
.
├── leona-sdk-android/   # Public Android SDK, sample app, Gradle build, SDK tests
├── leona-server/        # Placeholder only; backend implementation is closed source
├── demo-backend/        # Placeholder only; hosted/customer backend examples are closed source
├── leona/               # Placeholder only; internal CLI/tooling is closed source
├── scripts/             # Placeholder only; internal release/ops scripts are closed source
├── docs/                # Public-safe boundary and integration notes
└── .github/workflows/   # Public Android SDK CI
```

## Android Quick Start

```kotlin
Leona.init(
    context = this,
    config = LeonaConfig.Builder()
        .apiKey("your-leona-api-key")
        .reportingEndpoint("https://leona.xiyanshan.com")
        .build()
)

val boxId = Leona.sense()
```

Send `boxId` to your business backend. Your backend queries the Leona verdict API and applies your product policy.

## Android SDK Dependency

For `v0.2.0`, the first automated Maven channel is GitHub Packages:

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://maven.pkg.github.com/zedbully/leona-open") {
            credentials {
                username = providers.gradleProperty("gpr.user")
                    .orElse(providers.environmentVariable("GITHUB_ACTOR"))
                    .orNull
                password = providers.gradleProperty("gpr.key")
                    .orElse(providers.environmentVariable("GITHUB_TOKEN"))
                    .orNull
            }
        }
    }
}
```

```kotlin
dependencies {
    implementation("io.leonasec:leona-sdk-android:0.2.0")
}
```

GitHub Release AAR + `.sha256` files remain the fallback path for teams that do
not want to configure GitHub Packages credentials in Gradle.

Post-release consumption smoke:

```bash
cd leona-sdk-android
./scripts/verify-v0.2-public-consumption.sh
```

Without package credentials, this verifies the public GitHub Release AAR
fallback and `.sha256`. To also verify GitHub Packages remote Gradle resolution,
set `LEONA_GITHUB_PACKAGES_TOKEN` or `GITHUB_TOKEN` to a token with
`read:packages`.

`v0.2.x` hotfixes are limited to SDK acquisition, integration crashes, severe
false positives, public API compatibility, and public documentation drift. New
environment-detection capabilities stay in `v0.3.0+`.

## Backend: Exchange BoxId for Device Evidence

The Android app must never call the evidence query API directly. The app sends
the opaque `BoxId` to your backend, and your backend calls Leona with your
tenant `SecretKey`.

```text
Android app
  -> Leona.sense() -> BoxId
  -> your login/payment/API request carries BoxId
  -> your backend calls POST /v1/verdict
  -> Leona returns deviceFingerprint, canonicalDeviceId, events,
     provenance, and policyExplanation
```

Key separation:

- `LEONA_API_KEY` / AppKey: safe to configure in the APK; used for evidence upload.
- `LEONA_SECRET_KEY`: backend-only; used to query a BoxId. Never embed it in an APK.

Request:

```http
POST https://leona.xiyanshan.com/v1/verdict
Authorization: Bearer <LEONA_SECRET_KEY>
Content-Type: application/json
X-Leona-Timestamp: <unix-time-ms>
X-Leona-Nonce: <random-nonce>
X-Leona-Signature: <base64url-hmac-sha256>

{"boxId":"<BOX_ID_FROM_APP>"}
```

Signature input:

```text
signingText = timestamp + "\n" + nonce + "\n" + sha256(requestBody)
signature = base64url_no_padding(HMAC-SHA256(secretKey, signingText))
```

`X-Leona-Timestamp` is a backend request-signing field for `/v1/verdict`; it is
not a device environment signal. If a query fails with a timestamp-skew style
error, refresh the backend timestamp and retry according to your own retry
policy. Do not treat clock-skew/authentication errors as Root, Hook, emulator,
or tamper evidence.

Minimal Node.js example:

```js
import crypto from "node:crypto";

async function queryLeonaBox(boxId) {
  const endpoint = "https://leona.xiyanshan.com/v1/verdict";
  const secret = process.env.LEONA_SECRET_KEY;
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

  if (!response.ok) {
    throw new Error(`Leona verdict query failed: ${response.status} ${await response.text()}`);
  }
  return response.json();
}
```

Ready-to-run backend examples are available in
[`examples/boxid-verdict`](examples/boxid-verdict) for Python, Java, Go, C,
C++, and Node.js.

Typical backend flow with cache:

```text
1. Android app calls Leona.sense() during login/payment/high-value action.
2. App sends the opaque BoxId in the customer API request.
3. Customer backend checks whether this business record already has a cached
   Leona evidence report.
4. On cache miss, backend signs and calls POST /v1/verdict with SecretKey.
5. Backend persists the first successful report with its own record id,
   response status, query time, deviceFingerprint, canonicalDeviceId, events,
   provenance, and policyExplanation.
6. Backend applies customer-owned business policy from the cached evidence.
7. Later retries or audits read the cached report because the BoxId has already
   been consumed by the successful /v1/verdict call.
```

Important response fields:

- `deviceFingerprint`: Leona device fingerprint identifier.
- `canonicalDeviceId`: stable app-scoped Leona device id, usually prefixed with `L`.
- `events`: collected device/environment evidence events.
- `authoritativeRiskTags`: tags derived from authoritative server/native evidence.
- `telemetryRiskTags`: low-trust telemetry kept for explanation/debugging.
- `riskTagsBySource`: source breakdown such as `native_payload`, `server_policy`, `client_header`.
- `provenance` and `policyExplanation`: why the evidence report looks the way it does.

`/v1/verdict` is single-use. After a successful query, the BoxId is consumed;
subsequent calls return `410 LEONA_BOX_ALREADY_USED`. Cache the returned report
inside your own business order/login/risk record if you need to read it again.

Leona returns evidence. Your backend decides whether to allow, challenge, deny,
honeypot, or take any other product action.

## Customer Integration Checklist

- Get a Leona AppKey for the Android SDK and a separate backend-only SecretKey.
- Configure the APK with AppKey and hosted endpoint only; never package SecretKey.
- Call `Leona.sense()` at the protected business moment and send the opaque BoxId to your backend.
- Include the BoxId in a backend-owned login/order/payment/risk request field.
- Sign backend `POST /v1/verdict` calls with timestamp, nonce, body hash, and HMAC signature.
- Cache the first successful verdict response with your own business record because BoxId is single-use.
- Handle `410 LEONA_BOX_ALREADY_USED` through your cache/idempotency path.
- Log auth/signature/time/network/server failures separately so integration issues are diagnosable.
- Keep final allow/challenge/deny/manual-review actions in your own backend policy.

## Build Public SDK

```bash
cd leona-sdk-android
./gradlew :sdk:testDebugUnitTest :sdk:assembleRelease --no-daemon
```

AAR output:

```text
leona-sdk-android/sdk/build/outputs/aar/sdk-release.aar
```

## CI

The public GitHub workflow builds only the Android public SDK:

- `:sdk:lint` as advisory
- `:sdk:testDebugUnitTest`
- `:sdk:assembleDebug`
- `:sdk:assembleRelease`
- native source sanity as advisory

Nightly CI runs the same public SDK checks. It does not run private backend, demo backend, or closed-source alpha-closure flows.

## Closed-Source Areas

The following areas are intentionally absent from public code:

- Leona hosted API/backend implementation
- hosted `/v1/verdict` evidence/provenance policy and production operations
- private native detector catalog and private JNI bridge
- private risk scoring weights and tenant rollout policy
- production config, keys, KMS/Vault wiring, dashboards, and internal ops
- internal release, sync, and deployment automation

See [docs/open-source-policy.md](docs/open-source-policy.md) for the public/private boundary.
