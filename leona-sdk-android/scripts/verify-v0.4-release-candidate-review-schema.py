#!/usr/bin/env python3
"""Validate the Android v0.4 release candidate review summary.

This verifier is read-only. It checks that
verify-v0.4-release-candidate-review.sh still exposes the fields needed for a
human or automation pre-tag review: manifest/schema summary paths, failure
semantics, and no-tag/no-publish/no-stage/no-device guarantees.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


def strip_value(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def read_values(summary_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    pattern = re.compile(r"^- ([^:]+):\s*(.*)$")
    for line in summary_path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values.setdefault(match.group(1), strip_value(match.group(2)))
    return values


def read_section(summary_path: Path, heading: str) -> list[str]:
    items: list[str] = []
    in_section = False
    for line in summary_path.read_text(encoding="utf-8").splitlines():
        if line == f"## {heading}":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section and line.startswith("- "):
            items.append(line[2:])
    return items


def fail(failures: list[str], message: str) -> None:
    failures.append(message)


def expect_value(failures: list[str], values: dict[str, str], key: str, expected: str) -> None:
    if values.get(key) != expected:
        fail(failures, f"{key} must be {expected}; got {values.get(key, '<missing>')}")


def expect_path(failures: list[str], values: dict[str, str], key: str) -> Path | None:
    value = values.get(key, "")
    if not value.startswith("/"):
        fail(failures, f"{key} must be an absolute path")
        return None
    path = Path(value)
    if not path.exists():
        fail(failures, f"{key} path does not exist: {path}")
        return None
    return path


def expect_exit_code(failures: list[str], values: dict[str, str], key: str) -> int | None:
    value = values.get(key, "")
    try:
        code = int(value)
    except ValueError:
        fail(failures, f"{key} must be an integer")
        return None
    if code < 0:
        fail(failures, f"{key} must be non-negative")
    return code


def main() -> int:
    summary_arg = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LEONA_V04_RELEASE_CANDIDATE_REVIEW_SUMMARY")
    out_dir = Path(os.environ.get("LEONA_V04_RELEASE_CANDIDATE_REVIEW_SCHEMA_OUT", "/tmp/leona-v0.4-release-candidate-review-schema"))
    target_version = os.environ.get("LEONA_TARGET_RELEASE_VERSION", "0.4.0")
    out_dir.mkdir(parents=True, exist_ok=True)
    schema_summary = out_dir / "summary.md"

    failures: list[str] = []
    warnings: list[str] = []

    if not summary_arg:
        fail(failures, "missing release candidate review summary path")
        summary_path = None
        values: dict[str, str] = {}
    else:
        summary_path = Path(summary_arg)
        if not summary_path.is_file():
            fail(failures, f"release candidate review summary does not exist: {summary_path}")
            values = {}
        else:
            values = read_values(summary_path)

    if values and summary_path:
        status = values.get("status")
        manifest_status = values.get("release candidate manifest status")
        schema_status = values.get("release candidate manifest schema status")
        manifest_exit = expect_exit_code(failures, values, "release candidate manifest exit")
        schema_exit = expect_exit_code(failures, values, "release candidate manifest schema exit")
        manifest_summary = expect_path(failures, values, "release candidate manifest summary")
        schema_summary_path = expect_path(failures, values, "release candidate manifest schema summary")
        report_dir = expect_path(failures, values, "report dir")

        if values.get("target release version") != target_version:
            fail(failures, f"target release version must be {target_version}")
        if status not in {"local-pass-with-external-blockers", "failed"}:
            fail(failures, "status must be local-pass-with-external-blockers or failed")
        if manifest_status not in {"local-pass-with-external-blockers", "failed"}:
            fail(failures, "release candidate manifest status must be local-pass-with-external-blockers or failed")
        if schema_status not in {"pass", "failed"}:
            fail(failures, "release candidate manifest schema status must be pass or failed")

        expect_value(failures, values, "secret values printed", "no")
        expect_value(failures, values, "creates tag", "no")
        expect_value(failures, values, "triggers GitHub Actions", "no")
        expect_value(failures, values, "publishes artifacts", "no")
        expect_value(failures, values, "executes git add", "no")
        expect_value(failures, values, "starts paid devices or WeTest sessions", "no")

        failures_section = read_section(summary_path, "Failures")
        if status == "local-pass-with-external-blockers":
            if manifest_exit != 0 or schema_exit != 0:
                fail(failures, "passing review must have manifest/schema exit 0")
            if manifest_status != "local-pass-with-external-blockers" or schema_status != "pass":
                fail(failures, "passing review must have passing manifest and schema statuses")
            if failures_section != ["none"]:
                fail(failures, "passing review must list no failures")
        if status == "failed":
            if manifest_exit == 0 and schema_exit == 0:
                fail(failures, "failed review must have a non-zero manifest or schema exit")
            if failures_section == ["none"]:
                fail(failures, "failed review must list at least one failure")

        if schema_status == "pass" and schema_exit != 0:
            fail(failures, "schema status pass must have schema exit 0")
        if schema_status == "failed" and schema_exit == 0:
            fail(failures, "schema status failed must have non-zero schema exit")
        if manifest_status == "local-pass-with-external-blockers" and manifest_exit != 0:
            fail(failures, "manifest pass status must have manifest exit 0")
        if manifest_status == "failed" and manifest_exit == 0:
            fail(failures, "manifest failed status must have non-zero manifest exit")

        if report_dir and not str(manifest_summary or "").startswith(str(report_dir)):
            fail(failures, "manifest summary must be inside the review report dir")
        if report_dir and not str(schema_summary_path or "").startswith(str(report_dir)):
            fail(failures, "manifest schema summary must be inside the review report dir")

        if manifest_summary and schema_summary_path:
            manifest_values = read_values(manifest_summary)
            schema_values = read_values(schema_summary_path)
            if manifest_values.get("status") != manifest_status:
                fail(failures, "review manifest status must match manifest summary status")
            if schema_values.get("status") != schema_status:
                fail(failures, "review schema status must match schema summary status")
            for key in (
                "secret values printed",
                "creates tag",
                "triggers GitHub Actions",
                "publishes artifacts",
                "executes git add",
                "starts paid devices or WeTest sessions",
            ):
                if manifest_values.get(key) == "yes":
                    fail(failures, f"manifest summary must not set {key} to yes")
                if schema_values.get(key) == "yes":
                    fail(failures, f"schema summary must not set {key} to yes")
        else:
            warnings.append("manifest or schema summary could not be cross-checked")

    status = "pass" if not failures else "failed"
    with schema_summary.open("w", encoding="utf-8") as handle:
        handle.write("# Leona v0.4 Android Release Candidate Review Schema\n\n")
        handle.write(f"- status: {status}\n")
        handle.write(f"- release candidate review summary: `{summary_arg or ''}`\n")
        handle.write("- validates manifest summary path: yes\n")
        handle.write("- validates manifest schema summary path: yes\n")
        handle.write("- validates wrapper failure semantics: yes\n")
        handle.write("- validates no-auto-stage/no-publish/no-device rules: yes\n")
        handle.write("- secret values printed: no\n")
        handle.write("- creates tag: no\n")
        handle.write("- triggers GitHub Actions: no\n")
        handle.write("- publishes artifacts: no\n")
        handle.write("- executes git add: no\n")
        handle.write("- starts paid devices or WeTest sessions: no\n\n")
        handle.write("## Warnings\n")
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

    print(f"[release-candidate-review-schema] summary: {schema_summary}")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
