# Leona Public Docs

This directory contains public-safe documentation for the Leona Android public SDK.

Public GitHub scope:

- Android SDK integration
- Android sample app behavior
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

Automation runner prerequisites:

- GitHub CI visibility requires `gh` auth and access to `api.github.com`.
- Gradle verification requires network access to `services.gradle.org` (or a pre-cached Gradle wrapper distribution).
- In sandboxed environments, set `GRADLE_USER_HOME` to a writable path (for example: `GRADLE_USER_HOME=.gradle`).
