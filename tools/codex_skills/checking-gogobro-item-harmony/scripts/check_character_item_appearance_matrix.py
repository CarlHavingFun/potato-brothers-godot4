"""Fail closed when a playable character lacks an approved item appearance contract."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


MATRIX_SCHEMA = "gogobro-character-item-appearance-matrix-v1"
REPORT_SCHEMA = "gogobro-character-item-appearance-matrix-report-v1"
OUTPUT_NAME = "appearance-matrix-report.json"


def _load_sibling(module_name: str, filename: str) -> Any:
    module_path = Path(__file__).with_name(filename).resolve()
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _trust_module() -> Any:
    return _load_sibling(
        "_gogobro_trusted_character_bindings",
        "trusted_character_bindings.py",
    )


def _item_checker() -> Any:
    return _load_sibling(
        "_gogobro_item_socket_harmony_v2",
        "check_item_socket_harmony_v2.py",
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if type(payload) is not dict:
        raise ValueError("json_root_not_object")
    return payload


def _exact_keys(value: object, expected: set[str]) -> bool:
    return type(value) is dict and set(value) == expected


def _type_exact_equal(left: object, right: object) -> bool:
    if type(left) is not type(right):
        return False
    if type(left) is dict:
        return set(left) == set(right) and all(
            _type_exact_equal(left[key], right[key]) for key in left
        )
    if type(left) is list:
        return len(left) == len(right) and all(
            _type_exact_equal(left_value, right_value)
            for left_value, right_value in zip(left, right)
        )
    return left == right


def _relative_file(root: Path, raw: object) -> Path:
    if type(raw) is not str or not raw.strip():
        raise ValueError("matrix_path_invalid")
    relative = Path(raw)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("matrix_path_invalid")
    result = root / relative
    if not result.is_file():
        raise ValueError("matrix_source_unavailable")
    return result


def _matrix_source_paths(matrix_path: Path, registry_path: Path) -> set[Path]:
    result = {matrix_path.resolve(), registry_path.resolve()}
    try:
        matrix = _read_json(matrix_path)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        return result
    entries = matrix.get("entries")
    if type(entries) is not list:
        return result
    for entry in entries:
        if type(entry) is not dict:
            continue
        for name in (
            "contract",
            "harmony_report",
            "rig",
            "atlas",
            "appearance",
            "visual_rubric",
        ):
            raw = entry.get(name)
            if type(raw) is not str or not raw.strip():
                continue
            relative = Path(raw)
            if relative.is_absolute() or ".." in relative.parts:
                continue
            result.add((matrix_path.parent / relative).resolve())
    return result


@dataclass(frozen=True)
class MatrixResult:
    verdict: str
    reason_codes: tuple[str, ...]
    report: dict[str, Any]


def check_matrix(matrix_path: Path, registry_path: Path) -> MatrixResult:
    reasons: set[str] = set()
    report: dict[str, Any] = {
        "schema_version": REPORT_SCHEMA,
        "verdict": "hard_fail",
        "reason_codes": [],
        "trusted_catalog_sha256": None,
        "registry_sha256": None,
        "matrix_sha256": None,
        "expected_count": 0,
        "entry_count": 0,
        "rechecked_count": 0,
        "missing": [],
        "unexpected": [],
        "duplicates": [],
        "invalid_entries": [],
        "source_integrity": {"before": {}, "after": {}, "changed": []},
    }
    try:
        matrix = _read_json(matrix_path)
        registry = _read_json(registry_path)
        report["matrix_sha256"] = _sha256(matrix_path)
        report["registry_sha256"] = _sha256(registry_path)
        report["source_integrity"]["before"] = {
            "matrix": report["matrix_sha256"],
            "registry": report["registry_sha256"],
        }
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        reasons.add("matrix_input_unreadable")
        report["reason_codes"] = sorted(reasons)
        return MatrixResult("hard_fail", tuple(sorted(reasons)), report)

    try:
        trust = _trust_module()
        catalog = trust.load_trusted_bindings()
        report["trusted_catalog_sha256"] = trust.trusted_catalog_sha256()
        playable_ids = trust.playable_character_ids(catalog)
    except (AttributeError, KeyError, OSError, RuntimeError, TypeError, ValueError):
        reasons.add("trusted_binding_catalog_failed")
        playable_ids = ()
        trust = None
        catalog = None
    if not playable_ids:
        reasons.add("trusted_playable_character_set_empty")

    if not _exact_keys(matrix, {"schema_version", "entries"}):
        reasons.add("matrix_manifest_invalid")
        entries: list[object] = []
    elif matrix["schema_version"] != MATRIX_SCHEMA or type(matrix["entries"]) is not list:
        reasons.add("matrix_manifest_invalid")
        entries = []
    else:
        entries = matrix["entries"]
    report["entry_count"] = len(entries)

    item_ids: set[str] = set()
    units = registry.get("units")
    if type(units) is not list:
        reasons.add("asset_registry_invalid")
    else:
        for unit in units:
            if type(unit) is not dict or unit.get("category") != "item":
                continue
            asset_id = unit.get("asset_id")
            if "appearance" not in unit:
                continue
            if type(asset_id) is not str or not asset_id or asset_id in item_ids:
                reasons.add("asset_registry_invalid")
                continue
            if not _exact_keys(
                unit.get("appearance"), {"slot", "socket", "mode", "depth"}
            ):
                reasons.add("asset_registry_invalid")
                continue
            item_ids.add(asset_id)

    expected: set[tuple[str, str, str]] = set()
    if trust is not None and catalog is not None:
        mapping_sha256, item_count = trust.registry_mapping_sha256(registry)
        for character_id in playable_ids:
            character = trust.character_binding(catalog, character_id)
            trusted_registry = character["registry"]
            if (
                registry.get("schema_version") != trusted_registry["schema_version"]
                or item_count != trusted_registry["item_count"]
                or mapping_sha256 != trusted_registry["mapping_sha256"]
            ):
                reasons.add("trusted_registry_mapping_mismatch")
            for animation_id in character["animations"]:
                expected.update(
                    (character_id, animation_id, asset_id) for asset_id in item_ids
                )
    report["expected_count"] = len(expected)

    actual_counts: dict[tuple[str, str, str], int] = {}
    matrix_root = matrix_path.parent
    seen_contract_paths: set[Path] = set()
    seen_report_paths: set[Path] = set()
    item_checker = None
    try:
        item_checker = _item_checker()
    except (OSError, RuntimeError):
        reasons.add("item_checker_unavailable")

    for index, entry in enumerate(entries):
        entry_reasons: set[str] = set()
        key: tuple[str, str, str] | None = None
        if not _exact_keys(
            entry,
            {
                "character_id",
                "animation_id",
                "asset_id",
                "contract",
                "harmony_report",
                "rig",
                "atlas",
                "appearance",
                "visual_rubric",
            },
        ):
            entry_reasons.add("matrix_entry_invalid")
        else:
            identity = [entry.get(name) for name in ("character_id", "animation_id", "asset_id")]
            if any(type(value) is not str or not value for value in identity):
                entry_reasons.add("matrix_entry_invalid")
            else:
                key = identity[0], identity[1], identity[2]
                actual_counts[key] = actual_counts.get(key, 0) + 1
            try:
                contract_path = _relative_file(matrix_root, entry["contract"])
                harmony_path = _relative_file(matrix_root, entry["harmony_report"])
                rig_path = _relative_file(matrix_root, entry["rig"])
                atlas_path = _relative_file(matrix_root, entry["atlas"])
                appearance_path = _relative_file(matrix_root, entry["appearance"])
                rubric_path = _relative_file(matrix_root, entry["visual_rubric"])
            except ValueError as error:
                entry_reasons.add(str(error))
            else:
                resolved_contract = contract_path.resolve()
                resolved_report = harmony_path.resolve()
                if resolved_contract in seen_contract_paths or resolved_report in seen_report_paths:
                    entry_reasons.add("matrix_source_reused")
                seen_contract_paths.add(resolved_contract)
                seen_report_paths.add(resolved_report)
                try:
                    contract = _read_json(contract_path)
                    harmony = _read_json(harmony_path)
                    harmony_sha_before = _sha256(harmony_path)
                    if item_checker is None or key is None:
                        raise ValueError("matrix_entry_invalid")
                    item_checker._parse_contract(contract, key[2])
                    if (
                        contract["character_id"] != key[0]
                        or contract["animation_id"] != key[1]
                    ):
                        entry_reasons.add("matrix_contract_identity_mismatch")
                    with tempfile.TemporaryDirectory(
                        prefix="gogobro-matrix-recheck-"
                    ) as recheck_root:
                        recheck, _, _ = item_checker.check(
                            item_checker.Inputs(
                                rig=rig_path,
                                registry=registry_path,
                                asset_id=key[2],
                                contract=contract_path,
                                atlas=atlas_path,
                                appearance=appearance_path,
                                out_dir=Path(recheck_root),
                                visual_rubric=rubric_path,
                            )
                        )
                    report["rechecked_count"] += 1
                    if recheck.get("verdict") != "harmony_pass":
                        entry_reasons.add("matrix_harmony_recheck_failed")
                    if not _type_exact_equal(harmony, recheck):
                        entry_reasons.add("matrix_harmony_report_invalid")
                    if _sha256(harmony_path) != harmony_sha_before:
                        entry_reasons.add("matrix_source_modified")
                except (
                    AttributeError,
                    KeyError,
                    OSError,
                    RuntimeError,
                    TypeError,
                    UnicodeError,
                    json.JSONDecodeError,
                    ValueError,
                ):
                    entry_reasons.add("matrix_entry_source_invalid")
        if entry_reasons:
            report["invalid_entries"].append(
                {"index": index, "reason_codes": sorted(entry_reasons)}
            )
            reasons.update(entry_reasons)

    actual = set(actual_counts)
    report["missing"] = [list(key) for key in sorted(expected - actual)]
    report["unexpected"] = [list(key) for key in sorted(actual - expected)]
    report["duplicates"] = [
        {"key": list(key), "count": count}
        for key, count in sorted(actual_counts.items())
        if count != 1
    ]
    if report["missing"]:
        reasons.add("appearance_matrix_incomplete")
    if report["unexpected"]:
        reasons.add("appearance_matrix_unexpected_entry")
    if report["duplicates"]:
        reasons.add("appearance_matrix_duplicate_entry")

    try:
        source_after = {
            "matrix": _sha256(matrix_path),
            "registry": _sha256(registry_path),
        }
    except OSError:
        source_after = {"matrix": None, "registry": None}
    source_before = report["source_integrity"]["before"]
    source_changed = sorted(
        name for name in source_before if source_before[name] != source_after[name]
    )
    report["source_integrity"] = {
        "before": source_before,
        "after": source_after,
        "changed": source_changed,
    }
    if source_changed:
        reasons.add("matrix_source_modified")

    report["verdict"] = "matrix_pass" if not reasons else "hard_fail"
    report["reason_codes"] = sorted(reasons)
    return MatrixResult(report["verdict"], tuple(sorted(reasons)), report)


def _write_report(path: Path, payload: object) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    output_path = args.out_dir / OUTPUT_NAME
    try:
        collision = output_path.resolve() in _matrix_source_paths(
            args.matrix, args.registry
        )
    except OSError:
        collision = True
    if collision or os.path.lexists(output_path):
        print(json.dumps({"verdict": "hard_fail", "reason_codes": ["output_collision"]}))
        return 2
    result = check_matrix(args.matrix, args.registry)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    _write_report(output_path, result.report)
    print(
        json.dumps(
            {
                "verdict": result.verdict,
                "reason_codes": result.reason_codes,
                "report": str(output_path),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0 if result.verdict == "matrix_pass" else 2


if __name__ == "__main__":
    raise SystemExit(main())
