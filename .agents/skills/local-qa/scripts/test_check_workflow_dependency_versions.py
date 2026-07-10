#!/usr/bin/env python3
"""Focused regression tests for workflow dependency-version detection."""
# ruff: noqa: D101, D102

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-workflow-dependency-versions.py")
QA_SCRIPT = Path(__file__).with_name("qa.sh")
REPO_ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        check=True,
        capture_output=True,
        text=True,
        cwd=Path(__file__).parent,
    ).stdout.strip()
)
SPEC = importlib.util.spec_from_file_location("version_check", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
VERSION_CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSION_CHECK)


def _qa_script_checker_invocation(cwd: Path) -> subprocess.CompletedProcess[str]:
    """Reproduce qa.sh's SCRIPT_DIR-based checker invocation, run from cwd.

    The snippet is copied verbatim from qa.sh and executed from a script
    colocated with the real checker so BASH_SOURCE resolves the same way it
    does for qa.sh itself, regardless of the caller's working directory.
    """
    wanted_prefixes = ("SCRIPT_DIR=", "REPO_ROOT=", 'cd "${REPO_ROOT}"')
    lines = QA_SCRIPT.read_text(encoding="utf-8").splitlines()
    snippet = [
        line
        for line in lines
        if line.strip().startswith(wanted_prefixes)
        or "check-workflow-dependency-versions.py" in line
    ]
    assert len(snippet) == 4, snippet
    script_body = "#!/usr/bin/env bash\nset -euo pipefail\n" + "\n".join(snippet) + "\n"
    with tempfile.NamedTemporaryFile(
        "w", suffix=".sh", dir=QA_SCRIPT.parent, delete=False
    ) as handle:
        handle.write(script_body)
        temp_script = Path(handle.name)
    try:
        temp_script.chmod(0o755)
        return subprocess.run(
            ["bash", str(temp_script)],
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        temp_script.unlink()


class QaScriptCheckerInvocationTest(unittest.TestCase):
    def test_invocation_from_repository_root(self) -> None:
        result = _qa_script_checker_invocation(REPO_ROOT)
        assert result.returncode == 0, result.stderr

    def test_invocation_from_different_working_directory(self) -> None:
        result = _qa_script_checker_invocation(REPO_ROOT / "src")
        assert result.returncode == 0, result.stderr


class CheckWorkflowDependencyVersionsTest(unittest.TestCase):
    def check(self, workflow: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "workflow.yml"
            path.write_text(workflow, encoding="utf-8")
            return VERSION_CHECK.check_file(path)

    def test_rejects_supported_installers_and_script_version_variables(self) -> None:
        cases = (
            "run: python -m pip install package==1.2.3",
            "run: pipx install package==1.2.3",
            "run: uv tool install package==1.2.3",
            "run: uvx package@1.2.3",
            "run: npm exec package@1.2.3",
            "run: npx package@1.2.3",
            "run: pnpm add package@1.2.3",
            "run: pnpm dlx package@1.2.3",
            "run: yarn add package@1.2.3",
            "run: bun add package@1.2.3",
            "run: bunx package@1.2.3",
            "run: go install example.invalid/module@v1.2.3",
            "run: go run example.invalid/module@v1.2.3",
            "run: cargo install package --version 1.2.3",
            "run: cargo binstall package --version 1.2.3",
            "run: rustup toolchain install 1.2.3",
            "run: gem install package --version 1.2.3",
            "run: dotnet tool install package --version 1.2.3",
            "run: apt-get install package=1.2.3",
            "run: apk add package=1.2.3",
            "run: dnf install package-1.2.3",
            "run: yum install package-1.2.3",
            "run: brew install package@1.2.3",
            "run: gh extension install owner/package@v1.2.3",
            "run: |\n  TOOL_VERSION=1.2.3\n"
            '  curl -fsSL installer | sh -s -- --version "${TOOL_VERSION}"',
        )
        for case in cases:
            with self.subTest(case=case):
                assert self.check(case)

    def test_rejects_runtime_container_cache_and_multiline_download_versions(
        self,
    ) -> None:
        cases = (
            "python-version: '3.12.1'",
            "inputs:\n  dotnet-version:\n    type: string\n    default: '8.0.422'",
            "matrix:\n  python: [3.12.1]",
            "with:\n  terraform-version: '1.9.8'",
            "services:\n  db:\n    image: postgres:16.4",
            "key: tool-1.2.3",
            "run: |\n  curl --fail --location \\\n    https://example.invalid/releases/download/v1.2.3/tool",
        )
        for case in cases:
            with self.subTest(case=case):
                assert self.check(case)

    def test_allows_annotated_dynamic_and_sha_pinned_values(self) -> None:
        cases = (
            "# renovate: datasource=pypi depName=tool versioning=pep440\n"
            "TOOL_VERSION: '1.2.3'",
            "# renovate: datasource=dotnet-version depName=dotnet\ndefault: '6.0.x'",
            "uses: actions/checkout@0123456789012345678901234567890123456789  # v4.2.0",
            "run: go install example.invalid/tool@latest",
            "node-version: latest",
            "# dependency-version: allow reason=immutable-test-fixture\n"
            "TOOL_VERSION: '1.2.3'",
        )
        for case in cases:
            with self.subTest(case=case):
                assert not self.check(case)

    def test_ignores_non_dependency_numbers(self) -> None:
        cases = (
            "schema-version: '2020-12-01'",
            "port: 8080",
            "timeout-minutes: 30",
            "retention-days: 90",
            "fetch-depth: 0",
            "max-tokens: 100000",
            "run: echo 2026-07-10",
            "uses: actions/checkout@0123456789012345678901234567890123456789  # v4.2.0",
        )
        for case in cases:
            with self.subTest(case=case):
                assert not self.check(case)

    def test_rejects_bare_integer_and_generic_input_versions(self) -> None:
        cases = (
            "image: postgres:16",
            "services:\n  db:\n    image: postgres:16",
            "node-version: 20",
            "run: npx package@1",
            "with:\n  version: 1.2.3",
        )
        for case in cases:
            with self.subTest(case=case):
                assert self.check(case)

    def test_allows_renovate_annotations_on_supported_shapes(self) -> None:
        cases = (
            "# renovate: datasource=npm depName=tool\nTOOL_VERSION: '1.2.3'",
            "inputs:\n  dotnet-version:\n    type: string\n"
            "    # renovate: datasource=dotnet-version depName=dotnet\n"
            "    default: '8.0.422'",
        )
        for case in cases:
            with self.subTest(case=case):
                assert not self.check(case)

    def test_rejects_misplaced_or_unsupported_renovate_annotations(self) -> None:
        cases = (
            "# renovate: datasource=node-version depName=node\nnode-version: 20",
            "# renovate: datasource=docker depName=postgres\nimage: postgres:16",
            "# renovate: datasource=npm depName=tool\nwith:\n  version: 1.2.3",
        )
        for case in cases:
            with self.subTest(case=case):
                assert self.check(case)

    def test_allows_explicit_dependency_version_allow_exception(self) -> None:
        cases = (
            "# dependency-version: allow reason=immutable-test-fixture\n"
            "image: postgres:16",
        )
        for case in cases:
            with self.subTest(case=case):
                assert not self.check(case)


if __name__ == "__main__":
    unittest.main()
