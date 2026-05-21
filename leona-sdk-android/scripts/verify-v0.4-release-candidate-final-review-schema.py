#!/usr/bin/env python3
"""Validate the Android v0.4 release candidate final review summary.

This verifier is read-only. It checks that
verify-v0.4-release-candidate-final-review.sh exposes the final pre-tag review
fields needed by humans and automation: nested review/schema summary paths,
wrapper failure semantics, and no-tag/no-publish/no-stage/no-device guarantees.
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
    summary_arg = (
        sys.argv[1]
        if len(sys.argv) > 1
        else os.environ.get("LEONA_V04_RELEASE_CANDIDATE_FINAL_REVIEW_SUMMARY")
    )
    out_dir = Path(
        os.environ.get(
            "LEONA_V04_RELEASE_CANDIDATE_FINAL_REVIEW_SCHEMA_OUT",
            "/tmp/leona-v0.4-release-candidate-final-review-schema",
        )
    )
    target_version = os.environ.get("LEONA_TARGET_RELEASE_VERSION", "0.4.0")
    out_dir.mkdir(parents=True, exist_ok=True)
    schema_summary = out_dir / "summary.md"

    failures: list[str] = []
    warnings: list[str] = []

    if not summary_arg:
        fail(failures, "missing release candidate final review summary path")
        summary_path = None
        values: dict[str, str] = {}
    else:
        summary_path = Path(summary_arg)
        if not summary_path.is_file():
            fail(failures, f"release candidate final review summary does not exist: {summary_path}")
            values = {}
        else:
            values = read_values(summary_path)

    if values and summary_path:
        status = values.get("status")
        review_status = values.get("release candidate review status")
        review_schema_status = values.get("release candidate review schema status")
        review_exit = expect_exit_code(failures, values, "release candidate review exit")
        review_schema_exit = expect_exit_code(failures, values, "release candidate review schema exit")
        review_summary = expect_path(failures, values, "release candidate review summary")
        review_schema_summary = expect_path(failures, values, "release candidate review schema summary")
        report_dir = expect_path(failures, values, "report dir")

        if values.get("target release version") != target_version:
            fail(failures, f"target release version must be {target_version}")
        if status not in {"local-pass-with-external-blockers", "failed"}:
            fail(failures, "status must be local-pass-with-external-blockers or failed")
        if review_status not in {"local-pass-with-external-blockers", "failed"}:
            fail(failures, "release candidate review status must be local-pass-with-external-blockers or failed")
        if review_schema_status not in {"pass", "failed"}:
            fail(failures, "release candidate review schema status must be pass or failed")

        expect_value(failures, values, "secret values printed", "no")
        expect_value(failures, values, "creates tag", "no")
        expect_value(failures, values, "triggers GitHub Actions", "no")
        expect_value(failures, values, "publishes artifacts", "no")
        expect_value(failures, values, "executes git add", "no")
        expect_value(failures, values, "starts paid devices or WeTest sessions", "no")

        failures_section = read_section(summary_path, "Failures")
        if status == "local-pass-with-external-blockers":
            if review_exit != 0 or review_schema_exit != 0:
                fail(failures, "passing final review must have review/schema exit 0")
            if review_status != "local-pass-with-external-blockers" or review_schema_status != "pass":
                fail(failures, "passing final review must have passing nested review and schema statuses")
            if failures_section != ["none"]:
                fail(failures, "passing final review must list no failures")
        if status == "failed":
            if review_exit == 0 and review_schema_exit == 0:
                fail(failures, "failed final review must have a non-zero nested review or schema exit")
            if failures_section == ["none"]:
                fail(failures, "failed final review must list at least one failure")

        if review_schema_status == "pass" and review_schema_exit != 0:
            fail(failures, "nested schema status pass must have schema exit 0")
        if review_schema_status == "failed" and review_schema_exit == 0:
            fail(failures, "nested schema status failed must have non-zero schema exit")
        if review_status == "local-pass-with-external-blockers" and review_exit != 0:
            fail(failures, "nested review pass status must have review exit 0")
        if review_status == "failed" and review_exit == 0:
            fail(failures, "nested review failed status must have non-zero review exit")

        if report_dir and not str(review_summary or "").startswith(str(report_dir)):
            fail(failures, "nested review summary must be inside the final review report dir")
        if report_dir and not str(review_schema_summary or "").startswith(str(report_dir)):
            fail(failures, "nested review schema summary must be inside the final review report dir")

        if review_summary and review_schema_summary:
            nested_values = read_values(review_summary)
            nested_schema_values = read_values(review_schema_summary)
            if nested_values.get("status") != review_status:
                fail(failures, "final review status must match nested review summary status")
            if nested_schema_values.get("status") != review_schema_status:
                fail(failures, "final review schema status must match nested schema summary status")
            for key in (
                "secret values printed",
                "creates tag",
                "triggers GitHub Actions",
                "publishes artifacts",
                "executes git add",
                "starts paid devices or WeTest sessions",
            ):
                if nested_values.get(key) == "yes":
                    fail(failures, f"nested review summary must not set {key} to yes")
                if nested_schema_values.get(key) == "yes":
                    fail(failures, f"nested review schema summary must not set {key} to yes")
        else:
            warnings.append("nested review or schema summary could not be cross-checked")

    status = "pass" if not failures else "failed"
    with schema_summary.open("w", encoding="utf-8") as handle:
        handle.write("# Leona v0.4 Android Release Candidate Final Review Schema\n\n")
        handle.write(f"- status: {status}\n")
        handle.write(f"- release candidate final review summary: `{summary_arg or ''}`\n")
        handle.write("- validates review summary path: yes\n")
        handle.write("- validates review schema summary path: yes\n")
        handle.write("- validates final wrapper failure semantics: yes\n")
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

    print(f"[release-candidate-final-review-schema] summary: {schema_summary}")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
