# Leona Backend Wrappers

These skeletons are public-safe server-side wrappers for customer backends.
They are not Android SDK code and must never run inside an APK.

Current slices:

- `nodejs/`: Node.js 18+ wrapper skeleton with tests.
- `java/`: Java 11+ wrapper skeleton using only the JDK standard library.

Scope:

- sign backend-only Leona requests with a tenant SecretKey
- query evidence reports and support bundles
- submit customer feedback labels
- redact Leona identifiers before logs or support export

Non-goals:

- no final business `allow`, `reject`, `block`, or `deny` decision
- no embedded real SecretKey, provider credential, token, full BoxId, or raw
  device identifier
- no dependency on private Leona server implementation

Run local checks:

```bash
./scripts/verify-backend-wrapper-skeletons.sh
```

The verification script also performs package dry-runs:

- `npm pack --dry-run` for the Node.js wrapper
- Gradle `jar`, `sourcesJar`, `javadocJar`, and generated Maven POM for the Java
  wrapper
