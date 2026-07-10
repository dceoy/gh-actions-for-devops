#!/usr/bin/env python3
"""Reject dependency versions in workflows that Renovate cannot maintain."""

from __future__ import annotations

import re
import sys
from pathlib import Path

VERSION = r"v?\d+(?:\.\d+)+(?:[-+._][0-9A-Za-z]+)*(?:\.[xX*])?"
VERSION_LITERAL = re.compile(rf"(?<![0-9A-Za-z]){VERSION}(?![0-9A-Za-z])")
MAJOR_SELECTOR = re.compile(r"^['\"]?v?\d+['\"]?$")
RENOVATE = re.compile(
    r"^\s*# renovate: datasource=\S+ depName=\S+(?: versioning=\S+)?\s*$"
)
ALLOW = re.compile(r"^\s*# dependency-version: allow reason=\S.+\s*$")
USES = re.compile(r"^\s*uses:\s*(?P<reference>\S+)")
VERSION_KEY = re.compile(
    r"^\s*(?P<key>(?:[A-Za-z][A-Za-z0-9_]*_VERSION)|(?:node|python|go|java|ruby|dotnet|rust|terraform|terragrunt|hugo|gcloud|uv|r)-version):\s*(?P<value>.+?)\s*$"
)
RUNTIME_MATRIX_KEY = re.compile(
    r"^\s*(?:node|python|go|java|ruby|dotnet|rust|terraform|terragrunt|hugo|r):\s*(?P<value>.+?)\s*$"
)
RUNTIME_INPUT = re.compile(
    r"^\s*(?:node|python|go|java|ruby|dotnet|rust|terraform|terragrunt|hugo|gcloud|uv|r)-version:\s*$"
)
DEFAULT = re.compile(r"^\s*default:\s*(?P<value>.+?)\s*$")
CACHE_KEY = re.compile(r"^\s*(?:key|restore-keys):\s*(?P<value>.+?)\s*$")
CONTAINER = re.compile(r"^\s*(?:container|image):\s*(?P<value>\S+)\s*$")
GENERIC_VERSION_KEY = re.compile(r"^\s*version:\s*(?P<value>.+?)\s*$")
DIGEST_SUFFIX = re.compile(r"@sha256:[0-9a-f]{64}$")
RENOVATE_MANAGED_SHAPE = re.compile(
    r"^\s*(?:[A-Za-z][A-Za-z0-9_]*_VERSION|default):\s*\S.*$"
)
SHELL_VERSION = re.compile(
    rf"\b[A-Za-z_][A-Za-z0-9_]*VERSION\s*=\s*['\"]?{VERSION_LITERAL.pattern}"
)
INSTALL = re.compile(
    r"\b(?:python\s+-m\s+pip|pipx?|uv\s+(?:tool\s+install|run)|uvx|"
    r"npm\s+(?:install|exec)|npx|pnpm\s+(?:add|install|exec|dlx)|yarn|"
    r"bunx?|go\s+(?:install|run)|cargo\s+(?:install|binstall)|rustup|"
    r"gem\s+install|dotnet\s+tool\s+install|apt(?:-get)?|apk|dnf|yum|brew|"
    r"gh\s+extension\s+install)\b",
    re.IGNORECASE,
)
DOWNLOAD = re.compile(r"\b(?:curl|wget)\b|https?://", re.IGNORECASE)
BARE_INSTALLER_SELECTOR = re.compile(r"@\d+(?![0-9A-Za-z.])")
COMMAND_VERSION = re.compile(
    rf"(?:==|@|=|(?<=\w)-|--version\s+)\s*{VERSION_LITERAL.pattern}|"
    rf"{BARE_INSTALLER_SELECTOR.pattern}|"
    rf"\b(?:install|run)\s+(?:\S+\s+){{0,3}}{VERSION_LITERAL.pattern}"
)


def previous_annotation(lines: list[str], index: int) -> str | None:
    """Return the adjacent dependency-version annotation, if present.

    A `# renovate:` comment only counts when it sits directly above a line
    shaped like one of this repository's Renovate regex managers actually
    match (`*_VERSION: <value>` or `default: <value>`); otherwise Renovate
    cannot act on it, so the annotation is not sufficient. `# dependency-
    version: allow` is an explicit, unconditional exception.
    """
    for previous in reversed(lines[:index]):
        if not previous.strip():
            continue
        if RENOVATE.match(previous):
            return "renovate" if RENOVATE_MANAGED_SHAPE.match(lines[index]) else None
        if ALLOW.match(previous):
            return "allow"
        return None
    return None


def container_tag(value: str) -> str | None:
    """Return the literal tag of a container/image reference, if pinned."""
    stripped = value.strip("'\"")
    if DIGEST_SUFFIX.search(stripped):
        return None
    if ":" not in stripped:
        return None
    return stripped.rsplit(":", maxsplit=1)[-1]


def is_dynamic(value: str) -> bool:
    """Return whether a selector is intentionally resolved at workflow runtime."""
    return (
        "${{" in value
        or "$" in value
        or value.strip("'\"")
        in {
            "latest",
            "stable",
            "release",
        }
        or bool(re.fullmatch(r"v?\d+(?:\.\d+)?\.[xX*]", value.strip("'\"")))
    )


