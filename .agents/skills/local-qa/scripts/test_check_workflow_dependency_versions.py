#!/usr/bin/env python3
"""Focused regression tests for workflow dependency-version detection."""
# ruff: noqa: D101, D102

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("check-workflow-dependency-versions.py")
SPEC = importlib.util.spec_from_file_location("version_check", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
VERSION_CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSION_CHECK)


class CheckWorkflowDependencyVersionsTest(unittest.TestCase):
    def check(self, workflow: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "workflow.yml"
            path.write_text(workflow, encoding="utf-8")
            return VERSION_CHECK.check_file(path)

    def test_rejects_exact_versions_in_dependency_contexts(self) -> None:
        cases = (
            "run: pip install tool==1.2.3",
            "run: curl https://example.invalid/releases/download/v1.2.3/tool",
            "key: tool-1.2.3",
            "TOOL_VERSION: 1.2.3",
            "default: 1.2.3",
            "container: example/tool:1.2.3",
        )
        for case in cases:
            with self.subTest(case=case):
                assert self.check(case)

    def test_allows_managed_and_intentionally_floating_versions(self) -> None:
        cases = (
            "# renovate: datasource=pypi depName=tool versioning=pep440\n"
            "TOOL_VERSION: 1.2.3",
            "uses: actions/checkout@0123456789012345678901234567890123456789  # v4.2.0",
            "default: 3.x",
            "run: go install example.invalid/tool@latest",
            "TOOL_VERSION: ${DYNAMIC_VERSION}",
        )
        for case in cases:
            with self.subTest(case=case):
                assert not self.check(case)


if __name__ == "__main__":
    unittest.main()
