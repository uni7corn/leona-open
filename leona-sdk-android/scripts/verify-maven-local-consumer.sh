#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${LEONA_SDK_VERSION:-$(grep '^VERSION_NAME=' "${ROOT_DIR}/gradle.properties" | cut -d= -f2-)}"
GROUP_ID="${LEONA_SDK_GROUP:-$(grep '^GROUP=' "${ROOT_DIR}/gradle.properties" | cut -d= -f2-)}"
ARTIFACT_ID="${LEONA_SDK_ARTIFACT:-leona-sdk-android}"
OUT_DIR="${LEONA_MAVEN_CONSUMER_OUT:-/tmp/leona-maven-consumer-$(date +%Y%m%d-%H%M%S)}"
M2_DIR="${OUT_DIR}/m2"
CONSUMER_DIR="${OUT_DIR}/consumer"
M2_REPO_PATH="${M2_DIR//\\/\\\\}"

mkdir -p "${M2_DIR}" "${CONSUMER_DIR}"

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
        maven("${M2_REPO_PATH}")
        google()
        mavenCentral()
    }
}

rootProject.name = "leona-maven-consumer-check"
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

        val requiredTransitives = setOf("core-ktx", "kotlinx-coroutines-android", "okhttp")
        val resolvedNames = artifacts.map { it.name }.toSet()
        val missing = requiredTransitives.filterNot { it in resolvedNames }
        check(missing.isEmpty()) {
            "Missing expected transitive dependencies: \${missing.joinToString()}"
        }

        println("Resolved \${sdkArtifact.moduleVersion.id} -> \${sdkArtifact.file.name}")
        println("Transitives present: \${requiredTransitives.joinToString()}")
    }
}
EOF

echo "[maven-consumer] publishing ${GROUP_ID}:${ARTIFACT_ID}:${VERSION} to isolated maven local: ${M2_DIR}"
(
  cd "${ROOT_DIR}"
  ./gradlew :sdk:publishReleasePublicationToMavenLocal \
    -Dmaven.repo.local="${M2_DIR}" \
    --no-daemon
)

echo "[maven-consumer] resolving from temporary consumer project: ${CONSUMER_DIR}"
(
  cd "${ROOT_DIR}"
  ./gradlew -p "${CONSUMER_DIR}" verifyLeonaSdkDependency \
    -Dmaven.repo.local="${M2_DIR}" \
    --no-daemon
)

cat > "${OUT_DIR}/summary.md" <<EOF
# Leona Maven Local Consumer Check

- status: pass
- coordinate: \`${GROUP_ID}:${ARTIFACT_ID}:${VERSION}\`
- isolated maven repo: \`${M2_DIR}\`
- consumer project: \`${CONSUMER_DIR}\`

This gate validates the local publication metadata and Gradle dependency
resolution path before cutting a tag. GitHub Packages remote pull must still be
validated after the tag workflow publishes the package.
EOF

echo "[maven-consumer] summary: ${OUT_DIR}/summary.md"
