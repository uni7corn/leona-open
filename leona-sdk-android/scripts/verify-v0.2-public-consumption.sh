#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${LEONA_SDK_VERSION:-0.2.0}"
GROUP_ID="${LEONA_SDK_GROUP:-io.leonasec}"
ARTIFACT_ID="${LEONA_SDK_ARTIFACT:-leona-sdk-android}"
REPO_OWNER="${LEONA_GITHUB_OWNER:-zedbully}"
REPO_NAME="${LEONA_GITHUB_REPO:-leona-open}"
OUT_DIR="${LEONA_PUBLIC_CONSUMPTION_OUT:-/tmp/leona-v${VERSION}-public-consumption-$(date +%Y%m%d-%H%M%S)}"
RELEASE_BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}"
PACKAGE_TOKEN="${LEONA_GITHUB_PACKAGES_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
PACKAGE_USER="${LEONA_GITHUB_PACKAGES_USER:-${GITHUB_ACTOR:-${USER:-leona-consumer}}}"
STATUS=0
PASS_COUNT=0
SKIPS=()
FAILURES=()

mkdir -p "${OUT_DIR}"

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[pass] %s\n' "$1"
}

skip() {
  SKIPS+=("$1")
  printf '[skip] %s\n' "$1"
}

fail() {
  STATUS=1
  FAILURES+=("$1")
  printf '[fail] %s\n' "$1" >&2
}

echo "[public-consumption] Leona Android SDK v${VERSION}"
echo "[public-consumption] report dir: ${OUT_DIR}"

AAR_NAME="${ARTIFACT_ID}-${VERSION}.aar"
SHA_NAME="${AAR_NAME}.sha256"
AAR_PATH="${OUT_DIR}/${AAR_NAME}"
SHA_PATH="${OUT_DIR}/${SHA_NAME}"

if curl -fsSL "${RELEASE_BASE_URL}/${AAR_NAME}" -o "${AAR_PATH}" &&
   curl -fsSL "${RELEASE_BASE_URL}/${SHA_NAME}" -o "${SHA_PATH}"; then
  (
    cd "${OUT_DIR}"
    shasum -a 256 -c "${SHA_NAME}"
  ) > "${OUT_DIR}/release-aar-sha256.txt"
  pass "GitHub Release AAR fallback downloads and matches sha256"
else
  fail "GitHub Release AAR fallback download failed from ${RELEASE_BASE_URL}"
fi

if [[ -z "${PACKAGE_TOKEN}" ]]; then
  skip "GitHub Packages remote Gradle pull not run; set LEONA_GITHUB_PACKAGES_TOKEN or GITHUB_TOKEN with read:packages."
else
  CONSUMER_DIR="${OUT_DIR}/github-packages-consumer"
  mkdir -p "${CONSUMER_DIR}"
  cat > "${CONSUMER_DIR}/settings.gradle.kts" <<EOF
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://maven.pkg.github.com/${REPO_OWNER}/${REPO_NAME}") {
            credentials {
                username = "${PACKAGE_USER}"
                password = providers.environmentVariable("LEONA_GITHUB_PACKAGES_TOKEN")
                    .orElse(providers.environmentVariable("GITHUB_TOKEN"))
                    .orElse(providers.environmentVariable("GH_TOKEN"))
                    .get()
            }
        }
    }
}

rootProject.name = "leona-github-packages-consumer-check"
EOF
  cat > "${CONSUMER_DIR}/build.gradle.kts" <<EOF
val leonaSdk by configurations.creating

dependencies {
    leonaSdk("${GROUP_ID}:${ARTIFACT_ID}:${VERSION}")
}

tasks.register("verifyLeonaSdkDependency") {
    doLast {
        val artifacts = leonaSdk.resolvedConfiguration.resolvedArtifacts
        val sdkArtifact = artifacts.firstOrNull {
            it.moduleVersion.id.group == "${GROUP_ID}" &&
                it.name == "${ARTIFACT_ID}" &&
                it.moduleVersion.id.version == "${VERSION}"
        } ?: error("Missing ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}")

        check(sdkArtifact.file.extension == "aar") {
            "Expected AAR artifact, got \${sdkArtifact.file.name}"
        }

        println("Resolved \${sdkArtifact.moduleVersion.id} -> \${sdkArtifact.file.name}")
    }
}
EOF

  if (
    cd "${ROOT_DIR}"
    LEONA_GITHUB_PACKAGES_TOKEN="${PACKAGE_TOKEN}" ./gradlew -p "${CONSUMER_DIR}" verifyLeonaSdkDependency --no-daemon
  ) > "${OUT_DIR}/github-packages-consumer.txt"; then
    pass "GitHub Packages remote Gradle pull resolves ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}"
  else
    fail "GitHub Packages remote Gradle pull failed; see ${OUT_DIR}/github-packages-consumer.txt"
  fi
fi

{
  echo "# Leona v${VERSION} Public Consumption Smoke"
  echo
  echo "- status: $([[ "${STATUS}" == "0" ]] && echo "pass" || echo "failed")"
  echo "- coordinate: \`${GROUP_ID}:${ARTIFACT_ID}:${VERSION}\`"
  echo "- release fallback URL: \`${RELEASE_BASE_URL}/${AAR_NAME}\`"
  echo "- report dir: \`${OUT_DIR}\`"
  echo "- pass checks: ${PASS_COUNT}"
  echo
  echo "## Failures"
  if (( ${#FAILURES[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${FAILURES[@]}"
  fi
  echo
  echo "## Skips"
  if (( ${#SKIPS[@]} == 0 )); then
    echo "- none"
  else
    printf -- '- %s\n' "${SKIPS[@]}"
  fi
} > "${OUT_DIR}/summary.md"

echo "[public-consumption] summary: ${OUT_DIR}/summary.md"
exit "${STATUS}"
