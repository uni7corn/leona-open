#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
REPORT_DIR="${LEONA_V04_PUBLIC_RELEASE_BATCH_OUT:-/tmp/leona-v0.4-public-release-batch-$(date +%Y%m%d-%H%M%S)}"
SCOPE_DIR="${REPORT_DIR}/public-commit-scope"
MODE="${LEONA_PUBLIC_RELEASE_BATCH_SCOPE_MODE:-working-tree}"
STAGE_DRY_RUN="${LEONA_ANDROID_STAGE_DRY_RUN:-1}"
SUMMARY_PATH="${REPORT_DIR}/summary.md"

STATUS=0
PASS_COUNT=0
FAILURES=()
WARNINGS=()

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

count_lines() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    wc -l < "${file}" | tr -d ' '
  else
    echo "0"
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

cd "${REPO_DIR}"

echo "[v0.4-public-release-batch] generating public Android release batch plan"
echo "[v0.4-public-release-batch] mode: ${MODE}"
echo "[v0.4-public-release-batch] stage dry-run: ${STAGE_DRY_RUN}"
echo "[v0.4-public-release-batch] report dir: ${REPORT_DIR}"
echo "[v0.4-public-release-batch] secret values are never printed by this script"

if [[ "${STAGE_DRY_RUN}" != "0" && "${STAGE_DRY_RUN}" != "1" ]]; then
  fail "LEONA_ANDROID_STAGE_DRY_RUN must be 0 or 1."
fi

if ! env LEONA_PUBLIC_COMMIT_SCOPE_MODE="${MODE}" \
    LEONA_V04_PUBLIC_COMMIT_SCOPE_OUT="${SCOPE_DIR}" \
    "${ROOT_DIR}/scripts/verify-v0.4-public-commit-scope.sh" \
    > "${REPORT_DIR}/public-commit-scope.txt" 2>&1; then
  fail "public commit scope gate failed; see ${REPORT_DIR}/public-commit-scope.txt"
fi

PUBLIC_PATHS="${SCOPE_DIR}/public-candidate-paths.txt"
NON_PUBLIC_PATHS="${SCOPE_DIR}/non-public-dirty-paths.txt"
STAGED_FORBIDDEN_PATHS="${SCOPE_DIR}/staged-forbidden-paths.txt"

touch "${PUBLIC_PATHS}" "${NON_PUBLIC_PATHS}" "${STAGED_FORBIDDEN_PATHS}"

cp "${PUBLIC_PATHS}" "${REPORT_DIR}/public-release-batch-paths.txt"
cp "${NON_PUBLIC_PATHS}" "${REPORT_DIR}/do-not-stage-paths.txt"
cp "${STAGED_FORBIDDEN_PATHS}" "${REPORT_DIR}/staged-forbidden-paths.txt"

PUBLIC_COUNT="$(count_lines "${REPORT_DIR}/public-release-batch-paths.txt")"
NON_PUBLIC_COUNT="$(count_lines "${REPORT_DIR}/do-not-stage-paths.txt")"
STAGED_FORBIDDEN_COUNT="$(count_lines "${REPORT_DIR}/staged-forbidden-paths.txt")"
PUBLIC_PATHS_SHA256="$(file_sha256 "${REPORT_DIR}/public-release-batch-paths.txt")"
DO_NOT_STAGE_PATHS_SHA256="$(file_sha256 "${REPORT_DIR}/do-not-stage-paths.txt")"
STAGED_FORBIDDEN_PATHS_SHA256="$(file_sha256 "${REPORT_DIR}/staged-forbidden-paths.txt")"

if [[ "${STAGED_FORBIDDEN_COUNT}" == "0" ]]; then
  pass "no forbidden paths are currently staged"
else
  fail "forbidden paths are currently staged; see ${REPORT_DIR}/staged-forbidden-paths.txt"
fi

if [[ "${PUBLIC_COUNT}" == "0" ]]; then
  warn "no public Android release batch paths were detected"
else
  pass "public Android release batch paths detected: ${PUBLIC_COUNT}"
fi

if [[ "${NON_PUBLIC_COUNT}" == "0" ]]; then
  pass "no non-public dirty paths detected"
else
  warn "non-public dirty paths detected; keep them out of the public Android commit"
fi

