#!/usr/bin/env python3
"""Validate or explicitly reinstall the curated development-preview asset set.

The checked-in manifest is the source of truth for curated geometry, anchors, and
identity. The default command is deliberately read-only. ``--install`` copies
only source files whose bytes already match the manifest; it never derives or
rewrites manifest metadata.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any, Iterator

from PIL import Image


REPO = Path(__file__).resolve().parents[2]
OUTPUT = REPO / "game/assets/gogobro_static_preview"
MANIFEST = REPO / "game/content/assets/gogobro_static_candidate_preview_v1.json"
EVIDENCE = REPO / "tools/assets/gogobro_static_candidate_preview_coverage_v1.json"
EVIDENCE_RESOURCE_PATH = "res://tools/assets/gogobro_static_candidate_preview_coverage_v1.json"
EXPECTED_COUNTS = {
    "weapon": 12,
    "item": 30,
    "upgrade": 5,
    "world": 11,
    "ui_brand": 7,
}
EXPECTED_ROLES = {
    "weapon": "world_sprite",
    "item": "icon",
    "upgrade": "icon",
    "world": "world_sprite",
    "ui_brand": "ui_texture",
}


class PreviewValidationError(RuntimeError):
    """Raised when checked-in preview evidence is inconsistent."""


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PreviewValidationError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise PreviewValidationError(f"JSON root must be an object: {path}")
    return value


def _pair(value: Any, label: str) -> tuple[int, int]:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(not isinstance(component, int) or component <= 0 for component in value)
    ):
        raise PreviewValidationError(f"{label} must be two positive integers")
    return int(value[0]), int(value[1])


def _destination(resource_path: str) -> Path:
    prefix = "res://game/assets/gogobro_static_preview/"
    if not resource_path.startswith(prefix):
        raise PreviewValidationError(f"preview resource escapes preview root: {resource_path}")
    destination = (REPO / resource_path.removeprefix("res://")).resolve()
    try:
        destination.relative_to(OUTPUT.resolve())
    except ValueError as error:
        raise PreviewValidationError(f"preview resource escapes preview root: {resource_path}") from error
    return destination


def _artifact_rows(unit: dict[str, Any]) -> Iterator[tuple[str, dict[str, Any]]]:
    yield "", unit
    variants = unit.get("variants", [])
    if not isinstance(variants, list):
        raise PreviewValidationError(f"variants must be an array: {unit.get('asset_id', '')}")
    selectors: set[str] = set()
    for raw_variant in variants:
        if not isinstance(raw_variant, dict):
            raise PreviewValidationError(f"variant must be an object: {unit.get('asset_id', '')}")
        selector = str(raw_variant.get("selector", ""))
        if not selector or selector in selectors:
            raise PreviewValidationError(
                f"variant selector missing or duplicated: {unit.get('asset_id', '')}/{selector}"
            )
        selectors.add(selector)
        yield selector, raw_variant


def _validate_artifact(
    asset_id: str,
    selector: str,
    artifact: dict[str, Any],
    *,
    verify_resource: bool,
) -> None:
    label = f"{asset_id}/{selector}" if selector else asset_id
    resource_path = str(artifact.get("resource_path", ""))
    source_path = str(artifact.get("source_candidate_path", ""))
    expected_hash = str(artifact.get("sha256", "")).upper()
    expected_size = _pair(artifact.get("pixel_size"), f"{label} pixel_size")
    if not source_path.startswith("GOGOBRO_ASSET_INBOX/") or ".." in Path(source_path).parts:
        raise PreviewValidationError(f"unsafe source path for {label}: {source_path}")
    if len(expected_hash) != 64:
        raise PreviewValidationError(f"invalid sha256 for {label}")
    destination = _destination(resource_path)
    if not verify_resource:
        return
    if not destination.is_file():
        raise PreviewValidationError(f"missing preview resource for {label}: {destination}")
    if sha256(destination) != expected_hash:
        raise PreviewValidationError(f"preview hash mismatch for {label}: {destination}")
    try:
        with Image.open(destination) as image:
            if image.size != expected_size:
                raise PreviewValidationError(
                    f"preview size mismatch for {label}: {image.size} != {expected_size}"
                )
    except OSError as error:
        raise PreviewValidationError(f"unreadable preview PNG for {label}: {error}") from error


def _coverage_payload(manifest: dict[str, Any]) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for unit in manifest.get("units", []):
        variants = []
        for raw_variant in unit.get("variants", []):
            variants.append(
                {
                    "selector": raw_variant["selector"],
                    "resource_path": raw_variant["resource_path"],
                    "source_candidate_path": raw_variant["source_candidate_path"],
                    "sha256": str(raw_variant["sha256"]).upper(),
                    "pixel_size": raw_variant["pixel_size"],
                }
            )
        rows.append(
            {
                "asset_id": unit["asset_id"],
                "category": unit["category"],
                "role": unit["role"],
                "resource_path": unit["resource_path"],
                "source_candidate_path": unit["source_candidate_path"],
                "sha256": str(unit["sha256"]).upper(),
                "pixel_size": unit["pixel_size"],
                "variants": variants,
            }
        )
    return {
        "schema_version": "gogobro-static-candidate-preview-coverage-v1",
        "manifest_path": "res://game/content/assets/gogobro_static_candidate_preview_v1.json",
        "unit_count": len(rows),
        "category_counts": EXPECTED_COUNTS,
        "rows": rows,
    }


def _validate_manifest(manifest: dict[str, Any], *, verify_resources: bool) -> None:
    units = manifest.get("units", [])
    if not isinstance(units, list) or len(units) != 65:
        raise PreviewValidationError("preview manifest must contain exactly 65 units")
    if int(manifest.get("expected_unit_count", -1)) != 65:
        raise PreviewValidationError("expected_unit_count must be 65")
    if manifest.get("category_counts") != EXPECTED_COUNTS:
        raise PreviewValidationError("manifest category_counts do not match 12/30/5/11/7")
    if str(manifest.get("coverage_report_path", "")) != EVIDENCE_RESOURCE_PATH:
        raise PreviewValidationError("manifest coverage_report_path is not the checked-in evidence")

    ids: set[str] = set()
    actual_counts = {category: 0 for category in EXPECTED_COUNTS}
    for raw_unit in units:
        if not isinstance(raw_unit, dict):
            raise PreviewValidationError("preview unit must be an object")
        asset_id = str(raw_unit.get("asset_id", ""))
        category = str(raw_unit.get("category", ""))
        if not asset_id or asset_id in ids or asset_id == "service_carbine":
            raise PreviewValidationError(f"missing, duplicate, or forbidden asset id: {asset_id}")
        if category not in EXPECTED_COUNTS:
            raise PreviewValidationError(f"unknown category for {asset_id}: {category}")
        if str(raw_unit.get("role", "")) != EXPECTED_ROLES[category]:
            raise PreviewValidationError(f"wrong role for {asset_id}")
        if raw_unit.get("preview_alias_asset_ids", []) != []:
            raise PreviewValidationError(f"preview aliases are forbidden: {asset_id}")
        if raw_unit.get("approval_status") != "candidate_preview_only":
            raise PreviewValidationError(f"wrong preview approval status: {asset_id}")
        if raw_unit.get("texture_filter") != "nearest" or raw_unit.get("mipmaps") is not False:
            raise PreviewValidationError(f"wrong texture import contract: {asset_id}")
        ids.add(asset_id)
        actual_counts[category] += 1
        for selector, artifact in _artifact_rows(raw_unit):
            _validate_artifact(
                asset_id,
                selector,
                artifact,
                verify_resource=verify_resources,
            )
    if actual_counts != EXPECTED_COUNTS:
        raise PreviewValidationError(f"actual category counts are wrong: {actual_counts}")


def _validate_evidence(manifest: dict[str, Any]) -> None:
    evidence = load_json(EVIDENCE)
    expected = _coverage_payload(manifest)
    if evidence != expected:
        raise PreviewValidationError("checked-in coverage evidence does not match the manifest")
    expected_hash = str(manifest.get("coverage_report_sha256", "")).upper()
    actual_hash = sha256(EVIDENCE)
    if expected_hash != actual_hash:
        raise PreviewValidationError(
            f"coverage evidence hash mismatch: manifest={expected_hash} actual={actual_hash}"
        )


def _discover_workspace_root(explicit: str | None) -> Path:
    if explicit:
        root = Path(explicit).expanduser().resolve()
        if not (root / "GOGOBRO_ASSET_INBOX").is_dir():
            raise PreviewValidationError(f"source root has no GOGOBRO_ASSET_INBOX: {root}")
        return root
    # A normal checkout may itself be the workspace root, while linked worktrees
    # usually need one or two ancestors. Check both layouts without requiring a flag.
    for candidate in [REPO, REPO.parent, *REPO.parents]:
        if (candidate / "GOGOBRO_ASSET_INBOX").is_dir():
            return candidate.resolve()
    raise PreviewValidationError("could not locate workspace root containing GOGOBRO_ASSET_INBOX")


def _install(manifest: dict[str, Any], source_root: Path) -> int:
    copied = 0
    resolved_source_root = source_root.resolve()
    for unit in manifest["units"]:
        asset_id = str(unit["asset_id"])
        for selector, artifact in _artifact_rows(unit):
            label = f"{asset_id}/{selector}" if selector else asset_id
            source = (resolved_source_root / str(artifact["source_candidate_path"])).resolve()
            try:
                source.relative_to(resolved_source_root)
            except ValueError as error:
                raise PreviewValidationError(f"source escapes workspace root for {label}") from error
            if not source.is_file():
                raise PreviewValidationError(f"missing curated source for {label}: {source}")
            expected_hash = str(artifact["sha256"]).upper()
            if sha256(source) != expected_hash:
                raise PreviewValidationError(f"curated source hash mismatch for {label}: {source}")
            expected_size = _pair(artifact["pixel_size"], f"{label} pixel_size")
            try:
                with Image.open(source) as image:
                    if image.size != expected_size:
                        raise PreviewValidationError(
                            f"curated source size mismatch for {label}: {image.size} != {expected_size}"
                        )
            except OSError as error:
                raise PreviewValidationError(f"unreadable curated source for {label}: {error}") from error
            destination = _destination(str(artifact["resource_path"]))
            if destination.is_file() and sha256(destination) == expected_hash:
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            copied += 1
    return copied


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate without writing (the default)",
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="explicitly copy byte-identical curated sources into the preview tree",
    )
    parser.add_argument(
        "--source-root",
        help="workspace directory containing GOGOBRO_ASSET_INBOX (auto-discovered by default)",
    )
    args = parser.parse_args()
    if args.check and args.install:
        parser.error("--check and --install are mutually exclusive")
    return args


def main() -> int:
    args = parse_args()
    try:
        manifest = load_json(MANIFEST)
        _validate_manifest(manifest, verify_resources=not args.install)
        _validate_evidence(manifest)
        copied = 0
        if args.install:
            copied = _install(manifest, _discover_workspace_root(args.source_root))
            _validate_manifest(manifest, verify_resources=True)
        print(
            json.dumps(
                {
                    "ok": True,
                    "mode": "install" if args.install else "check",
                    "unit_count": 65,
                    "category_counts": EXPECTED_COUNTS,
                    "copied": copied,
                    "manifest": str(MANIFEST),
                    "manifest_sha256": sha256(MANIFEST),
                    "coverage_evidence": str(EVIDENCE),
                    "coverage_evidence_sha256": sha256(EVIDENCE),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 0
    except PreviewValidationError as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False, indent=2))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
