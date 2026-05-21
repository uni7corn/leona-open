# Leona Public Docs

This directory contains public-safe documentation for Leona public SDK surfaces.
Android is the released SDK line; iOS is a v0.4.0 public-safe scaffold/extension
track until formally released.

Public GitHub scope:

- Android SDK integration
- Android sample app behavior
- iOS public SDK scaffold and sample app behavior when present
- public/private boundary
- public CI and release notes for the AAR

Not public:

- Leona hosted backend implementation
- private detector/risk policy
- production deployment
- internal ops
- private customer policy
- secrets or environment-specific records

Start here:

- [Open-source policy](open-source-policy.md)
- [Public/private boundary matrix](open-vs-private-final-matrix.md)
- [Android v0.4 evidence and privacy boundary](../leona-sdk-android/docs/v0.4-evidence-privacy-boundary.md)
- [Android v0.4 release notes draft](../leona-sdk-android/docs/v0.4-release-notes-draft.md)
- [Android v0.4 release checklist](../leona-sdk-android/docs/v0.4-release-checklist.md)
- [Android SDK changelog](../leona-sdk-android/CHANGELOG.md)

Automation runner prerequisites:

- GitHub CI visibility requires `gh` auth and access to `api.github.com`.
- Gradle verification requires network access to `services.gradle.org` (or a pre-cached Gradle wrapper distribution).
- In sandboxed environments, set `GRADLE_USER_HOME` to a writable path (for example: `GRADLE_USER_HOME=.gradle`).
