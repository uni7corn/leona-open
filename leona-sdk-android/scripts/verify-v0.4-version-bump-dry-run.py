#!/usr/bin/env python3
"""Dry-run Android v0.4 version marker convergence in memory.

This verifier applies the public Android version bump plan to in-memory file
contents and proves the required markers converge to the target release version.
It does not write files, stage paths, create tags, publish artifacts, start
devices, or print secrets.
"""

from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Replacement:
    path: str
    old: str
    new: str
    required: bool
    marker: str
    reason: str


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    target_version = os.environ.get("LEONA_TARGET_RELEASE_VERSION", "0.4.0")
    report_dir = Path(os.environ.get("LEONA_ANDROID_VERSION_BUMP_DRY_RUN_OUT", "/tmp/leona-v0.4-version-bump-dry-run"))
    report_dir.mkdir(parents=True, exist_ok=True)
    summary_path = report_dir / "summary.md"

    gradle_properties = root / "gradle.properties"
    current_version = ""
    for line in gradle_properties.read_text(encoding="utf-8").splitlines():
        if line.startswith("VERSION_NAME="):
            current_version = line.split("=", 1)[1]
            break

    replacements = [
        Replacement(
            "gradle.properties",
            f"VERSION_NAME={current_version}",
            f"VERSION_NAME={target_version}",
            True,
            f"VERSION_NAME={target_version}",
            "Maven coordinate and Gradle publication version",
        ),
        Replacement(
            "sdk/src/main/kotlin/io/leonasec/leona/BuildConstants.kt",
            f'VERSION_NAME = "{current_version}"',
            f'VERSION_NAME = "{target_version}"',
            True,
            f'VERSION_NAME = "{target_version}"',
            "runtime SDK version marker reported by public API",
        ),
        Replacement(
            "sample-app/build.gradle.kts",
            f'versionName = "{current_version}"',
            f'versionName = "{target_version}"',
            True,
            f'versionName = "{target_version}"',
            "sample APK versionName aligned with SDK coordinate",
        ),
        Replacement(
            "sample-app/src/main/res/layout/activity_main.xml",
            f"SDK version: {current_version}",
            f"SDK version: {target_version}",
            False,
            f"SDK version: {target_version}",
            "design-time sample preview text",
        ),
        Replacement(
            "sample-app/src/main/res/layout/activity_main.xml",
            f'&quot;sdkVersion&quot;: &quot;{current_version}&quot;',
            f'&quot;sdkVersion&quot;: &quot;{target_version}&quot;',
            False,
            f'&quot;sdkVersion&quot;: &quot;{target_version}&quot;',
            "design-time sample JSON preview text",
        ),
        Replacement(
            "README.md",
            f"version-{current_version}-blue",
            f"version-{target_version}-blue",
            False,
            f"version-{target_version}-blue",
            "public README badge for latest SDK version",
        ),
    ]

    failures: list[str] = []
    warnings: list[str] = []
    rows: list[tuple[Replacement, int, str, str, str]] = []

    if not current_version:
        failures.append("VERSION_NAME marker missing from gradle.properties")
    if current_version == target_version:
        warnings.append(f"VERSION_NAME already equals target {target_version}; dry-run is a no-op.")

    forbidden_paths = ("leona-sdk-ios/", "leona-web-sdk/", "leona-server/", "leona-homepage/", "private/", "server/")

    for replacement in replacements:
        if replacement.path.startswith(forbidden_paths):
            failures.append(f"forbidden non-Android release path in dry-run: {replacement.path}")
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
        after_sha = sha256_text(after)
        status = "converged" if replacement.marker in after else "not-converged"

        if replacement.required and count != 1:
            failures.append(f"required marker must occur exactly once in {replacement.path}: found {count}")
        if replacement.required and replacement.old != replacement.new and replacement.old in after:
            failures.append(f"old required marker remains after dry-run in {replacement.path}")
        if replacement.required and replacement.marker not in after:
            failures.append(f"target required marker missing after dry-run in {replacement.path}: {replacement.marker}")
        if not replacement.required and count == 0:
            warnings.append(f"optional marker not found in {replacement.path}: {replacement.old}")
            status = "optional-not-found"
        elif not replacement.required and replacement.marker not in after:
            failures.append(f"optional marker replacement failed to converge in {replacement.path}: {replacement.marker}")

        rows.append((replacement, count, sha256_text(before), after_sha, status))

    status = "pass" if not failures else "failed"
    with summary_path.open("w", encoding="utf-8") as handle:
        handle.write("# Leona v0.4 Android Version Bump Dry Run\n\n")
        handle.write(f"- status: {status}\n")
        handle.write(f"- current VERSION_NAME: `{current_version}`\n")
        handle.write(f"- target version: `{target_version}`\n")
        handle.write("- writes files: no\n")
        handle.write("- executes git add: no\n")
        handle.write("- creates tag: no\n")
        handle.write("- publishes artifacts: no\n")
        handle.write("- starts paid devices or WeTest sessions: no\n")
        handle.write("- secret values printed: no\n\n")
        handle.write("## Dry-Run Replacements\n")
        handle.write("| file | required | count | status | before sha256 | dry-run sha256 | reason |\n")
        handle.write("| --- | --- | ---: | --- | --- | --- | --- |\n")
        for replacement, count, before_sha, after_sha, row_status in rows:
            handle.write(
                f"| `{replacement.path}` | {'yes' if replacement.required else 'no'} | "
                f"{count} | {row_status} | `{before_sha}` | `{after_sha}` | {replacement.reason} |\n"
            )
        handle.write("\n## Convergence Checks\n")
        handle.write("- required markers converge to target version: ")
        handle.write("yes\n" if not failures else "no\n")
        handle.write("- non-Android paths included: no\n")
        handle.write("- disk writes performed: no\n")
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

    print(f"[version-bump-dry-run] summary: {summary_path}")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
