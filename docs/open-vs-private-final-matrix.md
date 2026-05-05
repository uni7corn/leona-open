# Leona Public / Private Boundary Matrix

> Updated: 2026-04-29

## 1. Product Split

| Area | Public GitHub | Private/Internal |
|---|---|---|
| Role | Android public integration SDK | Hosted API/backend, private detection, evidence ops |
| Goal | Let customers integrate Leona into an APK | Collect, normalize, and operate device environment evidence |
| Visibility | Open source | Not open source |
| Runtime decision | No final decision in APK | Evidence report only; customer business policy is external |

## 2. Android

| Module / capability | Public GitHub | Private/Internal |
|---|---:|---:|
| `Leona.init()` / `Leona.sense()` / `BoxId` | Yes | Reused |
| `LeonaConfig` public endpoint/key config | Yes | Reused |
| Android sample app | Yes | May be customized internally |
| Public AAR build | Yes | Reused |
| Public fallback native runtime | Yes | May coexist |
| private native runtime | No | Yes |
| private detector catalog / high-value heuristics | No | Yes |
| private JNI bridge | No | Yes |
| production attestation bridge details | No | Yes |

## 3. Backend

| Module / capability | Public GitHub | Private/Internal |
|---|---:|---:|
| Leona hosted API/backend implementation | No | Yes |
| `/v1/verdict` evidence report implementation | No | Yes |
| evidence scoring / grouping implementation | No | Yes |
| tenant / stage / rollout collection policy | No | Yes |
| internal ops endpoints | No | Yes |
| production deployment/config | No | Yes |
| keys, certificates, KMS/Vault wiring | No | Yes |

Public SDK users must connect to the Leona API/backend. The public repository does not ship a production backend implementation.

## 4. Placeholder Directories

| Directory | Public GitHub content |
|---|---|
| `leona-sdk-android/` | Android public SDK code |
| `leona-sdk-android/private/` | README placeholder only |
| `leona-server/` | README placeholder only |
| `demo-backend/` | README placeholder only |
| `leona/` | README placeholder only |
| `scripts/` | README placeholder only |

## 5. Default Rule

New code defaults to:

- Android public integration code -> public repository.
- Backend, private detector, risk policy, production ops, deployment, or internal tooling -> private/internal repository only.
