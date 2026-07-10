#!/usr/bin/env python3
"""Reject unmanaged exact dependency versions in GitHub Actions workflows."""

from __future__ import annotations

import re
import sys
from pathlib import Path

SEMVER = r"v?\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?"
EXACT_VERSION = re.compile(rf"\b{SEMVER}\b")
PATCH_WILDCARD_VERSION = r"\d+\.\d+\.[xX*]"
VERSION_SELECTOR = re.compile(rf"\b(?:{SEMVER}|{PATCH_WILDCARD_VERSION})\b")
ANNOTATION = re.compile(
    r"^\s*# renovate: datasource=\S+ depName=\S+(?: versioning=\S+)?\s*$"
)
INSTALL = re.compile(
    rf"\b(?:pip(?:x)?|uv(?: tool)?|npm|pnpm|npx|go|cargo|gem)\s+"
    rf"(?:\S+\s+)*install\b.*(?:==|@){SEMVER}\b"
)
URL = re.compile(rf"https?://\S*(?:releases|archive|download)\S*{SEMVER}\b")
CACHE = re.compile(rf"\b(?:key|restore-keys):.*\b{SEMVER}\b")
VERSION_VALUE = re.compile(rf"^\s*[A-Z][A-Z0-9_]*_VERSION:\s*['\"]?{SEMVER}['\"]?\s*$")
RUNTIME_DEFAULT = re.compile(
    rf"^\s*(?:default|(?:node|python|dotnet|terraform|terragrunt|hugo)-version):\s*['\"]?(?:{SEMVER}|{PATCH_WILDCARD_VERSION})['\"]?\s*$"
)
CONTAINER = re.compile(rf"^\s*(?:container|image):\s*\S+:{SEMVER}\b")


def has_annotation(lines: list[str], index: int) -> bool:
    """Return whether the immediately preceding meaningful line is an annotation."""
    for previous in reversed(lines[:index]):
        if not previous.strip():
            continue
        return bool(ANNOTATION.match(previous))
    return False


def check_file(path: Path) -> list[str]:
    """Return unmanaged exact-version dependency contexts in one workflow."""
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[str] = []
    for index, line in enumerate(lines):
        if not VERSION_SELECTOR.search(line):
            continue
        if line.lstrip().startswith("uses:") or " uses: " in line:
            continue  # SHA-pinned actions are managed by GitHub Actions managers.
        if has_annotation(lines, index):
            continue
        if any(
            pattern.search(line)
            for pattern in (
                INSTALL,
                URL,
                CACHE,
                VERSION_VALUE,
                RUNTIME_DEFAULT,
                CONTAINER,
            )
        ):
            message = f"{path}:{index + 1}: unmanaged exact dependency version"
            problems.append(f"{message}: {line.strip()}")
    return problems


def main(argv: list[str]) -> int:
    """Check the supplied workflow files, or the repository workflow directory."""
    paths = [Path(argument) for argument in argv] or sorted(
        Path(".github/workflows").glob("*.y*ml")
    )
    problems = [problem for path in paths for problem in check_file(path)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
