# WeTest Device Matrix Runbook

This runbook is for collecting Leona Android SDK evidence on WeTest devices while
preserving the SDK principle: the client collects evidence only, and final risk
decisions come from the server verdict.

## Scope

Use WeTest for these work items:

- Mainland / non-GMS OEM route: validate at least one real OEM bridge or staging
  verifier dry run, then record provider, status, code, provenance, and verdict.
- Custom AOSP / custom ROM / cloud phone samples: collect posture and verdict
  records across real OEM, custom ROM/GSI, unlocked bootloader, Magisk testbed,
  and cloud phone devices.
- Emulator matrix expansion: add cloud-phone samples and, when available, Nox,
  LDPlayer, BlueStacks, Genymotion, and other hosted Android environments.

## APK Lanes

### Release / non-debug sample

Use this lane for non-debug package posture:

- Build: `./gradlew :sample-app:assembleRelease`
- Artifact: `sample-app/build/outputs/apk/release/sample-app-release-unsigned.apk`
- Lab install artifact: sign the unsigned APK with a lab key before uploading to
  WeTest.

Expected properties:

- `android:debuggable=false`
- no `LEONA_E2E_TOKEN`
- no fake attestation implementation in the release binary
- no debug API key, debug endpoint, or LAN cleartext config

This lane can prove `sideload_release` or platform-installed non-debug posture.
It does not prove trusted distribution unless the install channel is Play, OEM
store, MDM, enterprise distribution, or another trusted channel accepted by the
server policy.

### Debug / staging sample

Use this lane only for controlled E2E and logcat smoke collection. It may include
`LEONA_E2E_TOKEN`, local/staging endpoint configuration, and debug-only fake
attestation controls. Results from this lane must be labeled as debug/staging and
must not be used as clean release conclusions.

## WeTest Collection Steps

1. Upload the selected APK and choose a device group.
2. Record device metadata before running Leona:
   - device model, manufacturer, Android version, ABI
   - install channel and package flags when WeTest exposes them
   - whether the device is real hardware, cloud phone, emulator, or custom ROM
3. Start the app and run `sense()` through the normal UI or host-app flow.
4. Capture logcat and app output. Do not rely on screenshot OCR as the source of
   truth.
5. Record only redacted identifiers:
   - BoxId
   - canonical hash or hint
   - verdict id
   - attestation provider/status/code
   - authoritative risk tags
   - telemetry risk tags
   - `riskTagsBySource`
6. Query the server explain endpoint for the BoxId/verdict id when available.
   This query must use tenant-scoped server credentials outside the APK.
7. Save the sample into the matrix with expected outcome and actual outcome.

## Minimum Device Matrix

| Group | Minimum samples | Required record |
| --- | ---: | --- |
| Clean OEM real device | 2 | No emulator/root/hook tags; release/non-debug posture preferred |
| Mainland / non-GMS OEM | 1 | Real OEM bridge or staging verifier dry run |
| Custom ROM / GSI | 2 | `rom.*`, `gsi.*`, `verified_boot.*`, `bootloader.*` evidence |
| Unlocked bootloader | 1 | `bootloader.*` and verified boot state |
| Root / Magisk testbed | 1 | Root evidence without affecting clean OEM samples |
| Cloud phone | 2 | Virtualization/cloud-phone evidence and server provenance |
| Emulator family | 4 | Runtime evidence beyond brand/model strings |

## Blocking Conditions

Do not mark the related work item complete when:

- the sample only uses debug APK and debug intent automation
- the APK is release but installed only through `adb install` and no trusted
  distribution conclusion is needed
- WeTest does not expose logs, BoxId, or a server query path
- the server cannot return provenance or `riskTagsBySource`
- client header telemetry is treated as authoritative server risk
- any record contains raw device id, raw install id, raw canonical id, API key,
  token, secret, endpoint secret, or unredacted fingerprint
