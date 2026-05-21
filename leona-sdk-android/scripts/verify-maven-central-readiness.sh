#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
VERSION="${LEONA_SDK_VERSION:-$(grep '^VERSION_NAME=' "${ROOT_DIR}/gradle.properties" | cut -d= -f2-)}"
GROUP_ID="${LEONA_SDK_GROUP:-$(grep '^GROUP=' "${ROOT_DIR}/gradle.properties" | cut -d= -f2-)}"
ARTIFACT_ID="${LEONA_SDK_ARTIFACT:-leona-sdk-android}"
REPORT_DIR="${LEONA_MAVEN_CENTRAL_READINESS_OUT:-/tmp/leona-maven-central-readiness-$(date +%Y%m%d-%H%M%S)}"
REQUIRE_SECRETS="${LEONA_REQUIRE_MAVEN_CENTRAL_SECRETS:-0}"
RUN_LOCAL_CONSUMER="${LEONA_RUN_MAVEN_LOCAL_CONSUMER:-0}"

STATUS=0
PASS_COUNT=0
WARNINGS=()
BLOCKERS=()
FAILURES=()

mkdir -p "${REPORT_DIR}"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

warn() {
  WARNINGS+=("$1")
  printf '[warn] %s\n' "$1" >&2
}

blocker() {
  BLOCKERS+=("$1")
  printf '[blocked] %s\n' "$1"
}

fail() {
  STATUS=1
  FAILURES+=("$1")
  printf '[fail] %s\n' "$1" >&2
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

env_present() {
  local name="$1"
  [[ -n "${!name:-}" ]]
}

check_secret_env() {
  local name="$1"
  if env_present "${name}"; then
    pass "CI secret ${name} is present"
  else
    if [[ "${REQUIRE_SECRETS}" == "1" ]]; then
      fail "CI secret ${name} is missing"
    else
      blocker "CI secret ${name} is not configured"
    fi
  fi
}

cd "${REPO_DIR}"

echo "[maven-central-readiness] coordinate: ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}"
echo "[maven-central-readiness] report dir: ${REPORT_DIR}"
echo "[maven-central-readiness] secret values are never printed by this script"

require_contains "SDK applies maven-publish" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  'id\("maven-publish"\)'
require_contains "SDK publication has sources jar" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  "withSourcesJar"
require_contains "SDK publication has javadoc jar" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  "withJavadocJar"
require_contains "SDK publication uses expected group" \
  "leona-sdk-android/gradle.properties" \
  "^GROUP=${GROUP_ID}$"
require_contains "SDK publication version is v${VERSION}" \
  "leona-sdk-android/gradle.properties" \
  "^VERSION_NAME=${VERSION}$"
require_contains "POM declares Apache 2 license" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  "Apache License, Version 2.0"
require_contains "POM declares public SCM URL" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  "https://github.com/zedbully/leona-open"
require_contains "GitHub Packages fallback repository remains configured" \
  "leona-sdk-android/sdk/build.gradle.kts" \
  "GitHubPackages"
require_contains "tag workflow still publishes GitHub Release assets" \
  ".github/workflows/android.yml" \
  "Create GitHub Release"
require_contains "tag workflow still publishes GitHub Packages package" \
  ".github/workflows/android.yml" \
  "publishReleasePublicationToGitHubPackagesRepository"
require_executable "local Maven consumer smoke exists" \
  "leona-sdk-android/scripts/verify-maven-local-consumer.sh"

if contains "leona-sdk-android/sdk/build.gradle.kts" "CentralPortal|MavenCentral|Sonatype|sonatype|central"; then
  pass "Maven Central publishing path appears to be wired"
else
  blocker "Maven Central publishing path is not wired yet; keep GitHub Release/GitHub Packages fallback for v${VERSION}."
fi

check_secret_env "CENTRAL_PORTAL_USERNAME"
check_secret_env "CENTRAL_PORTAL_PASSWORD"
check_secret_env "SIGNING_KEY"
check_secret_env "SIGNING_PASSWORD"

if env_present "SIGNING_KEY_ID"; then
  pass "optional SIGNING_KEY_ID is present"
else
  warn "optional SIGNING_KEY_ID is not configured; some signing plugins can infer it, but CI should document the chosen path."
fi

if env_present "LEONA_MAVEN_CENTRAL_NAMESPACE"; then
  pass "optional LEONA_MAVEN_CENTRAL_NAMESPACE is present"
else
  warn "optional LEONA_MAVEN_CENTRAL_NAMESPACE is not configured; document the verified namespace before Central publish."
fi

if [[ "${RUN_LOCAL_CONSUMER}" == "1" ]]; then
  echo "[maven-central-readiness] running isolated local Maven consumer smoke"
  LEONA_SDK_VERSION="${VERSION}" \
    "${ROOT_DIR}/scripts/verify-maven-local-consumer.sh" > "${REPORT_DIR}/maven-local-consumer.txt"
  pass "isolated local Maven consumer smoke passes"
else
  warn "local Maven consumer smoke not rerun; set LEONA_RUN_MAVEN_LOCAL_CONSUMER=1 to execute it."
fi

{
  echo "# Leona Maven Central Readiness"
  echo
  echo "- status: $([[ "${STATUS}" == "0" ]] && echo "local-pass-with-external-blockers" || echo "failed")"
  echo "- coordinate: \`${GROUP_ID}:${ARTIFACT_ID}:${VERSION}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- secret values printed: no"
  echo "- local pass checks: ${PASS_COUNT}"
  echo
  echo "## Failures"
  if (( ${#FAILURES[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${FAILURES[@]}"
  fi
  echo
  echo "## External Blockers"
  if (( ${#BLOCKERS[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${BLOCKERS[@]}"
  fi
  echo
  echo "## Warnings"
  if (( ${#WARNINGS[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${WARNINGS[@]}"
  fi
} > "${REPORT_DIR}/summary.md"

echo "[maven-central-readiness] summary: ${REPORT_DIR}/summary.md"
exit "${STATUS}"
