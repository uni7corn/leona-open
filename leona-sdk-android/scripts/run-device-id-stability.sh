#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
SERIAL="${ANDROID_SERIAL:-${ADB_SERIAL:-}}"
APK="${LEONA_APK:-}"
PACKAGE="${LEONA_PACKAGE:-io.leonasec.leona.sample}"
OUT_DIR="${LEONA_STABILITY_OUT:-/tmp/leona-device-id-stability-$(date +%Y%m%d-%H%M%S)}"
COLLECTION_SCRIPT="${LEONA_COLLECTION_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-cloud-device-collection.sh}"
CLOUD_TEST_TOKEN="${LEONA_CLOUD_TEST_TOKEN:-}"
PHASES="${LEONA_STABILITY_PHASES:-initial,clear_data,reinstall,reboot}"
SENSE_WAIT_SECONDS="${LEONA_SENSE_WAIT_SECONDS:-18}"

adb_cmd() {
  if [[ -n "${SERIAL}" ]]; then
    "${ADB}" -s "${SERIAL}" "$@"
  else
    "${ADB}" "$@"
  fi
}

sha256_text() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

boxid_hint() {
  local value="$1"
  if (( ${#value} <= 12 )); then
    printf '<redacted:%s>' "$(sha256_text "${value}" | cut -c1-16)"
  else
    printf '%s...%s' "${value:0:6}" "${value: -4}"
  fi
}

extract_first_json_value() {
  local key="$1"
  local file="$2"
  grep -Eo "\"${key}\":\"[^\"]+\"" "${file}" 2>/dev/null | head -1 | cut -d'"' -f4 || true
}

redact_phase_boxids() {
  local phase_dir="$1"
  local logcat="${phase_dir}/logcat.leona.txt"
  [[ -f "${logcat}" ]] || return 0

  local box_id hint escaped
  while IFS= read -r box_id; do
    [[ -n "${box_id}" ]] || continue
    hint="$(boxid_hint "${box_id}")"
    escaped="$(printf '%s' "${box_id}" | sed 's/[\/&]/\\&/g')"
    for file in "${phase_dir}/logcat.leona.txt" "${phase_dir}/matrix-row.md" "${phase_dir}/report.md"; do
      [[ -f "${file}" ]] && sed -i.bak "s/${escaped}/${hint}/g" "${file}" && rm -f "${file}.bak"
    done
  done < <(grep -Eo '"boxId":"[^"]+"' "${logcat}" 2>/dev/null | cut -d'"' -f4 | sort -u)
}

write_blocked_report() {
  local reason="$1"
  mkdir -p "${OUT_DIR}"
  cat > "${OUT_DIR}/stability-summary.md" <<EOF
# Leona Device ID Stability

- status: blocked
- reason: ${reason}
- trigger mode: direct cloudTest receiver only
- UI fallback: not used
- package: ${PACKAGE}
- adb target: ${SERIAL:-not specified}

## Privacy

- BoxId values: not generated
- canonicalDeviceId: not generated
- raw serial/android_id/fingerprint: not collected by this wrapper
EOF
  echo "Blocked: ${reason}" >&2
  echo "Report: ${OUT_DIR}/stability-summary.md" >&2
}

require_ready() {
  if [[ -z "${APK}" || ! -f "${APK}" ]]; then
    write_blocked_report "LEONA_APK must point to an existing cloudTest APK."
    exit 2
  fi
  if [[ -z "${CLOUD_TEST_TOKEN}" ]]; then
    write_blocked_report "LEONA_CLOUD_TEST_TOKEN is required; existing APK/token pairing was not provided."
    exit 2
  fi
  if [[ ! -x "${COLLECTION_SCRIPT}" ]]; then
    write_blocked_report "collection script is not executable: ${COLLECTION_SCRIPT}"
    exit 2
  fi
  if ! adb_cmd get-state >/dev/null 2>&1; then
    write_blocked_report "ADB device is not ready; set ANDROID_SERIAL/ADB_SERIAL when multiple devices are online."
    exit 3
  fi
}

run_collection_phase() {
  local phase="$1"
  local install_mode="$2"
  local phase_dir="${OUT_DIR}/${phase}"
  mkdir -p "${phase_dir}"
  LEONA_APK="${APK}" \
    ANDROID_SERIAL="${SERIAL}" \
    LEONA_PACKAGE="${PACKAGE}" \
    LEONA_COLLECTION_OUT="${phase_dir}" \
    LEONA_INSTALL_APK="${install_mode}" \
    LEONA_TRIGGER_SENSE=direct \
    LEONA_CLOUD_TEST_TOKEN="${CLOUD_TEST_TOKEN}" \
    LEONA_SENSE_WAIT_SECONDS="${SENSE_WAIT_SECONDS}" \
    "${COLLECTION_SCRIPT}"
  redact_phase_boxids "${phase_dir}"
}

phase_clear_data() {
  adb_cmd shell pm clear "${PACKAGE}" > "${OUT_DIR}/clear-data.log" 2>&1 || true
}

phase_reinstall() {
  adb_cmd uninstall "${PACKAGE}" > "${OUT_DIR}/uninstall.log" 2>&1 || true
}

phase_reboot() {
  adb_cmd reboot
  adb_cmd wait-for-device
  sleep "${LEONA_POST_REBOOT_SETTLE_SECONDS:-12}"
}

summarize() {
  local summary="${OUT_DIR}/stability-summary.md"
  local rows="${OUT_DIR}/phase-results.tsv"
  {
    echo -e "phase\tboxIdHint\tcanonicalHint\tcanonicalSha256\tstatus"
    local phase phase_dir logcat box_id box_hint canonical_hint canonical_sha status
    IFS=',' read -ra phase_array <<< "${PHASES}"
    for phase in "${phase_array[@]}"; do
      phase_dir="${OUT_DIR}/${phase}"
      logcat="${phase_dir}/logcat.leona.txt"
      box_id="$(extract_first_json_value boxId "${logcat}")"
      box_hint="$([[ -n "${box_id}" ]] && boxid_hint "${box_id}" || true)"
      canonical_hint="$(extract_first_json_value canonicalDeviceIdHint "${logcat}")"
      canonical_sha="$(extract_first_json_value canonicalDeviceIdSha256 "${logcat}")"
      status="$([[ -n "${box_id}" && -n "${canonical_sha}" ]] && echo pass || echo blocked)"
      echo -e "${phase}\t${box_hint:-not_generated}\t${canonical_hint:-not_generated}\t${canonical_sha:-not_generated}\t${status}"
    done
  } > "${rows}"

  local unique_count generated_count conclusion
  generated_count="$(awk -F'\t' 'NR > 1 && $4 != "not_generated" {count++} END {print count+0}' "${rows}")"
  unique_count="$(awk -F'\t' 'NR > 1 && $4 != "not_generated" {seen[$4]=1} END {count=0; for (k in seen) count++; print count}' "${rows}")"
  if [[ "${generated_count}" == "0" ]]; then
    conclusion="blocked: no direct sense run generated canonical hash."
  elif [[ "${unique_count}" == "1" ]]; then
    conclusion="stable: all generated canonicalDeviceId hashes match."
  else
    conclusion="unstable: generated canonicalDeviceId hashes differ across phases."
  fi

  cat > "${summary}" <<EOF
# Leona Device ID Stability

- status: ${conclusion}
- device serial hash: $(sha256_text "$(adb_cmd get-serialno 2>/dev/null | tr -d '\r' || true)")
- package: ${PACKAGE}
- trigger mode: direct cloudTest receiver
- UI fallback: not used
- phases: ${PHASES}
- output: ${OUT_DIR}

## Results

$(awk -F'\t' 'NR == 1 {next} {printf "- %s: BoxId %s, canonical %s / sha256 %s, status %s\n", $1, $2, $3, $4, $5}' "${rows}")

## Privacy

- BoxId values: redacted to hints in shareable reports/log filters
- canonicalDeviceId values: hint/hash only
- raw serial/android_id/fingerprint: hash-only through collection script
- full logcat: not collected unless LEONA_KEEP_FULL_LOGCAT=1 is explicitly set
EOF
}

require_ready
mkdir -p "${OUT_DIR}"

IFS=',' read -ra phase_array <<< "${PHASES}"
for phase in "${phase_array[@]}"; do
  case "${phase}" in
    initial)
      run_collection_phase "${phase}" 1
      ;;
    clear_data)
      phase_clear_data
      run_collection_phase "${phase}" 0
      ;;
    reinstall)
      phase_reinstall
      run_collection_phase "${phase}" 1
      ;;
    reboot)
      phase_reboot
      run_collection_phase "${phase}" 0
      ;;
    *)
      echo "Unknown phase: ${phase}" >&2
      exit 2
      ;;
  esac
done

summarize
echo "Stability summary: ${OUT_DIR}/stability-summary.md"
