#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
VERSION="${LEONA_SDK_VERSION:-$(grep '^VERSION_NAME=' "${ROOT_DIR}/gradle.properties" | cut -d= -f2-)}"
TARGET_RELEASE_VERSION="${LEONA_TARGET_RELEASE_VERSION:-0.4.0}"
REQUIRE_PRETAG_READY="${LEONA_REQUIRE_PRETAG_READY:-0}"
SELF_SCAN_TEST="${LEONA_RC_SELF_SCAN_TEST:-0}"
REPORT_DIR="${LEONA_V04_RELEASE_CANDIDATE_OUT:-/tmp/leona-v0.4-release-candidate-$(date +%Y%m%d-%H%M%S)}"
SUMMARY_PATH="${REPORT_DIR}/summary.md"
EVIDENCE_PACK_MD="${REPORT_DIR}/release-evidence-pack.md"
EVIDENCE_PACK_JSON="${REPORT_DIR}/release-evidence-pack.json"
EVIDENCE_PACK_REDACTION_LOG="${REPORT_DIR}/release-evidence-pack-redaction-scan.txt"
EVIDENCE_PACK_SCHEMA_DIR="${REPORT_DIR}/release-evidence-pack-schema"
GIT_INDEX_BEFORE="${REPORT_DIR}/git-index-before.txt"
GIT_INDEX_AFTER="${REPORT_DIR}/git-index-after.txt"

STATUS=0
FAILURES=()
PRE_TAG_BLOCKERS=()

mkdir -p "${REPORT_DIR}"

run_gate() {
  local label="$1"
  local output_name="$2"
  shift 2
  echo "[release-candidate] running ${label}"
  if "$@" > "${REPORT_DIR}/${output_name}.txt" 2>&1; then
    echo "[release-candidate] ${label}: pass"
  else
    STATUS=1
    FAILURES+=("${label} failed; see ${REPORT_DIR}/${output_name}.txt")
    echo "[release-candidate] ${label}: failed" >&2
  fi
}

summary_value() {
  local file="$1"
  local label="$2"
  if [[ -f "${file}" ]]; then
    grep -E "^- ${label}:" "${file}" | head -n 1 | sed -E "s/^- ${label}: //"
  fi
}

section_items() {
  local file="$1"
  local heading="$2"
  if [[ -f "${file}" ]]; then
    awk -v heading="${heading}" '
      $0 == "## " heading { in_section=1; next }
      in_section && /^## / { exit }
      in_section && /^- / { print }
    ' "${file}"
  fi
}

file_sha256() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    echo ""
  fi
}

file_bytes() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    wc -c < "${file}" | tr -d ' '
  else
    echo "0"
  fi
}

cd "${REPO_DIR}"
git diff --cached --name-status > "${GIT_INDEX_BEFORE}"

echo "[release-candidate] Leona Android v0.4 release candidate manifest"
echo "[release-candidate] SDK coordinate version: ${VERSION}"
echo "[release-candidate] target release version: ${TARGET_RELEASE_VERSION}"
echo "[release-candidate] require pre-tag ready: ${REQUIRE_PRETAG_READY}"
echo "[release-candidate] report dir: ${REPORT_DIR}"
echo "[release-candidate] secret values are never printed by this script"

if [[ "${REQUIRE_PRETAG_READY}" != "0" && "${REQUIRE_PRETAG_READY}" != "1" ]]; then
  STATUS=1
  FAILURES+=("LEONA_REQUIRE_PRETAG_READY must be 0 or 1.")
fi

if [[ "${SELF_SCAN_TEST}" != "0" && "${SELF_SCAN_TEST}" != "1" ]]; then
  STATUS=1
  FAILURES+=("LEONA_RC_SELF_SCAN_TEST must be 0 or 1.")
fi

