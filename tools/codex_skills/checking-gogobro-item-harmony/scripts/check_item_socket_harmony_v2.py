"""Hard-gate a GOGOBRO v2 item appearance against its registry and character rig."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


CONTRACT_SCHEMA = "gogobro-item-appearance-contract-v2"
RIG_SCHEMA = "gogobro-character-attachment-rig-v2"
REPORT_SCHEMA = "gogobro-item-socket-harmony-report-v2"
MODES = {"RIGID", "FRAME_OVERLAY"}
RUBRIC_DIMENSIONS = ("identity", "function", "material", "hierarchy", "originality")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
OUTPUT_NAMES = ("harmony-report.json", "harmony-overlay.png", "harmony-actual-size.png")
MAX_RENDER_SCALE = 8.0


def _load_character_checker() -> Any:
    module_name = "_gogobro_character_socket_checker_v2"
    checker_path = Path(__file__).with_name("check_character_socket_rig.py").resolve()
    spec = importlib.util.spec_from_file_location(module_name, checker_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("character socket checker cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _load_trust_module() -> Any:
    module_name = "_gogobro_trusted_character_bindings"
    module_path = Path(__file__).with_name("trusted_character_bindings.py").resolve()
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("trusted bindings module cannot be loaded")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


@dataclass(frozen=True)
class Inputs:
    rig: Path
    registry: Path
    asset_id: str
    contract: Path
    atlas: Path
    appearance: Path
    out_dir: Path
    visual_rubric: Path | None = None


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if type(value) is not dict:
        raise ValueError("JSON root must be an object")
    return value


def _integer_pair(value: object) -> tuple[int, int]:
    if (
        type(value) is not list
        or len(value) != 2
        or type(value[0]) is not int
        or type(value[1]) is not int
    ):
        raise ValueError("expected an exact two-integer array")
    return value[0], value[1]


def _positive_size(value: object) -> tuple[int, int]:
    width, height = _integer_pair(value)
    if width <= 0 or height <= 0:
        raise ValueError("size must be positive")
    return width, height


def _scale_pair(value: object) -> tuple[float, float]:
    if type(value) is not list or len(value) != 2:
        raise ValueError("render_scale must be a two-number array")
    result: list[float] = []
    for member in value:
        if (
            type(member) not in (int, float)
            or not math.isfinite(member)
            or member <= 0
            or member > MAX_RENDER_SCALE
        ):
            raise ValueError("render_scale values must be finite and positive")
        result.append(float(member))
    return result[0], result[1]


def _exact_keys(value: object, expected: set[str]) -> bool:
    return type(value) is dict and set(value) == expected


def _parse_contract(payload: dict[str, Any], cli_asset_id: str) -> dict[str, Any]:
    if not _exact_keys(
        payload,
        {
            "schema_version",
            "asset_id",
            "character_id",
            "animation_id",
            "appearance",
            "pixel_contract",
            "source_sha256",
        },
    ):
        raise ValueError("invalid top-level keys")
    if payload["schema_version"] != CONTRACT_SCHEMA:
        raise ValueError("unknown appearance contract schema")
    for name in ("asset_id", "character_id", "animation_id"):
        if type(payload[name]) is not str or not payload[name].strip():
            raise ValueError(f"{name} must be a non-empty string")
    if payload["asset_id"] != cli_asset_id:
        raise ValueError("CLI asset ID does not match the contract")

    appearance = payload["appearance"]
    if not _exact_keys(
        appearance,
        {
            "slot",
            "socket",
            "mode",
            "depth",
            "render_scale",
            "rendered_pivot_px",
            "local_offset_px",
        },
    ):
        raise ValueError("invalid appearance keys")
    for name in ("slot", "socket", "mode"):
        if type(appearance[name]) is not str or not appearance[name].strip():
            raise ValueError(f"appearance.{name} must be a non-empty string")
    if appearance["mode"] not in MODES:
        raise ValueError("unknown appearance mode")
    if type(appearance["depth"]) is not int:
        raise ValueError("depth must be an exact integer")
    _scale_pair(appearance["render_scale"])
    _integer_pair(appearance["rendered_pivot_px"])
    _integer_pair(appearance["local_offset_px"])

    pixel = payload["pixel_contract"]
    if not _exact_keys(
        pixel,
        {
            "frame_size_px",
            "source_size_px",
            "frame_layout",
            "logical_pixel_scale",
            "resampling",
            "alpha",
            "transparent_rgb",
            "source_pivot_px",
        },
    ):
        raise ValueError("invalid pixel_contract keys")
    _positive_size(pixel["frame_size_px"])
    _positive_size(pixel["source_size_px"])
    _integer_pair(pixel["source_pivot_px"])
    if type(pixel["logical_pixel_scale"]) is not int or pixel["logical_pixel_scale"] <= 0:
        raise ValueError("logical_pixel_scale must be a positive exact integer")
    if pixel["resampling"] != "nearest":
        raise ValueError("only nearest resampling is permitted")
    if pixel["alpha"] != "binary" or pixel["transparent_rgb"] != "zero":
        raise ValueError("binary alpha and zero transparent RGB are mandatory")
    layout = pixel["frame_layout"]
    if not _exact_keys(layout, {"columns", "rows", "frame_count", "frame_order"}):
        raise ValueError("invalid frame_layout keys")
    for name in ("columns", "rows", "frame_count"):
        if type(layout[name]) is not int or layout[name] <= 0:
            raise ValueError(f"frame_layout.{name} must be a positive exact integer")
    if layout["frame_order"] not in ("single", "animation_sequence"):
        raise ValueError("invalid frame order")

    source_hashes = payload["source_sha256"]
    if not _exact_keys(
        source_hashes,
        {"character_rig", "asset_registry", "character_atlas", "appearance"},
    ):
        raise ValueError("invalid source_sha256 keys")
    for name, digest in source_hashes.items():
        if type(digest) is not str or SHA256_PATTERN.fullmatch(digest) is None:
            raise ValueError(f"invalid SHA-256 for {name}")
    return payload


def _safe_hashes(inputs: Inputs) -> dict[str, str | None]:
    profile_path: Path | None = None
    try:
        profile_path = _resolve_source_profile(inputs.rig, _read_json(inputs.rig))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        pass
    paths = {
        "character_rig": inputs.rig,
        "asset_registry": inputs.registry,
        "character_atlas": inputs.atlas,
        "appearance": inputs.appearance,
        "appearance_contract": inputs.contract,
        "visual_rubric": inputs.visual_rubric,
        "source_profile": profile_path,
    }
    result: dict[str, str | None] = {}
    for name, path in paths.items():
        try:
            result[name] = _sha256(path) if path is not None and path.is_file() else None
        except OSError:
            result[name] = None
    return result


def _source_paths(inputs: Inputs) -> list[Path]:
    result = [inputs.rig, inputs.registry, inputs.contract, inputs.atlas, inputs.appearance]
    if inputs.visual_rubric is not None:
        result.append(inputs.visual_rubric)
    try:
        profile_path = _resolve_source_profile(inputs.rig, _read_json(inputs.rig))
        if profile_path is not None:
            result.append(profile_path)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        pass
    return result


def _output_source_collision(inputs: Inputs) -> bool:
    try:
        source_paths = {path.resolve() for path in _source_paths(inputs)}
        output_root = inputs.out_dir.resolve()
        output_paths = {output_root / name for name in OUTPUT_NAMES}
    except OSError:
        return True
    return output_root in source_paths or bool(output_paths & source_paths)


def _output_dir_has_previous_outputs(inputs: Inputs) -> bool:
    try:
        output_root = inputs.out_dir.resolve()
    except OSError:
        return True
    return any(os.path.lexists(output_root / name) for name in OUTPUT_NAMES)


def _finalize_hard_report(
    report: dict[str, Any], reasons: set[str], inputs: Inputs
) -> dict[str, Any]:
    before = report.get("input_sha256", {})
    after = _safe_hashes(inputs)
    changed = sorted(
        name
        for name in set(before) | set(after)
        if before.get(name) != after.get(name)
    )
    if changed:
        reasons.add("source_modified")
    report["verdict"] = "hard_fail"
    report["reason_codes"] = sorted(reasons)
    report["source_integrity"] = {"before": before, "after": after, "changed": changed}
    return report


def _resolve_source_profile(rig_path: Path, rig: dict[str, Any]) -> Path | None:
    raw_path = rig.get("source_profile")
    if type(raw_path) is not str or not raw_path.strip():
        return None
    relative = Path(raw_path)
    if relative.is_absolute() or ".." in relative.parts:
        return None
    for parent in rig_path.resolve().parents:
        candidate = parent / relative
        if candidate.is_file():
            return candidate
    return None


def _source_profile_gate(
    rig_path: Path,
    rig: dict[str, Any],
    atlas_path: Path,
    atlas_size: tuple[int, int],
    animation_id: str,
    trusted_animation: dict[str, Any] | None,
) -> dict[str, Any]:
    reasons: set[str] = set()
    trusted_profile = (
        trusted_animation.get("source_profile")
        if type(trusted_animation) is dict
        else None
    )
    trusted_atlas = (
        trusted_animation.get("atlas")
        if type(trusted_animation) is dict
        else None
    )
    raw_profile_path = rig.get("source_profile")
    profile_path = _resolve_source_profile(rig_path, rig)
    profile_path_invalid = (
        type(raw_profile_path) is not str
        or not raw_profile_path.strip()
        or Path(raw_profile_path).is_absolute()
        or ".." in Path(raw_profile_path).parts
    )
    profile_sha_before = _sha256(profile_path) if profile_path is not None else None
    summary: dict[str, Any] = {
        "path": str(profile_path) if profile_path is not None else None,
        "sha256": profile_sha_before,
        "sha256_after": None,
        "changed": False,
        "expected_frame_count": None,
        "actual_frame_count": None,
        "expected_fps": (
            trusted_animation.get("fps")
            if type(trusted_animation) is dict
            else None
        ),
        "actual_fps": None,
        "expected_atlas_size": None,
        "actual_atlas_size": list(atlas_size),
        "expected_atlas_sha256": None,
        "actual_atlas_sha256": _sha256(atlas_path),
        "trusted_binding": {
            "source_profile": trusted_profile,
            "atlas": trusted_atlas,
            "frame_count": (
                trusted_animation.get("frame_count")
                if type(trusted_animation) is dict
                else None
            ),
            "fps": (
                trusted_animation.get("fps")
                if type(trusted_animation) is dict
                else None
            ),
        },
    }
    if type(trusted_animation) is not dict:
        reasons.add("trusted_animation_missing")
    elif type(trusted_profile) is not dict or type(trusted_atlas) is not dict:
        reasons.add("trusted_animation_invalid")
    elif raw_profile_path != trusted_profile["relative_path"]:
        reasons.add("source_profile_path_mismatch")
    if profile_path_invalid:
        reasons.add("source_profile_path_invalid")
    elif profile_path is None:
        reasons.add("source_profile_unavailable")
    else:
        try:
            profile = _read_json(profile_path)
            expected_atlas_size = _positive_size(profile.get("atlas_size"))
            expected_frame_size = _positive_size(profile.get("frame_size"))
            profile_frames = profile.get("frames")
            expected_hash = profile.get("character_atlas_sha256")
            expected_schema = (
                trusted_profile.get("schema_version")
                if type(trusted_profile) is dict
                else None
            )
            if profile.get("schema_version") != expected_schema:
                raise ValueError("profile schema")
            if type(profile_frames) is not list or not profile_frames:
                raise ValueError("profile frames")
            if type(expected_hash) is not str or SHA256_PATTERN.fullmatch(expected_hash.lower()) is None:
                raise ValueError("profile atlas hash")
            summary["expected_frame_count"] = len(profile_frames)
            summary["expected_atlas_size"] = list(expected_atlas_size)
            summary["expected_atlas_sha256"] = expected_hash.lower()
            rig_atlas = rig.get("atlas", {})
            rig_frame_size = (
                _positive_size(rig_atlas.get("frame_size")) if type(rig_atlas) is dict else None
            )
            animations = rig.get("animations")
            selected = animations.get(animation_id) if type(animations) is dict else None
            actual_frame_count = selected.get("frame_count") if type(selected) is dict else None
            actual_fps = selected.get("fps") if type(selected) is dict else None
            summary["actual_frame_count"] = actual_frame_count
            summary["actual_fps"] = actual_fps
            if expected_atlas_size != atlas_size:
                reasons.add("source_profile_atlas_size_mismatch")
            if expected_frame_size != rig_frame_size:
                reasons.add("source_profile_frame_size_mismatch")
            if actual_frame_count != len(profile_frames):
                reasons.add("source_profile_frame_count_mismatch")
            if expected_hash.lower() != summary["actual_atlas_sha256"]:
                reasons.add("source_profile_atlas_hash_mismatch")
            if type(trusted_animation) is dict and type(trusted_profile) is dict and type(trusted_atlas) is dict:
                if profile_sha_before != trusted_profile["sha256"]:
                    reasons.add("source_profile_hash_mismatch")
                if summary["actual_atlas_sha256"] != trusted_atlas["sha256"]:
                    reasons.add("trusted_atlas_hash_mismatch")
                if len(profile_frames) != trusted_animation["frame_count"]:
                    reasons.add("trusted_frame_count_mismatch")
                if actual_fps != trusted_animation["fps"]:
                    reasons.add("trusted_fps_mismatch")
                if list(expected_frame_size) != trusted_atlas["frame_size"]:
                    reasons.add("trusted_frame_size_mismatch")
                if list(expected_atlas_size) != trusted_atlas["atlas_size"]:
                    reasons.add("trusted_atlas_size_mismatch")
            expected_columns = expected_atlas_size[0] // expected_frame_size[0]
            expected_rows = expected_atlas_size[1] // expected_frame_size[1]
            trusted_grid = (
                trusted_atlas.get("grid") if type(trusted_atlas) is dict else None
            )
            if (
                expected_atlas_size[0] % expected_frame_size[0]
                or expected_atlas_size[1] % expected_frame_size[1]
                or expected_columns != len(profile_frames)
                or type(trusted_grid) is not dict
                or expected_columns != trusted_grid.get("columns")
                or expected_rows != trusted_grid.get("rows")
            ):
                reasons.add("source_profile_grid_mismatch")
        except (KeyError, OSError, UnicodeError, json.JSONDecodeError, ValueError):
            reasons.add("source_profile_malformed")
    profile_sha_after = _sha256(profile_path) if profile_path is not None else None
    summary["sha256_after"] = profile_sha_after
    summary["changed"] = profile_sha_before != profile_sha_after
    if summary["changed"]:
        reasons.add("source_profile_modified")
    summary["reason_codes"] = sorted(reasons)
    summary["verdict"] = "hard_fail" if reasons else "rig_pass"
    return summary


def _trusted_sources_gate(
    *,
    trust_module: Any,
    character: dict[str, Any],
    animation: dict[str, Any],
    animation_id: str,
    rig: dict[str, Any],
    registry: dict[str, Any],
    atlas_size: tuple[int, int],
    input_hashes: dict[str, str | None],
) -> dict[str, Any]:
    """Bind caller-controlled sources to the checker-owned trust catalog."""
    reasons: set[str] = set()
    trusted_registry = character["registry"]
    trusted_atlas = animation["atlas"]
    trusted_grid = trusted_atlas["grid"]
    actual_mapping_sha256, actual_item_count = trust_module.registry_mapping_sha256(
        registry
    )
    if registry.get("schema_version") != trusted_registry["schema_version"]:
        reasons.add("trusted_registry_schema_mismatch")
    if actual_item_count != trusted_registry["item_count"]:
        reasons.add("trusted_registry_item_count_mismatch")
    if actual_mapping_sha256 != trusted_registry["mapping_sha256"]:
        reasons.add("trusted_registry_mapping_mismatch")
    if input_hashes.get("character_rig") != animation["rig_sha256"]:
        reasons.add("trusted_rig_hash_mismatch")
    if rig.get("rig_id") != animation["rig_id"]:
        reasons.add("trusted_rig_id_mismatch")
    if input_hashes.get("character_atlas") != trusted_atlas["sha256"]:
        reasons.add("trusted_atlas_hash_mismatch")
    if atlas_size != tuple(trusted_atlas["atlas_size"]):
        reasons.add("trusted_atlas_size_mismatch")

    rig_atlas = rig.get("atlas")
    if type(rig_atlas) is not dict:
        reasons.add("trusted_rig_atlas_contract_mismatch")
    else:
        if rig_atlas.get("sha256") != trusted_atlas["sha256"]:
            reasons.add("trusted_rig_atlas_contract_mismatch")
        try:
            actual_frame_size = _positive_size(rig_atlas.get("frame_size"))
            actual_contract_size = _positive_size(rig_atlas.get("atlas_size"))
        except ValueError:
            reasons.add("trusted_rig_atlas_contract_mismatch")
        else:
            if actual_frame_size != tuple(trusted_atlas["frame_size"]):
                reasons.add("trusted_frame_size_mismatch")
            if actual_contract_size != tuple(trusted_atlas["atlas_size"]):
                reasons.add("trusted_atlas_size_mismatch")

    animations = rig.get("animations")
    trusted_rig_animations = {
        candidate_id: candidate
        for candidate_id, candidate in character["animations"].items()
        if candidate["rig_sha256"] == animation["rig_sha256"]
    }
    actual_animation_ids = set(animations) if type(animations) is dict else set()
    expected_animation_ids = set(trusted_rig_animations)
    if actual_animation_ids != expected_animation_ids:
        reasons.add("trusted_animation_set_mismatch")
    for candidate_id, candidate in trusted_rig_animations.items():
        candidate_atlas = candidate["atlas"]
        if (
            candidate["rig_id"] != animation["rig_id"]
            or candidate_atlas["sha256"] != trusted_atlas["sha256"]
            or candidate_atlas["frame_size"] != trusted_atlas["frame_size"]
            or candidate_atlas["atlas_size"] != trusted_atlas["atlas_size"]
            or candidate_atlas["grid"]["columns"] != trusted_grid["columns"]
            or candidate_atlas["grid"]["rows"] != trusted_grid["rows"]
        ):
            reasons.add("trusted_animation_binding_inconsistent")
        state = animations.get(candidate_id) if type(animations) is dict else None
        if type(state) is not dict:
            continue
        if (
            state.get("frame_count") != candidate["frame_count"]
            or state.get("fps") != candidate["fps"]
            or state.get("row") != candidate_atlas["grid"]["row"]
            or type(state.get("frames")) is not list
            or len(state["frames"]) != candidate["frame_count"]
        ):
            reasons.add("trusted_animation_binding_inconsistent")
    selected = animations.get(animation_id) if type(animations) is dict else None
    if type(selected) is not dict:
        reasons.add("trusted_animation_missing")
    else:
        if selected.get("frame_count") != animation["frame_count"]:
            reasons.add("trusted_frame_count_mismatch")
        if selected.get("fps") != animation["fps"]:
            reasons.add("trusted_fps_mismatch")
        if selected.get("row") != trusted_grid["row"]:
            reasons.add("trusted_animation_row_mismatch")
        frames = selected.get("frames")
        if type(frames) is not list or len(frames) != animation["frame_count"]:
            reasons.add("trusted_frame_count_mismatch")

    frame_width, frame_height = trusted_atlas["frame_size"]
    actual_columns = atlas_size[0] // frame_width if atlas_size[0] % frame_width == 0 else None
    actual_rows = atlas_size[1] // frame_height if atlas_size[1] % frame_height == 0 else None
    if actual_columns != trusted_grid["columns"] or actual_rows != trusted_grid["rows"]:
        reasons.add("trusted_atlas_grid_mismatch")

    return {
        "verdict": "hard_fail" if reasons else "rig_pass",
        "reason_codes": sorted(reasons),
        "profile_kind": character["profile_kind"],
        "playable": character["playable"],
        "expected": {
            "rig_id": animation["rig_id"],
            "rig_sha256": animation["rig_sha256"],
            "registry_schema_version": trusted_registry["schema_version"],
            "registry_item_count": trusted_registry["item_count"],
            "registry_mapping_sha256": trusted_registry["mapping_sha256"],
            "atlas_sha256": trusted_atlas["sha256"],
            "frame_size": trusted_atlas["frame_size"],
            "atlas_size": trusted_atlas["atlas_size"],
            "grid": trusted_grid,
            "frame_count": animation["frame_count"],
            "fps": animation["fps"],
            "animation_ids": sorted(expected_animation_ids),
        },
        "actual": {
            "rig_id": rig.get("rig_id"),
            "rig_sha256": input_hashes.get("character_rig"),
            "registry_schema_version": registry.get("schema_version"),
            "registry_item_count": actual_item_count,
            "registry_mapping_sha256": actual_mapping_sha256,
            "atlas_sha256": input_hashes.get("character_atlas"),
            "atlas_size": list(atlas_size),
            "grid": {"columns": actual_columns, "rows": actual_rows},
            "frame_count": selected.get("frame_count") if type(selected) is dict else None,
            "fps": selected.get("fps") if type(selected) is dict else None,
            "row": selected.get("row") if type(selected) is dict else None,
            "animation_ids": sorted(actual_animation_ids),
        },
    }


def _validate_registry(
    registry: dict[str, Any], asset_id: str, appearance: dict[str, Any], reasons: set[str]
) -> dict[str, Any] | None:
    units = registry.get("units")
    if type(units) is not list:
        reasons.add("invalid_asset_registry")
        return None
    matches = [unit for unit in units if type(unit) is dict and unit.get("asset_id") == asset_id]
    if len(matches) != 1:
        reasons.add("registry_asset_not_unique")
        return None
    unit = matches[0]
    if unit.get("category") != "item":
        reasons.add("registry_asset_not_item")
    registered = unit.get("appearance")
    if type(registered) is not dict:
        reasons.add("registry_appearance_missing")
        return unit
    expected = {
        "slot": appearance["slot"],
        "socket": appearance["socket"],
        "mode": appearance["mode"],
        "depth": appearance["depth"],
    }
    actual = {name: registered.get(name) for name in expected}
    if actual != expected or any(type(actual[name]) is not type(expected[name]) for name in expected):
        reasons.add("registry_appearance_mismatch")
    return unit


def _validate_rig(
    rig: dict[str, Any],
    contract: dict[str, Any],
    atlas_size: tuple[int, int],
    reasons: set[str],
) -> tuple[dict[str, Any] | None, tuple[int, int] | None]:
    if rig.get("schema_version") != RIG_SCHEMA:
        reasons.add("invalid_character_rig")
        return None, None
    if rig.get("character_id") != contract["character_id"]:
        reasons.add("rig_character_mismatch")

    atlas_contract = rig.get("atlas")
    catalog = rig.get("socket_catalog")
    animations = rig.get("animations")
    if type(atlas_contract) is not dict or type(catalog) is not dict or type(animations) is not dict:
        reasons.add("invalid_character_rig")
        return None, None
    try:
        frame_size = _positive_size(atlas_contract["frame_size"])
        expected_atlas_size = _positive_size(atlas_contract["atlas_size"])
    except (KeyError, ValueError):
        reasons.add("invalid_character_rig")
        return None, None
    if expected_atlas_size != atlas_size:
        reasons.add("atlas_size_mismatch")

    socket_id = contract["appearance"]["socket"]
    socket_contract = catalog.get(socket_id)
    if type(socket_contract) is not dict:
        reasons.add("rig_socket_missing")
    else:
        if socket_contract.get("slot_id") != contract["appearance"]["slot"]:
            reasons.add("rig_slot_mismatch")
        modes = socket_contract.get("allowed_modes")
        if type(modes) is not list or contract["appearance"]["mode"] not in modes:
            reasons.add("rig_mode_not_allowed")
        if (
            type(socket_contract.get("default_depth")) is not int
            or socket_contract.get("default_depth") != contract["appearance"]["depth"]
        ):
            reasons.add("rig_depth_mismatch")

    catalog_ids = set(catalog)
    for animation_id, animation in animations.items():
        if type(animation_id) is not str or type(animation) is not dict:
            reasons.add("rig_frame_coverage_incomplete")
            continue
        frame_count = animation.get("frame_count")
        row = animation.get("row")
        frames = animation.get("frames")
        if (
            type(frame_count) is not int
            or frame_count <= 0
            or type(row) is not int
            or row < 0
            or type(frames) is not list
            or len(frames) != frame_count
            or frame_count * frame_size[0] > expected_atlas_size[0]
            or (row + 1) * frame_size[1] > expected_atlas_size[1]
        ):
            reasons.add("rig_frame_coverage_incomplete")
            continue
        for index, frame in enumerate(frames):
            if type(frame) is not dict or type(frame.get("frame_index")) is not int:
                reasons.add("rig_frame_coverage_incomplete")
                continue
            sockets = frame.get("sockets")
            if frame["frame_index"] != index or type(sockets) is not dict or set(sockets) != catalog_ids:
                reasons.add("rig_frame_coverage_incomplete")
                continue
            for position in sockets.values():
                try:
                    x, y = _integer_pair(position)
                except ValueError:
                    reasons.add("rig_frame_coverage_incomplete")
                    continue
                if not (0 <= x < frame_size[0] and 0 <= y < frame_size[1]):
                    reasons.add("rig_frame_coverage_incomplete")

    selected = animations.get(contract["animation_id"])
    if type(selected) is not dict:
        reasons.add("rig_animation_missing")
        return None, frame_size
    return selected, frame_size


def _pixel_contract_violations(
    image: Image.Image,
    pixel: dict[str, Any],
    frame_count: int,
) -> list[str]:
    violations: list[str] = []
    rgba = image.convert("RGBA")
    if rgba.size != _positive_size(pixel["source_size_px"]):
        violations.append("appearance_size_mismatch")
        return violations
    raw_rgba = rgba.tobytes()
    alpha_values = set(raw_rgba[3::4])
    if not alpha_values <= {0, 255}:
        violations.append("non_binary_alpha")
    if any(
        raw_rgba[index + 3] == 0 and raw_rgba[index : index + 3] != b"\x00\x00\x00"
        for index in range(0, len(raw_rgba), 4)
    ):
        violations.append("transparent_rgb_not_zero")

    layout = pixel["frame_layout"]
    columns, rows = layout["columns"], layout["rows"]
    if columns * rows != frame_count:
        violations.append("appearance_frame_count_mismatch")
        return violations
    source_width, source_height = rgba.size
    if source_width % columns or source_height % rows:
        violations.append("appearance_layout_not_divisible")
        return violations
    frame_width, frame_height = source_width // columns, source_height // rows
    logical_scale = pixel["logical_pixel_scale"]
    if frame_width % logical_scale or frame_height % logical_scale:
        violations.append("logical_pixel_grid_mismatch")
        return violations
    pixels = rgba.load()
    for frame_index in range(frame_count):
        column = frame_index % columns
        row = frame_index // columns
        origin_x, origin_y = column * frame_width, row * frame_height
        if rgba.crop((origin_x, origin_y, origin_x + frame_width, origin_y + frame_height)).getbbox() is None:
            violations.append("empty_appearance_frame")
            break
        for y in range(origin_y, origin_y + frame_height, logical_scale):
            for x in range(origin_x, origin_x + frame_width, logical_scale):
                expected = pixels[x, y]
                if any(
                    pixels[check_x, check_y] != expected
                    for check_y in range(y, y + logical_scale)
                    for check_x in range(x, x + logical_scale)
                ):
                    violations.append("logical_pixel_grid_mismatch")
                    return violations
    return violations


def _round_pixel(value: float) -> int:
    return int(math.floor(value + 0.5))


def _split_appearance_frames(
    appearance: Image.Image, pixel: dict[str, Any], frame_count: int
) -> list[Image.Image]:
    layout = pixel["frame_layout"]
    columns, rows = layout["columns"], layout["rows"]
    frame_width, frame_height = appearance.width // columns, appearance.height // rows
    result: list[Image.Image] = []
    for index in range(frame_count):
        column, row = index % columns, index // columns
        result.append(
            appearance.crop(
                (
                    column * frame_width,
                    row * frame_height,
                    (column + 1) * frame_width,
                    (row + 1) * frame_height,
                )
            )
        )
    return result


def _render(
    atlas: Image.Image,
    appearance_source: Image.Image,
    selected_animation: dict[str, Any],
    frame_size: tuple[int, int],
    contract: dict[str, Any],
    reasons: set[str],
) -> tuple[Image.Image, Image.Image, list[dict[str, Any]]]:
    appearance = contract["appearance"]
    pixel = contract["pixel_contract"]
    frames = selected_animation["frames"]
    frame_count = selected_animation["frame_count"]
    row = selected_animation["row"]
    mode = appearance["mode"]
    scale_x, scale_y = _scale_pair(appearance["render_scale"])
    pivot_x, pivot_y = _integer_pair(appearance["rendered_pivot_px"])
    source_pivot_x, source_pivot_y = _integer_pair(pixel["source_pivot_px"])
    offset_x, offset_y = _integer_pair(appearance["local_offset_px"])

    source_pivot_in_frame = (
        0 <= source_pivot_x < frame_size[0]
        and 0 <= source_pivot_y < frame_size[1]
    )
    if not source_pivot_in_frame:
        reasons.add("source_pivot_out_of_bounds")
    expected_pivot = (
        (
            _round_pixel(source_pivot_x * scale_x),
            _round_pixel(source_pivot_y * scale_y),
        )
        if source_pivot_in_frame
        else None
    )
    if mode == "RIGID" and (pivot_x, pivot_y) != expected_pivot:
        reasons.add("pivot_scale_mismatch")
    if mode == "FRAME_OVERLAY" and (
        (pivot_x, pivot_y) != (0, 0) or (source_pivot_x, source_pivot_y) != (0, 0)
    ):
        reasons.add("overlay_pivot_must_be_zero")
    if mode == "FRAME_OVERLAY" and (scale_x, scale_y) != (1.0, 1.0):
        reasons.add("overlay_scale_must_be_one")

    layout = pixel["frame_layout"]
    if mode == "RIGID":
        if (
            layout != {"columns": 1, "rows": 1, "frame_count": 1, "frame_order": "single"}
            or appearance_source.size != frame_size
        ):
            reasons.add("rigid_layout_mismatch")
        appearance_frames = [appearance_source] * frame_count
    else:
        if (
            layout["columns"] != frame_count
            or layout["rows"] != 1
            or layout["frame_count"] != frame_count
            or layout["frame_order"] != "animation_sequence"
            or appearance_source.size != (frame_size[0] * frame_count, frame_size[1])
        ):
            reasons.add("overlay_layout_mismatch")
        appearance_frames = _split_appearance_frames(appearance_source, pixel, frame_count)

    overlay = Image.new("RGBA", (frame_size[0] * frame_count, frame_size[1]), (0, 0, 0, 0))
    clean_frames: list[Image.Image] = []
    measurements: list[dict[str, Any]] = []
    for index, frame in enumerate(frames):
        base = atlas.crop(
            (
                index * frame_size[0],
                row * frame_size[1],
                (index + 1) * frame_size[0],
                (row + 1) * frame_size[1],
            )
        ).convert("RGBA")
        source_frame = appearance_frames[index]
        if not (
            0 <= source_pivot_x < source_frame.width
            and 0 <= source_pivot_y < source_frame.height
        ):
            reasons.add("source_pivot_out_of_bounds")
        rendered_width_float = source_frame.width * scale_x
        rendered_height_float = source_frame.height * scale_y
        rendered_width = _round_pixel(rendered_width_float)
        rendered_height = _round_pixel(rendered_height_float)
        if (
            rendered_width <= 0
            or rendered_height <= 0
            or not math.isclose(rendered_width_float, rendered_width)
            or not math.isclose(rendered_height_float, rendered_height)
        ):
            reasons.add("non_integral_render_size")
            rendered_width = max(1, rendered_width)
            rendered_height = max(1, rendered_height)
        if not (0 <= pivot_x < rendered_width and 0 <= pivot_y < rendered_height):
            reasons.add("rendered_pivot_out_of_bounds")
        layer = source_frame.resize((rendered_width, rendered_height), Image.Resampling.NEAREST)
        socket_value = frame.get("sockets", {}).get(appearance["socket"])
        try:
            socket_x, socket_y = _integer_pair(socket_value)
        except ValueError:
            reasons.add("rig_frame_coverage_incomplete")
            socket_x, socket_y = 0, 0
        if mode == "RIGID":
            top_left = (socket_x - pivot_x + offset_x, socket_y - pivot_y + offset_y)
        else:
            top_left = (offset_x, offset_y)

        alpha_box = layer.getbbox()
        placed_alpha_box: list[int] | None = None
        if alpha_box is not None:
            placed_alpha_box = [
                top_left[0] + alpha_box[0],
                top_left[1] + alpha_box[1],
                top_left[0] + alpha_box[2],
                top_left[1] + alpha_box[3],
            ]
            if (
                placed_alpha_box[0] < 0
                or placed_alpha_box[1] < 0
                or placed_alpha_box[2] > frame_size[0]
                or placed_alpha_box[3] > frame_size[1]
            ):
                reasons.add("appearance_cropped")

        item_canvas = Image.new("RGBA", frame_size, (0, 0, 0, 0))
        safe_limit = max(frame_size[0], frame_size[1], rendered_width, rendered_height) * 4
        composite_destination = top_left
        if abs(top_left[0]) > safe_limit or abs(top_left[1]) > safe_limit:
            reasons.add("runtime_transform_out_of_safe_range")
            composite_destination = (0, 0)
        item_canvas.alpha_composite(layer, dest=composite_destination)
        if appearance["depth"] < 0:
            composite = Image.alpha_composite(item_canvas, base)
        else:
            composite = Image.alpha_composite(base, item_canvas)
        clean_frames.append(composite)

        diagnostic = composite.copy()
        draw = ImageDraw.Draw(diagnostic)
        draw.line((socket_x - 2, socket_y, socket_x + 2, socket_y), fill=(255, 0, 255, 255))
        draw.line((socket_x, socket_y - 2, socket_x, socket_y + 2), fill=(255, 0, 255, 255))
        attached_pivot = (
            top_left[0] + pivot_x if mode == "RIGID" else top_left[0],
            top_left[1] + pivot_y if mode == "RIGID" else top_left[1],
        )
        draw.rectangle(
            (attached_pivot[0] - 1, attached_pivot[1] - 1, attached_pivot[0] + 1, attached_pivot[1] + 1),
            outline=(0, 255, 255, 255),
        )
        overlay.alpha_composite(diagnostic, dest=(index * frame_size[0], 0))
        measurements.append(
            {
                "frame_index": index,
                "frame_name": frame.get("frame_name"),
                "socket_position_px": [socket_x, socket_y],
                "rendered_top_left_px": list(top_left),
                "godot_local_position_px": [
                    top_left[0] - frame_size[0] / 2,
                    top_left[1] - frame_size[1] / 2,
                ],
                "rendered_size_px": [rendered_width, rendered_height],
                "rendered_pivot_px": [pivot_x, pivot_y],
                "attached_pivot_px": list(attached_pivot),
                "placed_opaque_bounds_px": placed_alpha_box,
                "overlay_source_frame_index": index if mode == "FRAME_OVERLAY" else 0,
            }
        )

    preview = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    columns = 4
    gap_x, gap_y = 64, 80
    block_width, block_height = frame_size[0] + gap_x, frame_size[1] + gap_y
    rows = math.ceil(frame_count / columns)
    origin_x = (preview.width - min(frame_count, columns) * block_width + gap_x) // 2
    origin_y = (preview.height - rows * block_height + gap_y) // 2
    preview_draw = ImageDraw.Draw(preview)
    for index, composite in enumerate(clean_frames):
        x = origin_x + (index % columns) * block_width
        y = origin_y + (index // columns) * block_height
        preview.alpha_composite(composite, dest=(x, y))
        preview_draw.text((x, y + frame_size[1] + 8), f"frame {index + 1}", fill=(232, 226, 211, 255))
    return overlay, preview, measurements


def _load_visual_rubric(path: Path) -> tuple[dict[str, Any], int]:
    payload = _read_json(path)
    if set(payload) != set(RUBRIC_DIMENSIONS):
        raise ValueError("rubric keys")
    total = 0
    for name in RUBRIC_DIMENSIONS:
        value = payload[name]
        if not _exact_keys(value, {"score", "evidence"}):
            raise ValueError("rubric dimension")
        if (
            type(value["score"]) is not int
            or not 0 <= value["score"] <= 2
            or type(value["evidence"]) is not str
            or not value["evidence"].strip()
        ):
            raise ValueError("rubric value")
        total += value["score"]
    return payload, total


def check(inputs: Inputs) -> tuple[dict[str, Any], Image.Image | None, Image.Image | None]:
    reasons: set[str] = set()
    before = _safe_hashes(inputs)
    report: dict[str, Any] = {
        "schema_version": REPORT_SCHEMA,
        "verdict": "hard_fail",
        "reason_codes": [],
        "asset_id": inputs.asset_id,
        "character_id": None,
        "animation_id": None,
        "appearance_contract": None,
        "registry_mapping": None,
        "trusted_catalog_sha256": None,
        "rig_gate": None,
        "rig_socket_contract": None,
        "measurements": {"frames": []},
        "visual_rubric": None,
        "input_sha256": before,
        "source_integrity": {"before": before, "after": {}, "changed": []},
    }
    overlay: Image.Image | None = None
    preview: Image.Image | None = None

    if _output_source_collision(inputs):
        reasons.add("output_source_collision")
        return _finalize_hard_report(report, reasons, inputs), None, None
    if _output_dir_has_previous_outputs(inputs):
        reasons.add("output_dir_not_clean")
        return _finalize_hard_report(report, reasons, inputs), None, None

    try:
        raw_contract = _read_json(inputs.contract)
        contract = _parse_contract(raw_contract, inputs.asset_id)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        reasons.add("invalid_appearance_contract")
        return _finalize_hard_report(report, reasons, inputs), None, None

    report["character_id"] = contract["character_id"]
    report["animation_id"] = contract["animation_id"]
    report["appearance_contract"] = contract["appearance"]
    expected_hashes = contract["source_sha256"]
    for name, digest in expected_hashes.items():
        if before.get(name) != digest:
            reasons.add(f"{name}_hash_mismatch")

    trust_module: Any | None = None
    trusted_character: dict[str, Any] | None = None
    trusted_animation: dict[str, Any] | None = None
    trusted_binding_reasons: set[str] = set()
    try:
        trust_module = _load_trust_module()
        trusted_catalog = trust_module.load_trusted_bindings()
        report["trusted_catalog_sha256"] = trust_module.trusted_catalog_sha256()
        trusted_character, trusted_animation = trust_module.animation_binding(
            trusted_catalog,
            contract["character_id"],
            contract["animation_id"],
        )
    except (AttributeError, KeyError, OSError, RuntimeError, TypeError, ValueError) as error:
        code = str(error)
        trusted_binding_reasons.add(
            code if code.startswith("trusted_") else "trusted_binding_catalog_failed"
        )
        reasons.update(trusted_binding_reasons)

    try:
        character_checker = _load_character_checker()
        character_gate = character_checker.check_character_socket_rig(
            inputs.rig, inputs.atlas, inputs.registry
        )
        character_metrics = character_gate.report.get("metrics", {})
        report["rig_gate"] = {
            "verdict": character_gate.verdict,
            "reason_codes": list(character_gate.reason_codes),
            "summary": {
                name: character_metrics.get(name)
                for name in (
                    "animation_count",
                    "frame_count",
                    "socket_count",
                    "socket_coverage",
                    "atlas_columns",
                    "atlas_rows",
                    "registry_item_count",
                    "registry_required_socket_count",
                    "trusted_opaque_contact_coverage",
                    "trusted_opaque_contact_expected",
                )
            },
            "source_profile": None,
        }
        if character_gate.verdict != "rig_pass":
            reasons.add("character_rig_gate_failed")
    except (AttributeError, KeyError, OSError, RuntimeError, TypeError, ValueError):
        reasons.add("character_rig_gate_failed")
        report["rig_gate"] = {
            "verdict": "hard_fail",
            "reason_codes": ["character_checker_unavailable"],
            "summary": {},
            "source_profile": None,
        }

    try:
        registry = _read_json(inputs.registry)
        rig = _read_json(inputs.rig)
        with Image.open(inputs.atlas) as opened:
            atlas = opened.convert("RGBA")
        with Image.open(inputs.appearance) as opened:
            appearance_source = opened.convert("RGBA")
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        reasons.add("unreadable_source")
        return _finalize_hard_report(report, reasons, inputs), None, None

    profile_gate = _source_profile_gate(
        inputs.rig,
        rig,
        inputs.atlas,
        atlas.size,
        contract["animation_id"],
        trusted_animation,
    )
    if (
        trust_module is not None
        and trusted_character is not None
        and trusted_animation is not None
    ):
        trust_summary = _trusted_sources_gate(
            trust_module=trust_module,
            character=trusted_character,
            animation=trusted_animation,
            animation_id=contract["animation_id"],
            rig=rig,
            registry=registry,
            atlas_size=atlas.size,
            input_hashes=before,
        )
    else:
        trust_summary = {
            "verdict": "hard_fail",
            "reason_codes": sorted(trusted_binding_reasons),
            "profile_kind": None,
            "playable": None,
            "expected": None,
            "actual": None,
        }
    trust_reason_codes = set(trust_summary["reason_codes"])
    if type(report["rig_gate"]) is dict:
        report["rig_gate"]["source_profile"] = profile_gate
        report["rig_gate"]["trusted_sources"] = trust_summary
        merged_rig_reasons = set(report["rig_gate"].get("reason_codes", []))
        merged_rig_reasons.update(profile_gate["reason_codes"])
        merged_rig_reasons.update(trust_reason_codes)
        report["rig_gate"]["reason_codes"] = sorted(merged_rig_reasons)
        if profile_gate["verdict"] != "rig_pass" or trust_summary["verdict"] != "rig_pass":
            report["rig_gate"]["verdict"] = "hard_fail"
    if profile_gate["verdict"] != "rig_pass":
        reasons.update(profile_gate["reason_codes"])
    reasons.update(trust_reason_codes)

    unit = _validate_registry(registry, inputs.asset_id, contract["appearance"], reasons)
    if unit is not None:
        report["registry_mapping"] = unit.get("appearance")
    atlas_sha = rig.get("atlas", {}).get("sha256") if type(rig.get("atlas")) is dict else None
    if atlas_sha != before.get("character_atlas"):
        reasons.add("atlas_hash_mismatch")
    selected, frame_size = _validate_rig(rig, contract, atlas.size, reasons)
    socket_contract = (
        rig.get("socket_catalog", {}).get(contract["appearance"]["socket"])
        if type(rig.get("socket_catalog")) is dict
        else None
    )
    report["rig_socket_contract"] = socket_contract
    if frame_size is not None and _positive_size(contract["pixel_contract"]["frame_size_px"]) != frame_size:
        reasons.add("frame_size_mismatch")

    if selected is not None and frame_size is not None:
        frame_count = selected.get("frame_count")
        if type(frame_count) is not int or frame_count <= 0:
            reasons.add("rig_frame_coverage_incomplete")
        else:
            mode = contract["appearance"]["mode"]
            expected_source_frame_count = 1 if mode == "RIGID" else frame_count
            reasons.update(
                _pixel_contract_violations(
                    appearance_source, contract["pixel_contract"], expected_source_frame_count
                )
            )
            try:
                overlay, preview, frame_measurements = _render(
                    atlas,
                    appearance_source,
                    selected,
                    frame_size,
                    contract,
                    reasons,
                )
                report["measurements"] = {
                    "frame_count": frame_count,
                    "resolved_frame_count": len(frame_measurements),
                    "frames": frame_measurements,
                }
            except (IndexError, KeyError, MemoryError, OverflowError, TypeError, ValueError):
                reasons.add("unresolvable_runtime_transform")
                overlay = None
                preview = None

    rubric_payload: dict[str, Any] | None = None
    rubric_total: int | None = None
    if inputs.visual_rubric is not None:
        try:
            rubric_payload, rubric_total = _load_visual_rubric(inputs.visual_rubric)
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
            reasons.add("malformed_visual_rubric")
    report["visual_rubric"] = (
        {"dimensions": rubric_payload, "total": rubric_total}
        if rubric_payload is not None
        else None
    )

    after = _safe_hashes(inputs)
    changed = sorted(name for name in before if before[name] != after[name])
    if changed:
        reasons.add("source_modified")
    report["source_integrity"] = {"before": before, "after": after, "changed": changed}
    if reasons:
        report["verdict"] = "hard_fail"
    elif rubric_payload is None:
        report["verdict"] = "review"
        reasons.add("visual_rubric_required")
    elif rubric_total is not None and rubric_total >= 8 and all(
        rubric_payload[name]["score"] > 0 for name in RUBRIC_DIMENSIONS
    ):
        report["verdict"] = "harmony_pass"
    else:
        report["verdict"] = "review"
        reasons.add("visual_rubric_review")
    report["reason_codes"] = sorted(reasons)
    return report, overlay, preview


def _write_json(path: Path, payload: object) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _parse_args() -> Inputs:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rig", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--appearance", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--visual-rubric", type=Path)
    arguments = parser.parse_args()
    return Inputs(
        rig=arguments.rig,
        registry=arguments.registry,
        asset_id=arguments.asset_id,
        contract=arguments.contract,
        atlas=arguments.atlas,
        appearance=arguments.appearance,
        out_dir=arguments.out_dir,
        visual_rubric=arguments.visual_rubric,
    )


def main() -> int:
    inputs = _parse_args()
    if _output_source_collision(inputs) or _output_dir_has_previous_outputs(inputs):
        report, _, _ = check(inputs)
        print(
            json.dumps(
                {
                    "verdict": report["verdict"],
                    "reason_codes": report["reason_codes"],
                    "report": None,
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 2
    inputs.out_dir.mkdir(parents=True, exist_ok=True)
    report, overlay, preview = check(inputs)
    if overlay is not None:
        overlay.save(inputs.out_dir / "harmony-overlay.png")
    if preview is not None:
        preview.save(inputs.out_dir / "harmony-actual-size.png")
    _write_json(inputs.out_dir / "harmony-report.json", report)
    print(
        json.dumps(
            {
                "verdict": report["verdict"],
                "reason_codes": report["reason_codes"],
                "report": str(inputs.out_dir / "harmony-report.json"),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 2 if report["verdict"] == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
