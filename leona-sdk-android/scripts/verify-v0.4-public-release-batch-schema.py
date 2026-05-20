#!/usr/bin/env python3
"""Validate the Android v0.4 public release batch planner output.

This verifier is read-only. It checks that the generated stage-command draft
matches the public path list, excludes do-not-stage paths, preserves the git
index in dry-run mode, and that path-list counts and SHA-256 values in the
summary match the referenced files.
"""

from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path
from typing import Any


FORBIDDEN_PUBLIC_PREFIXES = (
    "leona-sdk-ios/",
    "leona-web-sdk/",
    "leona-homepage/",
    "leona-server/",
    "private/",
    "server/",
    "homepage/",
    "policy/",
    "deploy/",
    "deployment/",
    "wdblogs/",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def strip_value(value: str) -> str:
    value = value.strip()
    if value.startswith("`") and value.endswith("`"):
        return value[1:-1]
    return value


def read_summary_values(summary_path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    pattern = re.compile(r"^- ([^:]+):\s*(.*)$")
    for line in summary_path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            values.setdefault(match.group(1), strip_value(match.group(2)))
    return values


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.rstrip("\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def fail(failures: list[str], message: str) -> None:
    failures.append(message)


def expect_value(failures: list[str], values: dict[str, str], key: str, expected: str) -> None:
    if values.get(key) != expected:
        fail(failures, f"{key} must be {expected}; got {values.get(key, '<missing>')}")


def expect_count(
    failures: list[str],
    values: dict[str, str],
    key: str,
    path: Path,
) -> None:
    actual = len(read_lines(path))
    try:
        expected = int(values.get(key, ""))
    except ValueError:
        fail(failures, f"{key} must be an integer")
        return
    if actual != expected:
        fail(failures, f"{key} mismatch: summary={expected}, actual={actual}, file={path}")


def expect_hash(
    failures: list[str],
    values: dict[str, str],
    key: str,
    path: Path,
) -> None:
    if not path.is_file():
        fail(failures, f"{key} file is missing: {path}")
        return
    expected = values.get(key, "")
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        fail(failures, f"{key} must be a 64-character SHA-256 digest")
        return
    actual = sha256(path)
    if actual != expected:
        fail(failures, f"{key} mismatch: summary={expected}, actual={actual}, file={path}")


def main() -> int:
    summary_arg = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LEONA_V04_PUBLIC_RELEASE_BATCH_SUMMARY")
    out_dir = Path(os.environ.get("LEONA_V04_PUBLIC_RELEASE_BATCH_SCHEMA_OUT", "/tmp/leona-v0.4-public-release-batch-schema"))
    out_dir.mkdir(parents=True, exist_ok=True)
    schema_summary = out_dir / "summary.md"

    failures: list[str] = []
    warnings: list[str] = []

    if not summary_arg:
        fail(failures, "missing public release batch summary path")
        summary_path = None
        values: dict[str, str] = {}
        report_dir = None
    else:
        summary_path = Path(summary_arg)
        if not summary_path.is_file():
            fail(failures, f"public release batch summary does not exist: {summary_path}")
            values = {}
            report_dir = None
        else:
            values = read_summary_values(summary_path)
            report_value = values.get("report dir", "")
            report_dir = Path(report_value) if report_value.startswith("/") else None
            if report_dir is None or not report_dir.is_dir():
                fail(failures, f"report dir must be an existing absolute directory: {report_value}")

    if report_dir is not None:
        public_paths = report_dir / "public-release-batch-paths.txt"
        do_not_stage_paths = report_dir / "do-not-stage-paths.txt"
        staged_forbidden_paths = report_dir / "staged-forbidden-paths.txt"
        stage_draft_paths = report_dir / "stage-command-draft-paths.txt"
        stage_overlap = report_dir / "stage-command-draft-do-not-stage-overlap.txt"
        dry_run_index_before = report_dir / "stage-command-dry-run-index-before.txt"
        dry_run_index_after = report_dir / "stage-command-dry-run-index-after.txt"
        stage_script = report_dir / "stage-public-release-batch.sh"

        for path in (
            public_paths,
            do_not_stage_paths,
            staged_forbidden_paths,
            stage_draft_paths,
            stage_overlap,
            dry_run_index_before,
            dry_run_index_after,
            stage_script,
        ):
            if not path.exists():
                fail(failures, f"expected generated file missing: {path}")

        expect_count(failures, values, "public release batch paths", public_paths)
        expect_count(failures, values, "do-not-stage paths", do_not_stage_paths)
        expect_count(failures, values, "staged forbidden paths", staged_forbidden_paths)
        expect_count(failures, values, "stage command draft paths", stage_draft_paths)

        expect_hash(failures, values, "public release batch paths sha256", public_paths)
        expect_hash(failures, values, "do-not-stage paths sha256", do_not_stage_paths)
        expect_hash(failures, values, "staged forbidden paths sha256", staged_forbidden_paths)
        expect_hash(failures, values, "stage command draft paths sha256", stage_draft_paths)

        public_list = read_lines(public_paths)
        stage_list = read_lines(stage_draft_paths)
        do_not_stage_list = read_lines(do_not_stage_paths)
        staged_forbidden_list = read_lines(staged_forbidden_paths)
        overlap_list = read_lines(stage_overlap)

        if public_list != stage_list:
            fail(failures, "stage command draft paths must exactly match public release batch paths")
        if set(stage_list).intersection(do_not_stage_list):
            fail(failures, "stage command draft contains do-not-stage paths")
        if overlap_list:
            fail(failures, f"stage command do-not-stage overlap must be empty: {stage_overlap}")
        if staged_forbidden_list:
            fail(failures, f"staged forbidden paths must be empty: {staged_forbidden_paths}")

        for path in public_list:
            if path.startswith(FORBIDDEN_PUBLIC_PREFIXES):
                fail(failures, f"public release batch contains forbidden path prefix: {path}")
            if ".." in Path(path).parts:
                fail(failures, f"public release batch path must not contain '..': {path}")

        expect_value(failures, values, "secret values printed", "no")
        expect_value(failures, values, "executes git add", "no")
        expect_value(failures, values, "executes real git add", "no")
        expect_value(failures, values, "stage command draft syntax", "pass")
        expect_value(failures, values, "stage command draft matches public batch", "yes")
        expect_value(failures, values, "stage command draft contains do-not-stage paths", "no")
        expect_value(failures, values, "stage command dry-run", "pass")
        expect_value(failures, values, "stage command dry-run preserves index", "yes")

        if dry_run_index_before.exists() and dry_run_index_after.exists():
            if dry_run_index_before.read_bytes() != dry_run_index_after.read_bytes():
                fail(failures, "stage command dry-run index snapshots differ")

        if values.get("public release batch paths sha256") != values.get("stage command draft paths sha256"):
            fail(failures, "public release batch path hash must equal stage command draft path hash")

    status = "pass" if not failures else "failed"
    with schema_summary.open("w", encoding="utf-8") as handle:
        handle.write("# Leona v0.4 Public Android Release Batch Schema\n\n")
        handle.write(f"- status: {status}\n")
        handle.write(f"- public release batch summary: `{summary_arg or ''}`\n")
        handle.write("- validates path parity: yes\n")
        handle.write("- validates SHA-256 digests: yes\n")
        handle.write("- validates do-not-stage exclusion: yes\n")
        handle.write("- validates dry-run index preservation: yes\n")
        handle.write("- secret values printed: no\n")
        handle.write("- executes git add: no\n")
        handle.write("- creates tag: no\n")
        handle.write("- publishes artifacts: no\n")
        handle.write("- starts paid devices or WeTest sessions: no\n\n")
        handle.write("## Forbidden Public Prefixes\n")
        for prefix in FORBIDDEN_PUBLIC_PREFIXES:
            handle.write(f"- `{prefix}`\n")
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

    print(f"[public-release-batch-schema] summary: {schema_summary}")
    return 0 if status == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