{
  echo "#!/usr/bin/env bash"
  echo "set -euo pipefail"
  echo
  echo "# Review ${REPORT_DIR}/summary.md before running."
  echo "# This file is generated for convenience. The verifier only executes it with"
  echo "# LEONA_ANDROID_STAGE_DRY_RUN=1 to prove the path list is stageable without"
  echo "# modifying the git index."
  echo "DRY_RUN=\"\${LEONA_ANDROID_STAGE_DRY_RUN:-0}\""
  echo "if [[ \"\${DRY_RUN}\" != \"0\" && \"\${DRY_RUN}\" != \"1\" ]]; then"
  echo "  echo \"LEONA_ANDROID_STAGE_DRY_RUN must be 0 or 1\" >&2"
  echo "  exit 2"
  echo "fi"
  echo "while IFS= read -r path; do"
  echo "  [[ -z \"\${path}\" ]] && continue"
  echo "  if [[ \"\${DRY_RUN}\" == \"1\" ]]; then"
  echo "    git add --dry-run -- \"\${path}\""
  echo "  else"
  echo "    git add -- \"\${path}\""
  echo "  fi"
  echo "done <<'LEONA_PUBLIC_RELEASE_BATCH_PATHS'"
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    printf '%s\n' "${path}"
  done < "${REPORT_DIR}/public-release-batch-paths.txt"
  echo "LEONA_PUBLIC_RELEASE_BATCH_PATHS"
  echo
} > "${REPORT_DIR}/stage-public-release-batch.sh"
chmod +x "${REPORT_DIR}/stage-public-release-batch.sh"

STAGE_DRAFT_SYNTAX="not_checked"
if bash -n "${REPORT_DIR}/stage-public-release-batch.sh" > "${REPORT_DIR}/stage-public-release-batch.syntax.txt" 2>&1; then
  STAGE_DRAFT_SYNTAX="pass"
  pass "stage command draft syntax is valid"
else
  STAGE_DRAFT_SYNTAX="failed"
  fail "stage command draft syntax failed; see ${REPORT_DIR}/stage-public-release-batch.syntax.txt"
fi

STAGE_DRAFT_PATHS="${REPORT_DIR}/stage-command-draft-paths.txt"
STAGE_DRAFT_DO_NOT_STAGE_OVERLAP="${REPORT_DIR}/stage-command-draft-do-not-stage-overlap.txt"
awk '
  /^done <<'\''LEONA_PUBLIC_RELEASE_BATCH_PATHS'\''$/ { in_paths=1; next }
  /^LEONA_PUBLIC_RELEASE_BATCH_PATHS$/ { in_paths=0; next }
  in_paths { print }
' "${REPORT_DIR}/stage-public-release-batch.sh" > "${STAGE_DRAFT_PATHS}"
touch "${STAGE_DRAFT_DO_NOT_STAGE_OVERLAP}"

STAGE_DRAFT_PATH_COUNT="$(count_lines "${STAGE_DRAFT_PATHS}")"
STAGE_DRAFT_PATHS_SHA256="$(file_sha256 "${STAGE_DRAFT_PATHS}")"
STAGE_DRAFT_MATCHES_PUBLIC_BATCH="no"
STAGE_DRAFT_CONTAINS_DO_NOT_STAGE="no"
STAGE_DRY_RUN_STATUS="skipped"
STAGE_DRY_RUN_INDEX_PRESERVED="skipped"
STAGE_DRY_RUN_LOG="${REPORT_DIR}/stage-command-dry-run.txt"
STAGE_DRY_RUN_INDEX_BEFORE="${REPORT_DIR}/stage-command-dry-run-index-before.txt"
STAGE_DRY_RUN_INDEX_AFTER="${REPORT_DIR}/stage-command-dry-run-index-after.txt"

if cmp -s "${STAGE_DRAFT_PATHS}" "${REPORT_DIR}/public-release-batch-paths.txt"; then
  STAGE_DRAFT_MATCHES_PUBLIC_BATCH="yes"
  pass "stage command draft paths match public release batch paths"
else
  fail "stage command draft paths differ from public release batch paths"
fi

if [[ "${NON_PUBLIC_COUNT}" != "0" ]] && grep -Fxf "${REPORT_DIR}/do-not-stage-paths.txt" "${STAGE_DRAFT_PATHS}" > "${STAGE_DRAFT_DO_NOT_STAGE_OVERLAP}"; then
  STAGE_DRAFT_CONTAINS_DO_NOT_STAGE="yes"
  fail "stage command draft contains do-not-stage paths; see ${STAGE_DRAFT_DO_NOT_STAGE_OVERLAP}"
else
  : > "${STAGE_DRAFT_DO_NOT_STAGE_OVERLAP}"
  pass "stage command draft excludes do-not-stage paths"
fi

