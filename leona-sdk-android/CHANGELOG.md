# Changelog

All notable changes to Leona Android SDK are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-09

### Added
- First public Android SDK release for hosted Leona API integration.
- Evidence-only client posture: the SDK collects environment evidence and
  returns an opaque BoxId; customer backends own all business decisions.
- Public native runtime evidence for emulator, root, Magisk/KSU, Xposed,
  Frida/runtime mapping, unidbg, APK/resource/signing, and custom-ROM posture
  signals.
- Redacted support-bundle, logcat smoke, posture collection, and WeTest matrix
  scripts for repeatable integration checks.

### Changed
- Stabilized virtual-device fingerprinting so emulator/clone identity no
  longer depends on app-scoped Android ID.
- Hardened cloud config and reporting paths to use hashed identity fields and
  low-trust telemetry for client-provided evidence.
- Updated public docs to reflect the current open-source boundary: Android
  public SDK is open source; hosted backend, private detectors, and risk policy
  remain closed-source for security reasons.

### Fixed
- Clean OEM false positives found during WeTest release-gate runs, including
  vivo `qemu.hw.mainkeys*` navigation-key properties.
- WeTest/cloud-device timestamp skew by using server-time based reporting in
  the hosted/private reporting path.
- Token redaction for webshell/direct cloud-test artifacts.

## [0.1.0-alpha.1] - 2026-04-21

### Added
- Public Android SDK API surface:
  - `Leona.init()`
  - `Leona.sense()`
  - `Leona.senseAsync()`
  - `BoxId`
  - `LeonaConfig`
  - `Honeypot`
  - decoy `quickCheck()`
- Kotlin ↔ JNI ↔ C++ runtime collection path
- Native runtime detection for:
  - Frida / ptrace / trampoline signals
  - emulator signals
  - root / Magisk / KernelSU / Riru traces
  - Xposed / LSPosed / EdXposed traces
  - Unidbg traces
- X25519 + HKDF + AES-GCM + HMAC upload path
- Sample app for local stub mode and real server demo mode
- Minimal demo backend for verdict query demonstration

### Changed
- Sample app now supports Gradle property injection for real demo flow:
  - `LEONA_API_KEY`
  - `LEONA_REPORTING_ENDPOINT`
  - `LEONA_CLOUD_CONFIG_ENDPOINT`
  - `LEONA_DEMO_BACKEND_BASE_URL`
- Project status is now documented as an engineering alpha focused on
  Android SDK ↔ server loop closure

### Known limitations
- Sample app still defaults to local stub mode
- Real Android ↔ server ↔ demo backend acceptance is archived on emulator; real-device archive is still pending
- Public API should still be treated as alpha and may change before beta

## [Unreleased]

### Planned
- AAR release packaging hardening
- More real-device acceptance evidence
- Additional field validation on real devices and attacker sandboxes
