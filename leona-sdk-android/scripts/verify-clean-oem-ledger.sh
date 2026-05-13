#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNBOOK="${1:-${ROOT_DIR}/docs/wetest-matrix-runbook.md}"
MIN_BRANDS="${MIN_CLEAN_OEM_BRANDS:-6}"

if [[ ! -f "$RUNBOOK" ]]; then
  echo "[clean-oem-ledger] runbook not found: $RUNBOOK" >&2
  exit 1
fi

awk -v min_brands="$MIN_BRANDS" -v runbook="$RUNBOOK" '
function trim(value) {
  gsub(/^[[:space:]]+/, "", value)
  gsub(/[[:space:]]+$/, "", value)
  return value
}

function add_failure(message) {
  failures[++failure_count] = message
}

function remember_family(value, lower_value) {
  lower_value = tolower(value)
  if (lower_value ~ /samsung/) samsung = 1
  if (lower_value ~ /(xiaomi|redmi)/) xiaomi = 1
  if (lower_value ~ /(honor|huawei)/) honor_huawei = 1
  if (lower_value ~ /oppo/) oppo = 1
  if (lower_value ~ /(vivo|iqoo)/) vivo = 1
  if (lower_value ~ /realme/) realme = 1
  if (lower_value ~ /(asus|rog)/) asus = 1
}

/^### Tested Device Ledger[[:space:]]*$/ {
  in_ledger = 1
  next
}

in_ledger && /^### / {
  in_ledger = 0
  exit
}

in_ledger {
  if ($0 !~ /^[[:space:]]*$/) ledger_lines++

  if ($0 ~ /01[0-9A-HJKMNP-TV-Z]{24}/) {
    add_failure("raw BoxId value found in ledger; use BoxId hints or hashes only")
  }

  if ($0 !~ /^\|/) next
  if ($0 ~ /\|[[:space:]]*---/) next

  split($0, cells, /\|/)
  date = trim(cells[2])
  brand = trim(cells[3])
  model = trim(cells[4])
  android = trim(cells[5])
  result = tolower(trim(cells[6]))
  output = trim(cells[7])

  if (date == "Date" || result != "pass") next

  pass_rows++

  if (output !~ /BoxId[[:space:]]+(hint|hash)/) {
    add_failure(date " " brand " " model ": pass row must use a BoxId hint/hash")
  } else if (output ~ /BoxId[[:space:]]+hint/ && output !~ /\.\.\./) {
    add_failure(date " " brand " " model ": BoxId hint must be redacted with ellipsis")
  }

  lower_row = tolower($0)
  if (lower_row !~ /\/tmp\/leona-/) {
    add_failure(date " " brand " " model ": pass row must reference its redacted artifact directory")
  }
  if (lower_row !~ /canonical[[:space:]-]*(hash|hint)[[:space:]]+recorded/) {
    add_failure(date " " brand " " model ": pass row must state canonical hash/hint was recorded")
  }
  if (lower_row !~ /authoritative[[:space:]-]*(event|events)[[:space:]]+recorded/) {
    add_failure(date " " brand " " model ": pass row must state authoritative events were recorded")
  }
  if (lower_row !~ /telemetry[[:space:]-]*(event|events)[[:space:]]+recorded/) {
    add_failure(date " " brand " " model ": pass row must state telemetry events were recorded")
  }
  if (lower_row ~ /(^|[^[:alnum:]_])(frida|magisk|xposed|unidbg|honeypot|root|hook|emulator)([^[:alnum:]_]|$)/) {
    add_failure(date " " brand " " model ": pass row contains a disallowed false-positive family term")
  }

  if (android == "") {
    add_failure(date " " brand " " model ": Android version is empty")
  }

  remember_family(brand " " model)
}

END {
  if (ledger_lines == 0) {
    add_failure("Tested Device Ledger section is empty or missing")
  }
  if (pass_rows == 0) {
    add_failure("no pass rows found in Tested Device Ledger")
  }

  sep = ""
  if (asus) { family_count++; families = families sep "Asus"; sep = ", " }
  if (honor_huawei) { family_count++; families = families sep "HONOR/HUAWEI"; sep = ", " }
  if (oppo) { family_count++; families = families sep "OPPO"; sep = ", " }
  if (realme) { family_count++; families = families sep "realme"; sep = ", " }
  if (samsung) { family_count++; families = families sep "Samsung"; sep = ", " }
  if (vivo) { family_count++; families = families sep "vivo/iQOO"; sep = ", " }
  if (xiaomi) { family_count++; families = families sep "Xiaomi/Redmi"; sep = ", " }

  if (family_count < min_brands) {
    add_failure("only " family_count " clean OEM brand families pass; require at least " min_brands)
  }

  if (failure_count > 0) {
    print "[clean-oem-ledger] FAILED" > "/dev/stderr"
    for (i = 1; i <= failure_count; i++) {
      print "  - " failures[i] > "/dev/stderr"
    }
    exit 1
  }

  print "[clean-oem-ledger] passed"
  print "  runbook: " runbook
  print "  pass rows: " pass_rows
  print "  clean OEM brand families: " family_count " (" families ")"
  print "  BoxId policy: redacted hints/hashes only"
  print "  pass-row artifact and evidence fields: present"
  print "  pass-row false-positive terms: absent"
}
' "$RUNBOOK"
