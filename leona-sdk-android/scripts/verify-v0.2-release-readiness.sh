#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
REPORT_DIR="${LEONA_RELEASE_READINESS_OUT:-/tmp/leona-v0.2-readiness-$(date +%Y%m%d-%H%M%S)}"
VERSION="${LEONA_SDK_VERSION:-0.2.0}"
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
    fail "${label}: found forbidden public-boundary match\n${matches}"
  fi
}

cd "${REPO_DIR}"

echo "[readiness] Leona Android public SDK v${VERSION}"
echo "[readiness] report dir: ${REPORT_DIR}"

require_contains "workflow publishes GitHub Release assets" \
  ".github/workflows/android.yml" \
  "Publish release artifacts"
require_contains "workflow publishes GitHub Packages Maven package" \
  ".github/workflows/android.yml" \
  "publishReleasePublicationToGitHubPackagesRepository"
require_contains "workflow has packages write permission" \
  ".github/workflows/android.yml" \
  "packages:[[:space:]]*write"

require_contains "gradle.properties version is ${VERSION}" \
  "leona-sdk-android/gradle.properties" \
  "^VERSION_NAME=${VERSION}$"
require_contains "SDK BuildConstants version is ${VERSION}" \
  "leona-sdk-android/sdk/src/main/kotlin/io/leonasec/leona/BuildConstants.kt" \
  "VERSION_NAME = \"${VERSION}\""
require_contains "sample app versionName is ${VERSION}" \
  "leona-sdk-android/sample-app/build.gradle.kts" \
  "versionName = \"${VERSION}\""

require_contains "root README documents Gradle coordinate" \
  "README.md" \
  "io\\.leonasec:leona-sdk-android:${VERSION}"
require_contains "SDK README documents Gradle coordinate" \
  "leona-sdk-android/README.md" \
  "io\\.leonasec:leona-sdk-android:${VERSION}"
require_contains "README documents backend-owned verdict cache" \
  "README.md" \
  "Cache the first successful verdict response|Backend: Exchange BoxId"
require_contains "SDK README keeps evidence-only business policy wording" \
  "leona-sdk-android/README.md" \
  "Leona provides evidence, not final business decisions|does not make allow/reject/block decisions"
require_contains "CHANGELOG has v${VERSION} entry" \
  "leona-sdk-android/CHANGELOG.md" \
  "\\[${VERSION}\\]"

require_executable "clean OEM ledger gate is executable" \
  "leona-sdk-android/scripts/verify-clean-oem-ledger.sh"
require_executable "device id stability runner is executable" \
  "leona-sdk-android/scripts/run-device-id-stability.sh"
require_executable "clock skew regression runner is executable" \
  "leona-sdk-android/scripts/run-clock-skew-regression.sh"
require_executable "Maven local consumer gate is executable" \
  "leona-sdk-android/scripts/verify-maven-local-consumer.sh"

echo "[readiness] running clean OEM ledger gate"
"${ROOT_DIR}/scripts/verify-clean-oem-ledger.sh" > "${REPORT_DIR}/clean-oem-ledger.txt"
pass "clean OEM ledger gate passes"

require_absent "public docs do not expose known private/deployment terms" \
  '/home/leona|111\.170|leona-homepage|RiskScoringEngine|LEONA_INCLUDE_PRIVATE_CORE|internal console|recent boxes|private ops' \
  README.md \
  leona-sdk-android/README.md \
  leona-sdk-android/docs/TESTING.md \
  leona-sdk-android/docs/wetest-matrix-runbook.md \
  leona-sdk-android/CHANGELOG.md

if [[ "${LEONA_RUN_MAVEN_CONSUMER_GATE:-0}" == "1" ]]; then
  echo "[readiness] running Maven local consumer gate"
  "${ROOT_DIR}/scripts/verify-maven-local-consumer.sh" > "${REPORT_DIR}/maven-consumer.txt"
  pass "Maven local consumer gate passes"
else
  warn "Maven local consumer gate not rerun; set LEONA_RUN_MAVEN_CONSUMER_GATE=1 to execute it."
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

blocker "GitHub Android Public SDK CI must be checked on the final pushed commit/tag."
blocker "GitHub Release AAR + sha256 are only produced by the v${VERSION} tag workflow."
blocker "GitHub Packages remote Gradle pull must be validated after the v${VERSION} tag publishes."
blocker "Independent Android Studio AVD and clone VM dynamic identity validation still require available environments."
blocker "vivo/iQOO Android 14 SCDN timeout retest still requires a live device/session."

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