def is_runtime_input_default(lines: list[str], index: int) -> bool:
    """Return whether a nearby workflow-call input declares a runtime selector."""
    return any(RUNTIME_INPUT.match(line) for line in lines[max(0, index - 5) : index])


def report(path: Path, line: int, text: str, detail: str) -> str:
    """Build an actionable diagnostic."""
    return f"{path}:{line}: {detail}: {text.strip()}"


def run_blocks(lines: list[str]) -> list[tuple[int, str, list[int]]]:
    """Return literal-block shell snippets with their source line numbers.

    This is deliberately indentation-aware rather than line-oriented so a URL or
    package selector split with a shell continuation remains one command context.
    """
    blocks: list[tuple[int, str, list[int]]] = []
    index = 0
    while index < len(lines):
        match = re.match(r"^(\s*)run:\s*[>|][+-]?\s*(?:#.*)?$", lines[index])
        if not match:
            index += 1
            continue
        indent = len(match.group(1))
        start = index
        content: list[str] = []
        numbers: list[int] = []
        index += 1
        while index < len(lines):
            line = lines[index]
            if line.strip() and len(line) - len(line.lstrip()) <= indent:
                break
            content.append(line.strip())
            numbers.append(index + 1)
            index += 1
        blocks.append((start + 1, " ".join(content), numbers))
    return blocks


def check_file(path: Path) -> list[str]:  # noqa: C901
    """Return unmanaged dependency-version contexts in one workflow."""
    lines = path.read_text(encoding="utf-8").splitlines()
    problems: list[str] = []
    reported: set[int] = set()

    for index, line in enumerate(lines):
        number = index + 1
        annotation = previous_annotation(lines, index)
        uses = USES.match(line)
        if uses:
            reference = uses.group("reference")
            if reference.startswith("./"):
                continue
            revision = reference.rsplit("@", maxsplit=1)[-1]
            if re.fullmatch(r"[0-9a-f]{40}", revision):
                continue
            problems.append(
                report(path, number, line, "unverified action or Docker reference")
            )
            reported.add(number)
            continue

        version_key = VERSION_KEY.match(line) or RUNTIME_MATRIX_KEY.match(line)
        if (
            version_key
            and (
                VERSION_LITERAL.search(version_key.group("value"))
                or MAJOR_SELECTOR.fullmatch(version_key.group("value"))
            )
            and not is_dynamic(version_key.group("value"))
        ):
            if not annotation:
                problems.append(
                    report(path, number, line, "unmanaged runtime or tool version")
                )
                reported.add(number)
            continue

        generic_version = GENERIC_VERSION_KEY.match(line)
        if (
            generic_version
            and (
                VERSION_LITERAL.search(generic_version.group("value"))
                or MAJOR_SELECTOR.fullmatch(generic_version.group("value"))
            )
            and not is_dynamic(generic_version.group("value"))
        ):
            if not annotation:
                problems.append(
                    report(path, number, line, "unmanaged action input version")
                )
                reported.add(number)
            continue

        default = DEFAULT.match(line)
        if (
            default
            and is_runtime_input_default(lines, index)
            and (
                VERSION_LITERAL.search(default.group("value"))
                or MAJOR_SELECTOR.fullmatch(default.group("value"))
            )
            and not is_dynamic(default.group("value"))
        ):
            if not annotation:
                problems.append(
                    report(path, number, line, "unmanaged runtime input version")
                )
                reported.add(number)
            continue

        cache = CACHE_KEY.match(line)
        if (
            cache
            and VERSION_LITERAL.search(cache.group("value"))
            and not is_dynamic(cache.group("value"))
        ):
            problems.append(
                report(path, number, line, "duplicated literal version in cache key")
            )
            reported.add(number)
            continue

        container = CONTAINER.match(line)
        if container:
            tag = container_tag(container.group("value"))
            if (
                tag
                and not is_dynamic(tag)
                and (VERSION_LITERAL.fullmatch(tag) or MAJOR_SELECTOR.fullmatch(tag))
                and not annotation
            ):
                problems.append(
                    report(path, number, line, "unmanaged container image version")
                )
                reported.add(number)
                continue

        if (
            (VERSION_LITERAL.search(line) or BARE_INSTALLER_SELECTOR.search(line))
            and (
                SHELL_VERSION.search(line)
                or (DOWNLOAD.search(line) and "http" in line)
                or (
                    line.lstrip().startswith("run:")
                    and INSTALL.search(line)
                    and COMMAND_VERSION.search(line)
                )
            )
            and not annotation
        ):
            problems.append(report(path, number, line, "unmanaged dependency version"))
            reported.add(number)

    for _start, command, numbers in run_blocks(lines):
        if not (INSTALL.search(command) or DOWNLOAD.search(command)):
            continue
        for line_number in numbers:
            source = lines[line_number - 1]
            if line_number in reported or not (
                (INSTALL.search(command) and COMMAND_VERSION.search(source))
                or (
                    DOWNLOAD.search(command)
                    and "http" in source
                    and VERSION_LITERAL.search(source)
                )
            ):
                continue
            if previous_annotation(lines, line_number - 1):
                continue
            problems.append(
                report(
                    path,
                    line_number,
                    lines[line_number - 1],
                    "unmanaged installed or downloaded version",
                )
            )
            reported.add(line_number)
    return problems


def main(argv: list[str]) -> int:
    """Check supplied workflows, or every tracked workflow in the repository."""
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
