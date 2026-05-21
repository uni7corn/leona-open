#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
VERSION="${LEONA_SDK_VERSION:-0.3.0}"
REPORT_DIR="${LEONA_RELEASE_READINESS_OUT:-/tmp/leona-v0.3-readiness-$(date +%Y%m%d-%H%M%S)}"
STATUS=0
PASS_COUNT=0
FAILURES=()
WARNINGS=()
BLOCKERS=()

mkdir -p "${REPORT_DIR}"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

fail() {
  STATUS=1
  FAILURES+=("$1")
  printf '[fail] %s\n' "$1" >&2
}

warn() {
  WARNINGS+=("$1")
  printf '[warn] %s\n' "$1" >&2
}

blocker() {
  BLOCKERS+=("$1")
  printf '[blocked] %s\n' "$1"
}

contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${file}" ]] && grep -Eq "${pattern}" "${file}"
}

require_contains() {
  local label="$1"
  local file="$2"
  local pattern="$3"
  if contains "${file}" "${pattern}"; then
    pass "${label}"
  else
    fail "${label}: missing pattern ${pattern} in ${file}"
  fi
}

require_executable() {
  local label="$1"
  local file="$2"
  if [[ -x "${file}" ]]; then
    pass "${label}"
  else
    fail "${label}: not executable (${file})"
  fi
}

require_absent() {
  local label="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(rg -n "${pattern}" "$@" 2>/dev/null || true)"
  if [[ -z "${matches}" ]]; then
    pass "${label}"
  else
    fail "${label}: found forbidden public-boundary match
${matches}"
  fi
}

cd "${REPO_DIR}"

echo "[readiness] Leona Android public SDK v${VERSION}"
echo "[readiness] report dir: ${REPORT_DIR}"

require_contains "public SDK CI workflow has native sanity gate" \
  ".github/workflows/android.yml" \
  "Native source sanity"
require_contains "public SDK CI workflow has lint and unit test gate" \
  ".github/workflows/android.yml" \
  "Lint \\+ Unit tests|sdk:testDebugUnitTest"
require_contains "public SDK CI workflow assembles AAR" \
  ".github/workflows/android.yml" \
  "Assemble AAR|sdk:assembleRelease"

require_contains "Gradle publication version is v${VERSION}" \
  "leona-sdk-android/gradle.properties" \
  "^VERSION_NAME=${VERSION}$"
require_contains "SDK runtime version constant is v${VERSION}" \
  "leona-sdk-android/sdk/src/main/kotlin/io/leonasec/leona/BuildConstants.kt" \
  "VERSION_NAME = \"${VERSION}\""
require_contains "sample app versionName is v${VERSION}" \
  "leona-sdk-android/sample-app/build.gradle.kts" \
  "versionName = \"${VERSION}\""
require_contains "root README documents v${VERSION} dependency" \
  "README.md" \
  "leona-sdk-android:${VERSION}"
require_contains "SDK README documents v${VERSION} dependency" \
  "leona-sdk-android/README.md" \
  "leona-sdk-android:${VERSION}"
require_contains "SDK README documents v${VERSION} release AAR fallback" \
  "leona-sdk-android/README.md" \
  "leona-sdk-android-${VERSION}\\.aar"

require_contains "root README keeps evidence-only business policy wording" \
  "README.md" \
  "client only collects evidence and reports it|Leona provides evidence and"
require_contains "SDK README keeps evidence-only business policy wording" \
  "leona-sdk-android/README.md" \
  "Leona provides evidence, not final business decisions|does not make allow/reject/block decisions"
require_contains "CHANGELOG keeps v${VERSION} release history" \
  "leona-sdk-android/CHANGELOG.md" \
  "\\[${VERSION//./\\.}\\]"
require_contains "CHANGELOG keeps v0.2.0 release history" \
  "leona-sdk-android/CHANGELOG.md" \
  "\\[0\\.2\\.0\\]"

require_executable "public consumption smoke is executable" \
  "leona-sdk-android/scripts/verify-v0.2-public-consumption.sh"
require_executable "clean OEM ledger gate is executable" \
  "leona-sdk-android/scripts/verify-clean-oem-ledger.sh"
require_executable "device id stability runner is executable" \
  "leona-sdk-android/scripts/run-device-id-stability.sh"
require_executable "cloud device collection runner is executable" \
  "leona-sdk-android/scripts/run-cloud-device-collection.sh"
require_contains "sample app has Play Integrity bridge template" \
  "leona-sdk-android/sample-app/PLAY_INTEGRITY_REAL_BRIDGE_TEMPLATE.md" \
  "StandardIntegrityManager"
