#!/usr/bin/env python3
"""Validate unified-diff hunk counts for the repository's patch files."""

from __future__ import annotations

import re
import sys
from pathlib import Path

HUNK_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def validate(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    errors: list[str] = []
    hunk_count = 0
    index = 0

    while index < len(lines):
        match = HUNK_RE.match(lines[index])
        if not match:
            index += 1
            continue

        hunk_count += 1
        expected_old = int(match.group(2) or "1")
        expected_new = int(match.group(4) or "1")
        actual_old = 0
        actual_new = 0
        index += 1

        while index < len(lines):
            line = lines[index]
            if HUNK_RE.match(line) or line.startswith("diff --git ") or line.startswith("--- "):
                break
            if line.startswith("\\ No newline at end of file"):
                index += 1
                continue
            if not line:
                errors.append(f"{path}: blank unprefixed line inside unified-diff hunk")
                index += 1
                continue
            prefix = line[0]
            if prefix in (" ", "-"):
                actual_old += 1
            if prefix in (" ", "+"):
                actual_new += 1
            if prefix not in (" ", "+", "-"):
                errors.append(f"{path}: invalid hunk line prefix at line {index + 1}: {line!r}")
            index += 1

        if (actual_old, actual_new) != (expected_old, expected_new):
            errors.append(
                f"{path}: hunk at line {index + 1 - (actual_old + actual_new)} "
                f"declares -{expected_old}/+{expected_new}, "
                f"but contains -{actual_old}/+{actual_new}"
            )

    if hunk_count == 0:
        errors.append(f"{path}: no unified-diff hunks found")
    return errors


def main() -> int:
    roots = [Path("patches/ndk"), Path("patches/llvm_android"), Path("patches/cmake"), Path("patches/llvm_project")]
    files = sorted(path for root in roots for path in root.rglob("*.patch"))
    if not files:
        print("error: no patch files found", file=sys.stderr)
        return 2

    errors = [error for path in files for error in validate(path)]
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"PASS: validated unified-diff hunk counts in {len(files)} patch files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