if [[ "${STAGE_DRY_RUN}" == "1" ]]; then
  git diff --cached --name-status > "${STAGE_DRY_RUN_INDEX_BEFORE}"
  if env LEONA_ANDROID_STAGE_DRY_RUN=1 "${REPORT_DIR}/stage-public-release-batch.sh" > "${STAGE_DRY_RUN_LOG}" 2>&1; then
    STAGE_DRY_RUN_STATUS="pass"
    pass "stage command dry-run completed without modifying files"
  else
    STAGE_DRY_RUN_STATUS="failed"
    fail "stage command dry-run failed; see ${STAGE_DRY_RUN_LOG}"
  fi
  git diff --cached --name-status > "${STAGE_DRY_RUN_INDEX_AFTER}"
  if cmp -s "${STAGE_DRY_RUN_INDEX_BEFORE}" "${STAGE_DRY_RUN_INDEX_AFTER}"; then
    STAGE_DRY_RUN_INDEX_PRESERVED="yes"
    pass "stage command dry-run preserved git index"
  else
    STAGE_DRY_RUN_INDEX_PRESERVED="no"
    fail "stage command dry-run changed git index; inspect ${STAGE_DRY_RUN_INDEX_BEFORE} and ${STAGE_DRY_RUN_INDEX_AFTER}"
  fi
else
  : > "${STAGE_DRY_RUN_LOG}"
  : > "${STAGE_DRY_RUN_INDEX_BEFORE}"
  : > "${STAGE_DRY_RUN_INDEX_AFTER}"
fi

{
  echo "# Leona v0.4 Public Android Release Batch Plan"
  echo
  if [[ "${STATUS}" == "0" ]]; then
    if [[ "${NON_PUBLIC_COUNT}" == "0" ]]; then
      SUMMARY_STATUS="pass"
    else
      SUMMARY_STATUS="local-pass-with-non-public-dirty-paths"
    fi
  else
    SUMMARY_STATUS="failed"
  fi
  echo "- status: ${SUMMARY_STATUS}"
  echo "- mode: \`${MODE}\`"
  echo "- report dir: \`${REPORT_DIR}\`"
  echo "- secret values printed: no"
  echo "- executes git add: no"
  echo "- executes real git add: no"
  echo "- stage command dry-run enabled: ${STAGE_DRY_RUN}"
  echo "- public release batch paths: ${PUBLIC_COUNT}"
  echo "- do-not-stage paths: ${NON_PUBLIC_COUNT}"
  echo "- staged forbidden paths: ${STAGED_FORBIDDEN_COUNT}"
  echo "- public release batch paths sha256: \`${PUBLIC_PATHS_SHA256}\`"
  echo "- do-not-stage paths sha256: \`${DO_NOT_STAGE_PATHS_SHA256}\`"
  echo "- staged forbidden paths sha256: \`${STAGED_FORBIDDEN_PATHS_SHA256}\`"
  echo "- stage command draft syntax: ${STAGE_DRAFT_SYNTAX}"
  echo "- stage command draft paths: ${STAGE_DRAFT_PATH_COUNT}"
  echo "- stage command draft paths sha256: \`${STAGE_DRAFT_PATHS_SHA256}\`"
  echo "- stage command draft matches public batch: ${STAGE_DRAFT_MATCHES_PUBLIC_BATCH}"
  echo "- stage command draft contains do-not-stage paths: ${STAGE_DRAFT_CONTAINS_DO_NOT_STAGE}"
  echo "- stage command dry-run: ${STAGE_DRY_RUN_STATUS}"
  echo "- stage command dry-run preserves index: ${STAGE_DRY_RUN_INDEX_PRESERVED}"
  echo "- local pass checks: ${PASS_COUNT}"
  echo
  echo "## Files"
  echo "- public release batch paths: \`${REPORT_DIR}/public-release-batch-paths.txt\`"
  echo "- do-not-stage paths: \`${REPORT_DIR}/do-not-stage-paths.txt\`"
  echo "- staged forbidden paths: \`${REPORT_DIR}/staged-forbidden-paths.txt\`"
  echo "- stage command draft: \`${REPORT_DIR}/stage-public-release-batch.sh\`"
  echo "- stage command draft syntax log: \`${REPORT_DIR}/stage-public-release-batch.syntax.txt\`"
  echo "- stage command draft paths: \`${STAGE_DRAFT_PATHS}\`"
  echo "- stage command draft do-not-stage overlap: \`${STAGE_DRAFT_DO_NOT_STAGE_OVERLAP}\`"
  echo "- stage command dry-run log: \`${STAGE_DRY_RUN_LOG}\`"
  echo "- stage command dry-run index before: \`${STAGE_DRY_RUN_INDEX_BEFORE}\`"
  echo "- stage command dry-run index after: \`${STAGE_DRY_RUN_INDEX_AFTER}\`"
  echo "- public commit scope summary: \`${SCOPE_DIR}/summary.md\`"
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
  echo "## Rule"
  echo "- This script never stages, commits, tags, publishes, starts devices, or prints secrets."
  echo "- Use the generated path lists to keep iOS, Web, server, homepage, deployment, policy, private detector, and internal docs out of Android public GitHub commits."
} > "${SUMMARY_PATH}"

echo "[v0.4-public-release-batch] summary: ${SUMMARY_PATH}"
exit "${STATUS}"
