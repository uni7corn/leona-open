#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_VERSION="${LEONA_TARGET_RELEASE_VERSION:-0.4.0}"
REPORT_DIR="${LEONA_V04_RELEASE_CANDIDATE_REVIEW_OUT:-/tmp/leona-v0.4-release-candidate-review-$(date +%Y%m%d-%H%M%S)}"
MANIFEST_OUT="${LEONA_V04_RELEASE_CANDIDATE_OUT:-${REPORT_DIR}/release-candidate-manifest}"
SCHEMA_OUT="${LEONA_V04_RELEASE_CANDIDATE_SCHEMA_OUT:-${REPORT_DIR}/release-candidate-manifest-schema}"

mkdir -p "${REPORT_DIR}" "${MANIFEST_OUT}" "${SCHEMA_OUT}"

MANIFEST_EXIT=0
SCHEMA_EXIT=0

echo "[release-candidate-review] Leona Android v0.4 release candidate review"
echo "[release-candidate-review] target release version: ${TARGET_VERSION}"
echo "[release-candidate-review] report dir: ${REPORT_DIR}"
echo "[release-candidate-review] secret values are never printed by this script"
echo "[release-candidate-review] running release candidate manifest"

if env \
  LEONA_TARGET_RELEASE_VERSION="${TARGET_VERSION}" \
  LEONA_V04_RELEASE_CANDIDATE_OUT="${MANIFEST_OUT}" \
  "${ROOT_DIR}/scripts/verify-v0.4-release-candidate-manifest.sh" \
  > "${REPORT_DIR}/release-candidate-manifest.log" 2>&1; then
  echo "[release-candidate-review] release candidate manifest: pass"
else
  MANIFEST_EXIT=$?
  echo "[release-candidate-review] release candidate manifest: failed (${MANIFEST_EXIT})"
fi

MANIFEST_SUMMARY="${MANIFEST_OUT}/summary.md"
if [[ -f "${MANIFEST_SUMMARY}" ]]; then
  echo "[release-candidate-review] running release candidate manifest schema"
  if env \
    LEONA_TARGET_RELEASE_VERSION="${TARGET_VERSION}" \
    LEONA_V04_RELEASE_CANDIDATE_SCHEMA_OUT="${SCHEMA_OUT}" \
    "${ROOT_DIR}/scripts/verify-v0.4-release-candidate-manifest-schema.py" \
    "${MANIFEST_SUMMARY}" \
    > "${REPORT_DIR}/release-candidate-manifest-schema.log" 2>&1; then
    echo "[release-candidate-review] release candidate manifest schema: pass"
  else
    SCHEMA_EXIT=$?
    echo "[release-candidate-review] release candidate manifest schema: failed (${SCHEMA_EXIT})"
  fi
else
  SCHEMA_EXIT=1
  echo "[release-candidate-review] release candidate manifest schema: skipped; summary missing"
fi

manifest_status="missing"
schema_status="missing"
if [[ -f "${MANIFEST_SUMMARY}" ]]; then
  manifest_status="$(awk -F': ' '/^- status: / {print $2; exit}' "${MANIFEST_SUMMARY}")"
fi
if [[ -f "${SCHEMA_OUT}/summary.md" ]]; then
  schema_status="$(awk -F': ' '/^- status: / {print $2; exit}' "${SCHEMA_OUT}/summary.md")"
fi

STATUS="local-pass-with-external-blockers"
if [[ "${MANIFEST_EXIT}" != "0" || "${SCHEMA_EXIT}" != "0" ]]; then
  STATUS="failed"
fi

{
  echo "# Leona v0.4 Android Release Candidate Review"
  echo
  echo "- status: ${STATUS}"
  echo "- target release version: \`${TARGET_VERSION}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- release candidate manifest summary: \`${MANIFEST_SUMMARY}\`"
  echo "- release candidate manifest status: ${manifest_status:-missing}"
  echo "- release candidate manifest exit: ${MANIFEST_EXIT}"
  echo "- release candidate manifest schema summary: \`${SCHEMA_OUT}/summary.md\`"
  echo "- release candidate manifest schema status: ${schema_status:-missing}"
  echo "- release candidate manifest schema exit: ${SCHEMA_EXIT}"
  echo "- secret values printed: no"
  echo "- creates tag: no"
  echo "- triggers GitHub Actions: no"
  echo "- publishes artifacts: no"
  echo "- executes git add: no"
  echo "- starts paid devices or WeTest sessions: no"
  echo
  echo "## Failures"
  if [[ "${STATUS}" == "local-pass-with-external-blockers" ]]; then
    echo "- none"
  else
    if [[ "${MANIFEST_EXIT}" != "0" ]]; then
      echo "- release candidate manifest failed; see ${REPORT_DIR}/release-candidate-manifest.log"
    fi
    if [[ "${SCHEMA_EXIT}" != "0" ]]; then
      echo "- release candidate manifest schema failed; see ${REPORT_DIR}/release-candidate-manifest-schema.log"
    fi
  fi
} > "${REPORT_DIR}/summary.md"

echo "[release-candidate-review] summary: ${REPORT_DIR}/summary.md"

if [[ "${STATUS}" == "local-pass-with-external-blockers" ]]; then
  exit 0
fi
exit 1