if [[ "${VERSION}" != "${TARGET_RELEASE_VERSION}" ]]; then
  PRE_TAG_BLOCKERS+=("Android SDK coordinate is ${VERSION}; bump VERSION_NAME to ${TARGET_RELEASE_VERSION} before cutting a real v${TARGET_RELEASE_VERSION} tag.")
fi

if [[ "${REQUIRE_PRETAG_READY}" == "1" && ${#PRE_TAG_BLOCKERS[@]} -gt 0 ]]; then
  STATUS=1
  FAILURES+=("pre-tag readiness required but blockers remain")
fi

READINESS_DIR="${REPORT_DIR}/readiness"
ARCHIVE_CONSUMER_DIR="${REPORT_DIR}/archive-consumer"
PUBLISH_WORKFLOW_DIR="${REPORT_DIR}/publish-workflow"
PUBLIC_COMMIT_SCOPE_DIR="${REPORT_DIR}/public-commit-scope"
PUBLIC_RELEASE_BATCH_DIR="${REPORT_DIR}/public-release-batch"
PUBLIC_RELEASE_BATCH_SCHEMA_DIR="${REPORT_DIR}/public-release-batch-schema"
VERSION_BUMP_PLAN_DIR="${REPORT_DIR}/version-bump-plan"
VERSION_BUMP_DRY_RUN_DIR="${REPORT_DIR}/version-bump-dry-run"

run_gate "v0.4 release readiness" \
  "release-readiness" \
  env LEONA_TARGET_RELEASE_VERSION="${TARGET_RELEASE_VERSION}" \
    LEONA_V04_READINESS_OUT="${READINESS_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-release-readiness.sh"

run_gate "v0.4 public archive consumer smoke" \
  "public-archive-consumer" \
  env LEONA_V04_PUBLIC_ARCHIVE_CONSUMER_OUT="${ARCHIVE_CONSUMER_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-public-archive-consumer.sh"

run_gate "v0.4 publish workflow dry-run" \
  "publish-workflow" \
  env LEONA_TARGET_RELEASE_VERSION="${TARGET_RELEASE_VERSION}" \
    LEONA_V04_PUBLISH_WORKFLOW_OUT="${PUBLISH_WORKFLOW_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-publish-workflow-dry-run.sh"

run_gate "v0.4 public commit scope gate" \
  "public-commit-scope" \
  env LEONA_V04_PUBLIC_COMMIT_SCOPE_OUT="${PUBLIC_COMMIT_SCOPE_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-public-commit-scope.sh"

run_gate "v0.4 public release batch planner" \
  "public-release-batch" \
  env LEONA_V04_PUBLIC_RELEASE_BATCH_OUT="${PUBLIC_RELEASE_BATCH_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-public-release-batch.sh"

run_gate "v0.4 public release batch schema" \
  "public-release-batch-schema" \
  env LEONA_V04_PUBLIC_RELEASE_BATCH_SCHEMA_OUT="${PUBLIC_RELEASE_BATCH_SCHEMA_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-public-release-batch-schema.py" \
    "${PUBLIC_RELEASE_BATCH_DIR}/summary.md"

run_gate "v0.4 version bump plan" \
  "version-bump-plan" \
  env LEONA_TARGET_RELEASE_VERSION="${TARGET_RELEASE_VERSION}" \
    LEONA_ANDROID_VERSION_BUMP_PLAN_OUT="${VERSION_BUMP_PLAN_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-version-bump-plan.py"

run_gate "v0.4 version bump dry-run" \
  "version-bump-dry-run" \
  env LEONA_TARGET_RELEASE_VERSION="${TARGET_RELEASE_VERSION}" \
    LEONA_ANDROID_VERSION_BUMP_DRY_RUN_OUT="${VERSION_BUMP_DRY_RUN_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-version-bump-dry-run.py"

git diff --cached --name-status > "${GIT_INDEX_AFTER}"
GIT_INDEX_PRESERVED="yes"
if ! cmp -s "${GIT_INDEX_BEFORE}" "${GIT_INDEX_AFTER}"; then
  GIT_INDEX_PRESERVED="no"
  STATUS=1
  FAILURES+=("release candidate modified the git index; compare ${GIT_INDEX_BEFORE} and ${GIT_INDEX_AFTER}")
fi

READINESS_SUMMARY="${READINESS_DIR}/summary.md"
ARCHIVE_CONSUMER_SUMMARY="${ARCHIVE_CONSUMER_DIR}/summary.md"
PUBLISH_WORKFLOW_SUMMARY="${PUBLISH_WORKFLOW_DIR}/summary.md"
PUBLIC_COMMIT_SCOPE_SUMMARY="${PUBLIC_COMMIT_SCOPE_DIR}/summary.md"
PUBLIC_RELEASE_BATCH_SUMMARY="${PUBLIC_RELEASE_BATCH_DIR}/summary.md"
PUBLIC_RELEASE_BATCH_SCHEMA_SUMMARY="${PUBLIC_RELEASE_BATCH_SCHEMA_DIR}/summary.md"
VERSION_BUMP_PLAN_SUMMARY="${VERSION_BUMP_PLAN_DIR}/summary.md"
VERSION_BUMP_DRY_RUN_SUMMARY="${VERSION_BUMP_DRY_RUN_DIR}/summary.md"

COMPONENT_NAMES=(
  "release readiness"
  "archive consumer"
  "publish workflow"
  "public commit scope"
  "public release batch"
  "public release batch schema"
  "version bump plan"
  "version bump dry-run"
)
COMPONENT_FILES=(
  "${READINESS_SUMMARY}"
  "${ARCHIVE_CONSUMER_SUMMARY}"
  "${PUBLISH_WORKFLOW_SUMMARY}"
  "${PUBLIC_COMMIT_SCOPE_SUMMARY}"
  "${PUBLIC_RELEASE_BATCH_SUMMARY}"
  "${PUBLIC_RELEASE_BATCH_SCHEMA_SUMMARY}"
  "${VERSION_BUMP_PLAN_SUMMARY}"
  "${VERSION_BUMP_DRY_RUN_SUMMARY}"
)

REDACTION_PATTERN='BEGIN (RSA |EC |OPENSSH |PRIVATE )?KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|LEONA_[A-Z0-9_]*(SECRET|TOKEN|KEY)[A-Z0-9_]*=[^[:space:]]+|SecretKey[[:space:]]*[:=][[:space:]]*[^[:space:]`]+|[0-9A-HJKMNP-TV-Z]{26}'
REDACTION_STATUS="pass"

scan_redaction_target() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    if grep -nE "${REDACTION_PATTERN}" "${file}" >> "${EVIDENCE_PACK_REDACTION_LOG}" 2>/dev/null; then
      REDACTION_STATUS="failed"
    fi
  fi
}

write_evidence_pack() {
  {
    echo "# Leona v0.4 Android Release Evidence Pack"
    echo
    echo "- target release version: \`${TARGET_RELEASE_VERSION}\`"
    echo "- SDK coordinate version: \`${VERSION}\`"
    echo "- generated by: \`verify-v0.4-release-candidate-manifest.sh\`"
    echo "- report dir: \`${REPORT_DIR}\`"
    echo "- secret values printed: no"
    echo "- redaction scan: ${REDACTION_STATUS}"
    echo "- redaction scan log: \`${EVIDENCE_PACK_REDACTION_LOG}\`"
    echo "- git index preserved: ${GIT_INDEX_PRESERVED}"
    echo
    echo "## Component Summaries"
    for i in "${!COMPONENT_NAMES[@]}"; do
      name="${COMPONENT_NAMES[$i]}"
      file="${COMPONENT_FILES[$i]}"
      echo "- ${name}: path=\`${file}\`, sha256=\`$(file_sha256 "${file}")\`, bytes=$(file_bytes "${file}")"
    done
    echo
    echo "## Git Index Snapshots"
    echo "- before: path=\`${GIT_INDEX_BEFORE}\`, sha256=\`$(file_sha256 "${GIT_INDEX_BEFORE}")\`, bytes=$(file_bytes "${GIT_INDEX_BEFORE}")"
    echo "- after: path=\`${GIT_INDEX_AFTER}\`, sha256=\`$(file_sha256 "${GIT_INDEX_AFTER}")\`, bytes=$(file_bytes "${GIT_INDEX_AFTER}")"
    echo
    echo "## Rule"
    echo "- This evidence pack indexes local pre-tag summaries only."
    echo "- It does not create tags, publish artifacts, stage files, start devices, or print secrets."
  } > "${EVIDENCE_PACK_MD}"

  {
    echo "{"
    echo "  \"targetReleaseVersion\": \"${TARGET_RELEASE_VERSION}\","
    echo "  \"sdkCoordinateVersion\": \"${VERSION}\","
    echo "  \"reportDir\": \"${REPORT_DIR}\","
    echo "  \"secretValuesPrinted\": false,"
    echo "  \"redactionScan\": \"${REDACTION_STATUS}\","
    echo "  \"redactionScanLog\": \"${EVIDENCE_PACK_REDACTION_LOG}\","
    echo "  \"gitIndexPreserved\": \"${GIT_INDEX_PRESERVED}\","
    echo "  \"gitIndex\": {"
    echo "    \"beforePath\": \"${GIT_INDEX_BEFORE}\","
    echo "    \"beforeSha256\": \"$(file_sha256 "${GIT_INDEX_BEFORE}")\","
    echo "    \"beforeBytes\": $(file_bytes "${GIT_INDEX_BEFORE}"),"
    echo "    \"afterPath\": \"${GIT_INDEX_AFTER}\","
    echo "    \"afterSha256\": \"$(file_sha256 "${GIT_INDEX_AFTER}")\","
    echo "    \"afterBytes\": $(file_bytes "${GIT_INDEX_AFTER}")"
    echo "  },"
    echo "  \"components\": ["
    for i in "${!COMPONENT_NAMES[@]}"; do
      name="${COMPONENT_NAMES[$i]}"
      file="${COMPONENT_FILES[$i]}"
      comma=","
      if [[ "${i}" == "$((${#COMPONENT_NAMES[@]} - 1))" ]]; then
        comma=""
      fi
      echo "    {\"name\": \"${name}\", \"summaryPath\": \"${file}\", \"sha256\": \"$(file_sha256 "${file}")\", \"bytes\": $(file_bytes "${file}")}${comma}"
    done
    echo "  ]"
    echo "}"
  } > "${EVIDENCE_PACK_JSON}"
}

: > "${EVIDENCE_PACK_REDACTION_LOG}"
for component_file in "${COMPONENT_FILES[@]}"; do
  scan_redaction_target "${component_file}"
done
scan_redaction_target "${GIT_INDEX_BEFORE}"
scan_redaction_target "${GIT_INDEX_AFTER}"

write_evidence_pack
if [[ "${SELF_SCAN_TEST}" == "1" ]]; then
  echo "synthetic-redaction-marker: LEONA_RC_SELF_SCAN_SECRET=synthetic" >> "${EVIDENCE_PACK_MD}"
fi
scan_redaction_target "${EVIDENCE_PACK_MD}"
scan_redaction_target "${EVIDENCE_PACK_JSON}"

if [[ "${REDACTION_STATUS}" == "pass" ]]; then
  : > "${EVIDENCE_PACK_REDACTION_LOG}"
else
  STATUS=1
  FAILURES+=("release evidence pack redaction scan failed; see ${EVIDENCE_PACK_REDACTION_LOG}")
fi

write_evidence_pack

EVIDENCE_PACK_SCHEMA_SUMMARY="${EVIDENCE_PACK_SCHEMA_DIR}/summary.md"
run_gate "v0.4 release evidence pack schema" \
  "release-evidence-pack-schema" \
  env LEONA_TARGET_RELEASE_VERSION="${TARGET_RELEASE_VERSION}" \
    LEONA_V04_EVIDENCE_PACK_SCHEMA_OUT="${EVIDENCE_PACK_SCHEMA_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-release-evidence-pack-schema.py" \
    "${EVIDENCE_PACK_JSON}"

{
  echo "# Leona v0.4 Android Release Candidate Manifest"
  echo
  echo "- status: $([[ "${STATUS}" == "0" ]] && echo "local-pass-with-external-blockers" || echo "failed")"
  echo "- target release version: \`${TARGET_RELEASE_VERSION}\`"
  echo "- SDK coordinate version: \`${VERSION}\`"
  echo "- require pre-tag ready: \`${REQUIRE_PRETAG_READY}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- secret values printed: no"
  echo "- creates tag: no"
  echo "- triggers GitHub Actions: no"
  echo "- publishes artifacts: no"
  echo "- executes git add: no"
  echo "- starts paid devices or WeTest sessions: no"
  echo "- release evidence pack: \`${EVIDENCE_PACK_MD}\`"
  echo "- release evidence pack json: \`${EVIDENCE_PACK_JSON}\`"
  echo "- release evidence pack redaction scan: ${REDACTION_STATUS}"
  echo "- release evidence pack schema summary: \`${EVIDENCE_PACK_SCHEMA_SUMMARY}\`"
  echo "- release evidence pack schema status: $(summary_value "${EVIDENCE_PACK_SCHEMA_SUMMARY}" "status")"
  echo "- release candidate preserves git index: ${GIT_INDEX_PRESERVED}"
  echo "- git index before: \`${GIT_INDEX_BEFORE}\`"
  echo "- git index after: \`${GIT_INDEX_AFTER}\`"
  echo
  echo "## Component Summaries"
  echo "- release readiness summary: \`${READINESS_SUMMARY}\`"
  echo "- release readiness status: $(summary_value "${READINESS_SUMMARY}" "status")"
  echo "- release readiness local pass checks: $(summary_value "${READINESS_SUMMARY}" "local pass checks")"
  echo "- archive consumer summary: \`${ARCHIVE_CONSUMER_SUMMARY}\`"
  echo "- archive consumer status: $(summary_value "${ARCHIVE_CONSUMER_SUMMARY}" "status")"
  echo "- archive sha256: $(summary_value "${ARCHIVE_CONSUMER_SUMMARY}" "archive sha256")"
  echo "- archive file count: $(summary_value "${ARCHIVE_CONSUMER_SUMMARY}" "file count")"
  echo "- publish workflow summary: \`${PUBLISH_WORKFLOW_SUMMARY}\`"
  echo "- publish workflow status: $(summary_value "${PUBLISH_WORKFLOW_SUMMARY}" "status")"
  echo "- expected AAR asset: $(summary_value "${PUBLISH_WORKFLOW_SUMMARY}" "expected AAR asset")"
  echo "- expected checksum asset: $(summary_value "${PUBLISH_WORKFLOW_SUMMARY}" "expected checksum asset")"
  echo "- public commit scope summary: \`${PUBLIC_COMMIT_SCOPE_SUMMARY}\`"
  echo "- public commit scope status: $(summary_value "${PUBLIC_COMMIT_SCOPE_SUMMARY}" "status")"
  echo "- staged forbidden paths: $(summary_value "${PUBLIC_COMMIT_SCOPE_SUMMARY}" "staged forbidden paths")"
  echo "- non-public dirty paths: $(summary_value "${PUBLIC_COMMIT_SCOPE_SUMMARY}" "non-public dirty paths")"
  echo "- public release batch summary: \`${PUBLIC_RELEASE_BATCH_SUMMARY}\`"
  echo "- public release batch status: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "status")"
  echo "- public release batch paths: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "public release batch paths")"
  echo "- public release batch do-not-stage paths: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "do-not-stage paths")"
  echo "- public release batch staged forbidden paths: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "staged forbidden paths")"
  echo "- public release batch paths sha256: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "public release batch paths sha256")"
  echo "- public release batch do-not-stage paths sha256: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "do-not-stage paths sha256")"
  echo "- public release batch staged forbidden paths sha256: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "staged forbidden paths sha256")"
  echo "- public release batch stage command draft syntax: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command draft syntax")"
  echo "- public release batch stage command draft paths: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command draft paths")"
  echo "- public release batch stage command draft paths sha256: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command draft paths sha256")"
  echo "- public release batch stage command draft matches public batch: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command draft matches public batch")"
  echo "- public release batch stage command draft contains do-not-stage paths: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command draft contains do-not-stage paths")"
  echo "- public release batch stage command dry-run: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command dry-run")"
  echo "- public release batch stage command dry-run preserves index: $(summary_value "${PUBLIC_RELEASE_BATCH_SUMMARY}" "stage command dry-run preserves index")"
  echo "- public release batch schema summary: \`${PUBLIC_RELEASE_BATCH_SCHEMA_SUMMARY}\`"
  echo "- public release batch schema status: $(summary_value "${PUBLIC_RELEASE_BATCH_SCHEMA_SUMMARY}" "status")"
  echo "- version bump plan summary: \`${VERSION_BUMP_PLAN_SUMMARY}\`"
  echo "- version bump plan status: $(summary_value "${VERSION_BUMP_PLAN_SUMMARY}" "status")"
  echo "- version bump plan current VERSION_NAME: $(summary_value "${VERSION_BUMP_PLAN_SUMMARY}" "current VERSION_NAME")"
  echo "- version bump plan target version: $(summary_value "${VERSION_BUMP_PLAN_SUMMARY}" "target version")"
  echo "- version bump dry-run summary: \`${VERSION_BUMP_DRY_RUN_SUMMARY}\`"
  echo "- version bump dry-run status: $(summary_value "${VERSION_BUMP_DRY_RUN_SUMMARY}" "status")"
  echo "- version bump dry-run current VERSION_NAME: $(summary_value "${VERSION_BUMP_DRY_RUN_SUMMARY}" "current VERSION_NAME")"
  echo "- version bump dry-run target version: $(summary_value "${VERSION_BUMP_DRY_RUN_SUMMARY}" "target version")"
  echo
  echo "## Failures"
  if (( ${#FAILURES[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${FAILURES[@]}"
  fi
  echo
  echo "## Pre-Tag Blockers"
  if (( ${#PRE_TAG_BLOCKERS[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${PRE_TAG_BLOCKERS[@]}"
  fi
  echo
  echo "## External Blockers"
  readiness_blockers="$(section_items "${READINESS_SUMMARY}" "External Blockers" || true)"
  publish_blockers="$(section_items "${PUBLISH_WORKFLOW_SUMMARY}" "External Blockers" || true)"
  if [[ -z "${readiness_blockers}${publish_blockers}" ]]; then
    echo "- none"
  else
    if [[ -n "${readiness_blockers}" ]]; then
      echo "${readiness_blockers}"
    fi
    if [[ -n "${publish_blockers}" ]]; then
      echo "${publish_blockers}"
    fi
  fi
  echo
  echo "## Release Candidate Rule"
  echo "- This manifest is sufficient for local public-safe pre-tag review only."
  echo "- Real v0.4 release still requires a pushed tag workflow, post-release consumer smoke, and explicit handling of remaining external blockers."
} > "${SUMMARY_PATH}"

echo "[release-candidate] summary: ${SUMMARY_PATH}"
exit "${STATUS}"
