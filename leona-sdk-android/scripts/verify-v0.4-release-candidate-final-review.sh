#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_VERSION="${LEONA_TARGET_RELEASE_VERSION:-0.4.0}"
REPORT_DIR="${LEONA_V04_RELEASE_CANDIDATE_FINAL_REVIEW_OUT:-/tmp/leona-v0.4-release-candidate-final-review-$(date +%Y%m%d-%H%M%S)}"
REVIEW_OUT="${LEONA_V04_RELEASE_CANDIDATE_REVIEW_OUT:-${REPORT_DIR}/release-candidate-review}"
REVIEW_SCHEMA_OUT="${LEONA_V04_RELEASE_CANDIDATE_REVIEW_SCHEMA_OUT:-${REPORT_DIR}/release-candidate-review-schema}"

mkdir -p "${REPORT_DIR}" "${REVIEW_OUT}" "${REVIEW_SCHEMA_OUT}"

REVIEW_EXIT=0
REVIEW_SCHEMA_EXIT=0

echo "[release-candidate-final-review] Leona Android v0.4 release candidate final review"
echo "[release-candidate-final-review] target release version: ${TARGET_VERSION}"
echo "[release-candidate-final-review] report dir: ${REPORT_DIR}"
echo "[release-candidate-final-review] secret values are never printed by this script"
echo "[release-candidate-final-review] running release candidate review"

if env \
  LEONA_TARGET_RELEASE_VERSION="${TARGET_VERSION}" \
  LEONA_V04_RELEASE_CANDIDATE_REVIEW_OUT="${REVIEW_OUT}" \
  "${ROOT_DIR}/scripts/verify-v0.4-release-candidate-review.sh" \
  > "${REPORT_DIR}/release-candidate-review.log" 2>&1; then
  echo "[release-candidate-final-review] release candidate review: pass"
else
  REVIEW_EXIT=$?
  echo "[release-candidate-final-review] release candidate review: failed (${REVIEW_EXIT})"
fi

REVIEW_SUMMARY="${REVIEW_OUT}/summary.md"
if [[ -f "${REVIEW_SUMMARY}" ]]; then
  echo "[release-candidate-final-review] running release candidate review schema"
  if env \
    LEONA_TARGET_RELEASE_VERSION="${TARGET_VERSION}" \
    LEONA_V04_RELEASE_CANDIDATE_REVIEW_SCHEMA_OUT="${REVIEW_SCHEMA_OUT}" \
    "${ROOT_DIR}/scripts/verify-v0.4-release-candidate-review-schema.py" \
    "${REVIEW_SUMMARY}" \
    > "${REPORT_DIR}/release-candidate-review-schema.log" 2>&1; then
    echo "[release-candidate-final-review] release candidate review schema: pass"
  else
    REVIEW_SCHEMA_EXIT=$?
    echo "[release-candidate-final-review] release candidate review schema: failed (${REVIEW_SCHEMA_EXIT})"
  fi
else
  REVIEW_SCHEMA_EXIT=1
  echo "[release-candidate-final-review] release candidate review schema: skipped; summary missing"
fi

review_status="missing"
review_schema_status="missing"
if [[ -f "${REVIEW_SUMMARY}" ]]; then
  review_status="$(awk -F': ' '/^- status: / {print $2; exit}' "${REVIEW_SUMMARY}")"
fi
if [[ -f "${REVIEW_SCHEMA_OUT}/summary.md" ]]; then
  review_schema_status="$(awk -F': ' '/^- status: / {print $2; exit}' "${REVIEW_SCHEMA_OUT}/summary.md")"
fi

STATUS="local-pass-with-external-blockers"
if [[ "${REVIEW_EXIT}" != "0" || "${REVIEW_SCHEMA_EXIT}" != "0" ]]; then
  STATUS="failed"
fi

{
  echo "# Leona v0.4 Android Release Candidate Final Review"
  echo
  echo "- status: ${STATUS}"
  echo "- target release version: \`${TARGET_VERSION}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- release candidate review summary: \`${REVIEW_SUMMARY}\`"
  echo "- release candidate review status: ${review_status:-missing}"
  echo "- release candidate review exit: ${REVIEW_EXIT}"
  echo "- release candidate review schema summary: \`${REVIEW_SCHEMA_OUT}/summary.md\`"
  echo "- release candidate review schema status: ${review_schema_status:-missing}"
  echo "- release candidate review schema exit: ${REVIEW_SCHEMA_EXIT}"
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
    if [[ "${REVIEW_EXIT}" != "0" ]]; then
      echo "- release candidate review failed; see ${REPORT_DIR}/release-candidate-review.log"
    fi
    if [[ "${REVIEW_SCHEMA_EXIT}" != "0" ]]; then
      echo "- release candidate review schema failed; see ${REPORT_DIR}/release-candidate-review-schema.log"
    fi
  fi
} > "${REPORT_DIR}/summary.md"

echo "[release-candidate-final-review] summary: ${REPORT_DIR}/summary.md"

if [[ "${STATUS}" == "local-pass-with-external-blockers" ]]; then
  exit 0
fi
exit 1
