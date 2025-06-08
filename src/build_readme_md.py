#!/usr/bin/env python
"""Markdown build script."""

import argparse
import logging
import tomllib
from collections.abc import Generator
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader


def main() -> None:
    """Main function."""
    args = _parse_options()
    _set_log_config(args=args)
    logger = logging.getLogger(__name__)
    logger.debug("args: %s", vars(args))
    root_dir = Path(__file__).parent.parent
    readme_md = root_dir / "README.md"
    readme_md_j2 = root_dir / f"{readme_md.name}.j2"
    workflow_dir = root_dir / ".github" / "workflows"
    _render_md(
        workflows=list(_detect_reusable_workflow(workflow_dir=workflow_dir)),
        template_md=readme_md_j2,
        output_md=readme_md,
    )


def _detect_reusable_workflow(
    workflow_dir: Path,
) -> Generator[dict[str, str], None, None]:
    logger = logging.getLogger(__name__)
    _print_log(f"Detect reusable workflows: {workflow_dir}")
    for f in sorted(workflow_dir.iterdir(), key=lambda f: f.name):
        if f.is_file() and f.suffix == ".yml":
            logger.info("Read YAML: %s", f)
            with f.open("r") as y:
                d = yaml.safe_load(y)
            logger.debug("YAML: %s", d)
            if "name" in d and "workflow_call" in d[True]:
                print(f"  - {f}")
                yield {"name": d["name"], "file": f.name}


def _render_md(
    workflows: list[dict[str, str]],
    template_md: Path,
    output_md: Path,
) -> None:
    _print_log(f"Render a Markdown file: {output_md}")
    new_text = (
        Environment(
            loader=FileSystemLoader(template_md.parent, encoding="utf8"),
            autoescape=True,
        )
        .get_template(template_md.name)
        .render(workflows=workflows)
    )
    with output_md.open("w") as f:
        f.write(new_text)


def _print_log(message: str) -> None:
    print(f">>\t{message}", flush=True)


def _set_log_config(args: argparse.Namespace) -> None:
    if args.debug:
        lv = logging.DEBUG
    elif args.info:
        lv = logging.INFO
    else:
        lv = logging.WARNING
    logging.basicConfig(
        format="%(asctime)s %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        level=lv,
    )


def _parse_options() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog=Path(__file__).name,
        description="Markdown build script",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {_extract_version()}",
    )
    log_parser = parser.add_mutually_exclusive_group(required=False)
    log_parser.add_argument(
        "--debug",
        dest="debug",
        action="store_true",
        help="log with DEBUG level",
    )
    log_parser.add_argument(
        "--info",
        dest="info",
        action="store_true",
        help="log with INFO level",
    )
    return parser.parse_args()


def _extract_version() -> str:
    pyproject_toml = Path(__file__).parent / "pyproject.toml"
    if pyproject_toml.is_file():
        with pyproject_toml.open("rb") as f:
            data = tomllib.load(f)
        # Try new format first (project.version), then fall back to poetry format
        if "project" in data and "version" in data["project"]:
            return data["project"]["version"]
        elif (
            "tool" in data
            and "poetry" in data["tool"]
            and "version" in data["tool"]["poetry"]
        ):
            return data["tool"]["poetry"]["version"]
    return "v0.0.0"


if __name__ == "__main__":
    main()