require_contains "sample app keeps release builds free of fake attestation" \
  "leona-sdk-android/sample-app/src/release/kotlin/io/leonasec/leona/sample/SamplePlayIntegrityDebugProvider.kt" \
  "AttestationProvider\\? = null"

echo "[readiness] running clean OEM ledger gate"
"${ROOT_DIR}/scripts/verify-clean-oem-ledger.sh" > "${REPORT_DIR}/clean-oem-ledger.txt"
pass "clean OEM ledger gate passes"

require_absent "public tracked docs do not expose private/deployment terms" \
  '/home/leona|111\.170|leona-homepage|RiskScoringEngine|LEONA_INCLUDE_PRIVATE_CORE|internal console|recent boxes|private ops' \
  README.md \
  leona-sdk-android/README.md \
  leona-sdk-android/docs/TESTING.md \
  leona-sdk-android/docs/wetest-matrix-runbook.md \
  leona-sdk-android/docs/emulator-matrix.md \
  leona-sdk-android/docs/rom-matrix.md \
  leona-sdk-android/CHANGELOG.md

if [[ "${LEONA_RUN_PUBLIC_CONSUMPTION:-${LEONA_RUN_V02_PUBLIC_CONSUMPTION:-0}}" == "1" ]]; then
  echo "[readiness] running v${VERSION} public consumption smoke"
  LEONA_SDK_VERSION="${VERSION}" \
    "${ROOT_DIR}/scripts/verify-v0.2-public-consumption.sh" > "${REPORT_DIR}/v${VERSION}-public-consumption.txt"
  pass "v${VERSION} public consumption smoke passes"
else
  warn "v${VERSION} public consumption smoke not rerun; set LEONA_RUN_PUBLIC_CONSUMPTION=1 to execute it after tag assets are published."
fi

if [[ "${LEONA_RUN_PUBLIC_GRADLE_GATE:-0}" == "1" ]]; then
  echo "[readiness] running public Gradle gate"
  (
    cd "${ROOT_DIR}"
    ./gradlew :sdk:lint :sdk:testDebugUnitTest :sdk:assembleRelease :sample-app:assembleRelease --no-daemon
  ) > "${REPORT_DIR}/public-gradle-gate.txt"
  pass "public Gradle gate passes"
else
  warn "public Gradle gate not rerun; set LEONA_RUN_PUBLIC_GRADLE_GATE=1 to execute it."
fi

if [[ "${LEONA_RUN_ATTESTATION_DRY_RUN:-0}" == "1" ]]; then
  echo "[readiness] running attestation dry-run unit tests"
  (
    cd "${ROOT_DIR}"
    ./gradlew :sample-app:testDebugUnitTest --tests 'io.leonasec.leona.sample.SamplePlayIntegrityTest' --no-daemon
  ) > "${REPORT_DIR}/attestation-dry-run-unit-tests.txt"
  pass "attestation dry-run unit tests pass"
else
  warn "attestation dry-run unit tests not rerun; set LEONA_RUN_ATTESTATION_DRY_RUN=1 to execute them."
fi

blocker "GitHub Android Public SDK CI must be checked on the final pushed commit/tag."
blocker "GitHub Release AAR + sha256 are produced by the final v${VERSION} tag workflow."
blocker "GitHub Packages or selected artifact repository consumer smoke must be validated after publish."
warn "Real custom ROM/GSI/unlocked-device and broader external emulator samples are deferred to the next iteration."
warn "Additional hidden Root/Magisk/Shamiko/HMA combinations are deferred to the next iteration."
warn "Real Play Integrity/OEM provider smoke is deferred to the next iteration; v${VERSION} ships the public dry-run gate."

{
  echo "# Leona v${VERSION} Release Readiness"
  echo
  echo "- status: $([[ "${STATUS}" == "0" ]] && echo "local-pass-with-external-blockers" || echo "failed")"
  echo "- local pass checks: ${PASS_COUNT}"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo
  echo "## Failures"
  if (( ${#FAILURES[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${FAILURES[@]}"
  fi
  echo
  echo "## Warnings"
  if (( ${#WARNINGS[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${WARNINGS[@]}"
  fi
  echo
  echo "## External Blockers"
  printf -- '- %s\n' "${BLOCKERS[@]}"
} > "${REPORT_DIR}/summary.md"

echo "[readiness] summary: ${REPORT_DIR}/summary.md"
exit "${STATUS}"
