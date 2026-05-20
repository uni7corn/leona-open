#!/usr/bin/env python3
"""Build a read-only Android v0.4 version bump plan.

The plan identifies public Android files that should be reviewed before the
real v0.4 tag version bump. It computes planned replacement counts and planned
SHA-256 digests without writing files, staging paths, creating tags, publishing
artifacts, starting devices, or printing secrets.
"""

from __future__ import annotations

import hashlib
import os
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Replacement:
    path: str
    old: str
    new: str
    required: bool
    reason: str


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    target_version = os.environ.get("LEONA_TARGET_RELEASE_VERSION", "0.4.0")
    report_dir = Path(os.environ.get("LEONA_ANDROID_VERSION_BUMP_PLAN_OUT", "/tmp/leona-v0.4-version-bump-plan"))
    require_clean_plan = os.environ.get("LEONA_REQUIRE_ANDROID_VERSION_BUMP_PLAN", "0")
    report_dir.mkdir(parents=True, exist_ok=True)
    summary_path = report_dir / "summary.md"

    gradle_properties = root / "gradle.properties"
    current_version = ""
    for line in gradle_properties.read_text(encoding="utf-8").splitlines():
        if line.startswith("VERSION_NAME="):
            current_version = line.split("=", 1)[1]
            break

    failures: list[str] = []
    warnings: list[str] = []
    replacements = [
        Replacement(
            "gradle.properties",
            f"VERSION_NAME={current_version}",
            f"VERSION_NAME={target_version}",
            True,
            "Maven coordinate and Gradle publication version",
        ),
        Replacement(
            "sdk/src/main/kotlin/io/leonasec/leona/BuildConstants.kt",
            f'VERSION_NAME = "{current_version}"',
            f'VERSION_NAME = "{target_version}"',
            True,
            "runtime SDK version marker reported by public API",
        ),
        Replacement(
            "sample-app/build.gradle.kts",
            f'versionName = "{current_version}"',
            f'versionName = "{target_version}"',
            True,
            "sample APK versionName aligned with SDK coordinate",
        ),
        Replacement(
            "sample-app/src/main/res/layout/activity_main.xml",
            f"SDK version: {current_version}",
            f"SDK version: {target_version}",
            False,
            "design-time sample preview text",
        ),
        Replacement(
            "sample-app/src/main/res/layout/activity_main.xml",
            f'&quot;sdkVersion&quot;: &quot;{current_version}&quot;',
            f'&quot;sdkVersion&quot;: &quot;{target_version}&quot;',
            False,
            "design-time sample JSON preview text",
        ),
        Replacement(
            "README.md",
            f"version-{current_version}-blue",
            f"version-{target_version}-blue",
            False,
            "public README badge for latest SDK version",
        ),
    ]

    rows: list[tuple[Replacement, int, str, str, str]] = []
    for replacement in replacements:
        path = root / replacement.path
        if not path.is_file():
            if replacement.required:
                failures.append(f"required version marker file missing: {replacement.path}")
            else:
                warnings.append(f"optional version marker file missing: {replacement.path}")
            rows.append((replacement, 0, "", "", "missing"))
            continue
        before = path.read_text(encoding="utf-8")
        count = before.count(replacement.old)
        after = before.replace(replacement.old, replacement.new)
        status = "planned" if count > 0 else "not-found"
        if replacement.required and count != 1:
            failures.append(f"required marker must occur exactly once in {replacement.path}: found {count}")
        if not replacement.required and count == 0:
            warnings.append(f"optional marker not found in {replacement.path}: {replacement.old}")
        rows.append((replacement, count, sha256_text(before), sha256_text(after), status))

    forbidden_paths = ["leona-sdk-ios/", "leona-web-sdk/", "leona-server/", "leona-homepage/", "private/", "server/"]
    for replacement, _, _, _, _ in rows:
        if any(replacement.path.startswith(prefix) for prefix in forbidden_paths):
            failures.append(f"forbidden non-Android release path in bump plan: {replacement.path}")

    current_equals_target = current_version == target_version
    if current_equals_target:
        warnings.append(f"VERSION_NAME already equals target {target_version}; no bump is required.")

    status = "pass" if not failures else "failed"
    if require_clean_plan == "1" and failures:
        exit_code = 1
    elif failures:
        exit_code = 1
    else:
        exit_code = 0

    with summary_path.open("w", encoding="utf-8") as handle:
        handle.write("# Leona v0.4 Android Version Bump Plan\n\n")
        handle.write(f"- status: {status}\n")
        handle.write(f"- current VERSION_NAME: `{current_version}`\n")
        handle.write(f"- target version: `{target_version}`\n")
        handle.write(f"- strict mode: `{require_clean_plan}`\n")
        handle.write("- writes files: no\n")
        handle.write("- executes git add: no\n")
        handle.write("- creates tag: no\n")
        handle.write("- publishes artifacts: no\n")
        handle.write("- starts paid devices or WeTest sessions: no\n")
        handle.write("- secret values printed: no\n\n")
        handle.write("## Planned Replacements\n")
        handle.write("| file | required | count | status | before sha256 | planned sha256 | reason |\n")
        handle.write("| --- | --- | ---: | --- | --- | --- | --- |\n")
        for replacement, count, before_sha, after_sha, row_status in rows:
            handle.write(
                f"| `{replacement.path}` | {'yes' if replacement.required else 'no'} | "
                f"{count} | {row_status} | `{before_sha}` | `{after_sha}` | {replacement.reason} |\n"
            )
        handle.write("\n## Required Files\n")
        for replacement in replacements:
            if replacement.required:
                handle.write(f"- `{replacement.path}`\n")
        handle.write("\n## Warnings\n")
        if warnings:
            for warning in warnings:
                handle.write(f"- {warning}\n")
        else:
            handle.write("- none\n")
        handle.write("\n## Failures\n")
        if failures:
            for failure in failures:
                handle.write(f"- {failure}\n")
        else:
            handle.write("- none\n")
        handle.write("\n## Rule\n")
        handle.write("- This gate is read-only. Apply the plan only in the final release bump commit.\n")
        handle.write("- Re-run `verify-v0.4-version-markers.sh` in strict mode after applying the bump.\n")

    print(f"[version-bump-plan] summary: {summary_path}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
