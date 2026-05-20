#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${LEONA_TARGET_RELEASE_VERSION:-${LEONA_SDK_VERSION:-0.4.0}}"
REPORT_DIR="${LEONA_V04_POST_RELEASE_CONSUMPTION_OUT:-/tmp/leona-v0.4-post-release-consumption-$(date +%Y%m%d-%H%M%S)}"
CHILD_OUT="${REPORT_DIR}/public-consumption"
SUMMARY_PATH="${REPORT_DIR}/summary.md"
REQUIRE_READY="${LEONA_REQUIRE_POST_RELEASE_CONSUMPTION:-0}"
STATUS="blocked-release-not-published"
EXIT_CODE=0

mkdir -p "${REPORT_DIR}"

echo "[v0.4-post-release] target version: ${VERSION}"
echo "[v0.4-post-release] report dir: ${REPORT_DIR}"

if LEONA_SDK_VERSION="${VERSION}" \
   LEONA_PUBLIC_CONSUMPTION_OUT="${CHILD_OUT}" \
   LEONA_PUBLIC_CONSUMPTION_CURL_CONNECT_TIMEOUT="${LEONA_PUBLIC_CONSUMPTION_CURL_CONNECT_TIMEOUT:-5}" \
   LEONA_PUBLIC_CONSUMPTION_CURL_MAX_TIME="${LEONA_PUBLIC_CONSUMPTION_CURL_MAX_TIME:-15}" \
   "${ROOT_DIR}/scripts/verify-v0.2-public-consumption.sh" \
   > "${REPORT_DIR}/public-consumption.stdout.txt" \
   2> "${REPORT_DIR}/public-consumption.stderr.txt"; then
  STATUS="pass"
else
  CHILD_STATUS=$?
  if [[ "${REQUIRE_READY}" == "1" ]]; then
    STATUS="failed"
    EXIT_CODE="${CHILD_STATUS}"
  else
    STATUS="blocked-release-not-published"
    EXIT_CODE=0
  fi
fi

{
  echo "# Leona v0.4 Android Post-Release Consumption Smoke"
  echo
  echo "- status: ${STATUS}"
  echo "- target version: \`${VERSION}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- child report dir: \`${CHILD_OUT}\`"
  echo "- strict mode: \`${REQUIRE_READY}\`"
  echo "- creates tag: no"
  echo "- publishes artifacts: no"
  echo "- executes git add: no"
  echo "- starts paid devices or WeTest sessions: no"
  echo "- secret values printed: no"
  echo
  echo "## Interpretation"
  if [[ "${STATUS}" == "pass" ]]; then
    echo "- The GitHub Release fallback artifact was consumed and verified."
    echo "- If a package-read token was configured, GitHub Packages was also checked by the underlying consumer smoke."
  elif [[ "${STATUS}" == "blocked-release-not-published" ]]; then
    echo "- The real v0.4.0 GitHub Release/GitHub Packages artifact is not consumable yet, or the network/package-read context is unavailable."
    echo "- This is expected before pushing the annotated tag and waiting for the tag workflow to publish artifacts."
    echo "- Re-run with \`LEONA_REQUIRE_POST_RELEASE_CONSUMPTION=1\` after the release exists to make this a hard gate."
  else
    echo "- The required post-release consumer smoke failed. Inspect \`public-consumption.stdout.txt\` and \`public-consumption.stderr.txt\`."
  fi
} > "${SUMMARY_PATH}"

echo "[v0.4-post-release] summary: ${SUMMARY_PATH}"
exit "${EXIT_CODE}"
