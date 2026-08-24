from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


SCHEMA_VERSION = "gogobro-character-attachment-rig-v2"
VALID_MODES = {"RIGID", "FRAME_OVERLAY"}
COLORS = (
    (255, 96, 96, 255),
    (255, 180, 64, 255),
    (255, 230, 80, 255),
    (120, 235, 100, 255),
    (64, 225, 180, 255),
    (70, 210, 255, 255),
    (90, 145, 255, 255),
    (160, 110, 255, 255),
    (230, 105, 255, 255),
    (255, 115, 185, 255),
    (255, 145, 115, 255),
    (190, 220, 90, 255),
    (70, 235, 130, 255),
    (80, 185, 255, 255),
    (205, 130, 255, 255),
)
PROFILE_REGION_ALIASES = {
    "side_left": "hip_left",
    "side_right": "hip_right",
}


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
class RigCheckResult:
    verdict: str
    reason_codes: tuple[str, ...]
    report: dict[str, Any]
    atlas: Image.Image | None
    rig: dict[str, Any] | None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _integer(value: object) -> int:
    if type(value) is not int:
        raise ValueError("non_integer_socket")
    return value


def _pair(value: object) -> tuple[int, int]:
    if type(value) is not list or len(value) != 2:
        raise ValueError("non_integer_socket")
    return (_integer(value[0]), _integer(value[1]))


def _box(value: object) -> tuple[int, int, int, int]:
    if type(value) is not list or len(value) != 4:
        raise ValueError("invalid_reference_region")
    result = tuple(_integer(part) for part in value)
    left, top, right, bottom = result
    if left < 0 or top < 0 or right <= left or bottom <= top:
        raise ValueError("invalid_reference_region")
    return result


def _center(box: tuple[int, int, int, int]) -> tuple[int, int]:
    return ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2)


def _box_is_inside_frame(
    box: tuple[int, int, int, int], frame_size: tuple[int, int]
) -> bool:
    return box[2] <= frame_size[0] and box[3] <= frame_size[1]


def _add_issue(
    issues: dict[tuple[str, str, int, str], dict[str, object]],
    reasons: set[str],
    code: str,
    *,
    animation: str | None = None,
    frame: int | None = None,
    socket: str | None = None,
) -> None:
    reasons.add(code)
    key = (
        code,
        animation or "",
        frame if frame is not None else -1,
        socket or "",
    )
    issues[key] = {
        "animation": animation,
        "frame": frame,
        "socket": socket,
        "code": code,
    }


def _ordered_issues(
    issues: dict[tuple[str, str, int, str], dict[str, object]],
) -> list[dict[str, object]]:
    return [issues[key] for key in sorted(issues)]


def _required_socket_contracts(
    registry_path: Path | None,
    issues: dict[tuple[str, str, int, str], dict[str, object]],
    reasons: set[str],
    trusted_registry: dict[str, object] | None,
    trust_module: Any | None,
) -> tuple[dict[str, dict[str, set[object]]], int]:
    if registry_path is None:
        return {}, 0
    try:
        decoded = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        _add_issue(issues, reasons, "asset_registry_malformed")
        return {}, 0
    if (
        type(decoded) is not dict
        or type(decoded.get("units")) is not list
    ):
        _add_issue(issues, reasons, "asset_registry_malformed")
        return {}, 0
    if trusted_registry is None or trust_module is None:
        _add_issue(issues, reasons, "trusted_character_missing")
    else:
        if decoded.get("schema_version") != trusted_registry.get("schema_version"):
            _add_issue(issues, reasons, "asset_registry_schema_mismatch")

    contracts: dict[str, dict[str, set[object]]] = {}
    item_count = 0
    for unit in decoded["units"]:
        if type(unit) is not dict or unit.get("category") != "item":
            continue
        if "appearance" not in unit:
            continue
        item_count += 1
        appearance = unit.get("appearance")
        asset_id = unit.get("asset_id")
        if (
            type(appearance) is not dict
            or set(appearance) != {"slot", "socket", "mode", "depth"}
            or type(asset_id) is not str
            or not asset_id
        ):
            _add_issue(issues, reasons, "asset_registry_item_appearance_invalid")
            continue
        slot = appearance.get("slot")
        socket = appearance.get("socket")
        mode = appearance.get("mode")
        depth = appearance.get("depth")
        if (
            type(slot) is not str
            or not slot
            or type(socket) is not str
            or not socket
            or type(mode) is not str
            or mode not in VALID_MODES
            or type(depth) is not int
        ):
            _add_issue(
                issues,
                reasons,
                "asset_registry_item_appearance_invalid",
                socket=socket if type(socket) is str else None,
            )
            continue
        contract = contracts.setdefault(
            socket,
            {"slots": set(), "modes": set(), "depths": set(), "asset_ids": set()},
        )
        contract["slots"].add(slot)
        contract["modes"].add(mode)
        contract["depths"].add(depth)
        contract["asset_ids"].add(asset_id)

    if trusted_registry is not None and trust_module is not None:
        if item_count != trusted_registry.get("item_count"):
            _add_issue(issues, reasons, "asset_registry_item_count_mismatch")
        mapping_sha256, mapping_count = trust_module.registry_mapping_sha256(decoded)
        if (
            mapping_count != item_count
            or mapping_sha256 != trusted_registry.get("mapping_sha256")
        ):
            _add_issue(issues, reasons, "asset_registry_mapping_mismatch")
    if item_count == 0 or not contracts:
        _add_issue(issues, reasons, "asset_registry_has_no_item_sockets")
    for socket, contract in contracts.items():
        if len(contract["slots"]) != 1 or len(contract["depths"]) != 1:
            _add_issue(
                issues,
                reasons,
                "asset_registry_socket_contract_conflict",
                socket=socket,
            )
    return contracts, item_count


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


def _positive_fps(value: object) -> int | float:
    if type(value) is int:
        if value > 0:
            return value
        raise ValueError("invalid_animation_fps")
    if type(value) is not float or not math.isfinite(value) or value <= 0:
        raise ValueError("invalid_animation_fps")
    return value


def _source_profile_gate(
    *,
    rig_path: Path,
    rig: dict[str, Any],
    atlas_path: Path,
    animation_id: str,
    binding: dict[str, Any],
    issues: dict[tuple[str, str, int, str], dict[str, object]],
    reasons: set[str],
) -> dict[str, Any]:
    """Bind and align the authored per-frame profile inside the rig gate."""
    gate_reasons: set[str] = set()

    def add(
        code: str,
        *,
        frame: int | None = None,
        region: str | None = None,
    ) -> None:
        gate_reasons.add(code)
        _add_issue(
            issues,
            reasons,
            code,
            animation=animation_id,
            frame=frame,
            socket=region,
        )

    trusted_profile = binding["source_profile"]
    trusted_atlas = binding["atlas"]
    raw_profile_path = rig.get("source_profile")
    profile_path = _resolve_source_profile(rig_path, rig)
    invalid_path = (
        type(raw_profile_path) is not str
        or not raw_profile_path.strip()
        or Path(raw_profile_path).is_absolute()
        or ".." in Path(raw_profile_path).parts
    )
    profile_sha_before = _sha256(profile_path) if profile_path is not None else None
    summary: dict[str, Any] = {
        "animation_id": animation_id,
        "path": str(profile_path) if profile_path is not None else None,
        "relative_path": raw_profile_path if type(raw_profile_path) is str else None,
        "sha256": profile_sha_before,
        "sha256_after": None,
        "changed": False,
        "aligned_region_count": 0,
        "aligned_protected_region_count": 0,
        "expected_frame_count": binding["frame_count"],
        "actual_profile_frame_count": None,
        "actual_rig_frame_count": None,
        "expected_fps": binding["fps"],
        "actual_fps": None,
    }

    if raw_profile_path != trusted_profile["relative_path"]:
        add("source_profile_path_mismatch")
    if invalid_path:
        add("source_profile_path_invalid")
    elif profile_path is None:
        add("source_profile_unavailable")
    else:
        try:
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            if type(profile) is not dict:
                raise ValueError("profile")
            profile_frames = profile.get("frames")
            profile_frame_size = _pair(profile.get("frame_size"))
            profile_atlas_size = _pair(profile.get("atlas_size"))
            profile_atlas_sha = profile.get("character_atlas_sha256")
            if (
                profile_frame_size[0] <= 0
                or profile_frame_size[1] <= 0
                or profile_atlas_size[0] <= 0
                or profile_atlas_size[1] <= 0
                or type(profile_frames) is not list
                or not profile_frames
                or type(profile_atlas_sha) is not str
                or len(profile_atlas_sha) != 64
            ):
                raise ValueError("profile")
            profile_atlas_sha = profile_atlas_sha.lower()
            if any(character not in "0123456789abcdef" for character in profile_atlas_sha):
                raise ValueError("profile")

            animations = rig.get("animations")
            state = animations.get(animation_id) if type(animations) is dict else None
            state_frames = state.get("frames") if type(state) is dict else None
            actual_frame_count = state.get("frame_count") if type(state) is dict else None
            actual_fps = state.get("fps") if type(state) is dict else None
            summary["actual_profile_frame_count"] = len(profile_frames)
            summary["actual_rig_frame_count"] = actual_frame_count
            summary["actual_fps"] = actual_fps

            if profile.get("schema_version") != trusted_profile["schema_version"]:
                add("source_profile_schema_mismatch")
            if profile_sha_before != trusted_profile["sha256"]:
                add("source_profile_hash_mismatch")
            if profile_frame_size != tuple(trusted_atlas["frame_size"]):
                add("source_profile_frame_size_mismatch")
            if profile_atlas_size != tuple(trusted_atlas["atlas_size"]):
                add("source_profile_atlas_size_mismatch")
            actual_atlas_sha = _sha256(atlas_path) if atlas_path.is_file() else None
            if (
                profile_atlas_sha != trusted_atlas["sha256"]
                or actual_atlas_sha != trusted_atlas["sha256"]
            ):
                add("source_profile_atlas_hash_mismatch")
            columns = (
                profile_atlas_size[0] // profile_frame_size[0]
                if profile_atlas_size[0] % profile_frame_size[0] == 0
                else None
            )
            rows = (
                profile_atlas_size[1] // profile_frame_size[1]
                if profile_atlas_size[1] % profile_frame_size[1] == 0
                else None
            )
            trusted_grid = trusted_atlas["grid"]
            if (
                columns != trusted_grid["columns"]
                or rows != trusted_grid["rows"]
                or len(profile_frames) != trusted_grid["columns"]
            ):
                add("source_profile_grid_mismatch")
            if (
                len(profile_frames) != binding["frame_count"]
                or actual_frame_count != binding["frame_count"]
                or type(state_frames) is not list
                or len(state_frames) != binding["frame_count"]
            ):
                add("source_profile_frame_count_mismatch")
            if actual_fps != binding["fps"]:
                add("source_profile_fps_mismatch")

            comparable_frames = min(
                len(profile_frames),
                len(state_frames) if type(state_frames) is list else 0,
            )
            for frame_index in range(comparable_frames):
                profile_frame = profile_frames[frame_index]
                rig_frame = state_frames[frame_index]
                if type(profile_frame) is not dict or type(rig_frame) is not dict:
                    add("source_profile_frame_identity_mismatch", frame=frame_index)
                    continue
                if (
                    profile_frame.get("frame_index") != frame_index
                    or rig_frame.get("frame_index") != frame_index
                ):
                    add("source_profile_frame_identity_mismatch", frame=frame_index)

                attachment_regions = profile_frame.get("attachment_regions")
                face_roi = profile_frame.get("face_roi")
                profile_protected = profile_frame.get("protected_regions")
                rig_regions = rig_frame.get("regions")
                rig_protected = rig_frame.get("protected_regions")
                if (
                    type(attachment_regions) is not dict
                    or not attachment_regions
                    or type(profile_protected) is not dict
                    or not profile_protected
                    or type(rig_regions) is not dict
                    or type(rig_protected) is not dict
                ):
                    add("source_profile_malformed", frame=frame_index)
                    continue

                expected_regions: dict[str, list[int]] = {}
                try:
                    for profile_region_id, raw_box in attachment_regions.items():
                        if type(profile_region_id) is not str:
                            raise ValueError("profile region")
                        region_id = PROFILE_REGION_ALIASES.get(
                            profile_region_id, profile_region_id
                        )
                        if region_id == "face" or region_id in expected_regions:
                            raise ValueError("profile region alias collision")
                        expected_regions[region_id] = list(_box(raw_box))
                    expected_regions["face"] = list(_box(face_roi))
                    expected_protected = {
                        region_id: list(_box(raw_box))
                        for region_id, raw_box in profile_protected.items()
                        if type(region_id) is str
                    }
                    if len(expected_protected) != len(profile_protected):
                        raise ValueError("profile protected region")
                except ValueError:
                    add("source_profile_malformed", frame=frame_index)
                    continue

                for region_id, expected_box in sorted(expected_regions.items()):
                    if rig_regions.get(region_id) != expected_box:
                        add(
                            "source_profile_region_mismatch",
                            frame=frame_index,
                            region=region_id,
                        )
                    else:
                        summary["aligned_region_count"] += 1
                protected_ids = set(expected_protected) | set(rig_protected)
                for region_id in sorted(str(value) for value in protected_ids):
                    if rig_protected.get(region_id) != expected_protected.get(region_id):
                        add(
                            "source_profile_protected_regions_mismatch",
                            frame=frame_index,
                            region=f"protected:{region_id}",
                        )
                    else:
                        summary["aligned_protected_region_count"] += 1
        except (OSError, UnicodeError, json.JSONDecodeError, TypeError, ValueError):
            add("source_profile_malformed")

    profile_sha_after = _sha256(profile_path) if profile_path is not None else None
    summary["sha256_after"] = profile_sha_after
    summary["changed"] = profile_sha_before != profile_sha_after
    if summary["changed"]:
        add("source_profile_modified")
    summary["reason_codes"] = sorted(gate_reasons)
    summary["verdict"] = "hard_fail" if gate_reasons else "rig_pass"
    return summary


def _canonical_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def check_character_socket_rig(
    rig_path: Path,
    atlas_path: Path,
    asset_registry_path: Path | None = None,
) -> RigCheckResult:
    reasons: set[str] = set()
    issues: dict[tuple[str, str, int, str], dict[str, object]] = {}
    before: dict[str, str | None] = {
        "rig": _sha256(rig_path) if rig_path.is_file() else None,
        "atlas": _sha256(atlas_path) if atlas_path.is_file() else None,
        "source_profile": None,
        "asset_registry": (
            _sha256(asset_registry_path)
            if asset_registry_path is not None and asset_registry_path.is_file()
            else None
        ),
    }
    rig: dict[str, Any] | None = None
    atlas: Image.Image | None = None
    metrics: dict[str, Any] = {
        "animation_count": 0,
        "frame_count": 0,
        "socket_count": 0,
        "socket_coverage": 0,
        "socket_positions": {},
        "socket_residuals": {},
        "socket_positions_by_animation": {},
        "socket_residuals_by_animation": {},
        "socket_max_residual_jitter_by_animation": {},
        "animation_fps": {},
        "atlas_columns": 0,
        "atlas_rows": 0,
        "registry_item_count": 0,
        "registry_required_socket_count": 0,
        "registry_required_sockets": {},
        "trusted_catalog_sha256": None,
        "trusted_profile_kind": None,
        "trusted_rig_sha256": None,
        "trusted_rig_id": None,
        "trusted_rig_animation_ids": [],
        "trusted_animation_fps": {},
        "source_profile_gates": {},
        "trusted_opaque_contact_coverage": 0,
        "trusted_opaque_contact_expected": 0,
    }
    try:
        decoded = json.loads(rig_path.read_text(encoding="utf-8"))
        if type(decoded) is not dict:
            raise ValueError("malformed_input")
        rig = decoded
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        _add_issue(issues, reasons, "malformed_input")
    source_profile_path = (
        _resolve_source_profile(rig_path, rig) if rig is not None else None
    )
    before["source_profile"] = (
        _sha256(source_profile_path) if source_profile_path is not None else None
    )
    try:
        with Image.open(atlas_path) as opened:
            atlas = opened.convert("RGBA")
    except (OSError, ValueError):
        _add_issue(issues, reasons, "malformed_input")

    trust_module: Any | None = None
    trusted_character: dict[str, Any] | None = None
    trusted_registry: dict[str, object] | None = None
    trusted_topology: dict[str, dict[str, object]] = {}
    trusted_rig_animations: dict[str, dict[str, Any]] = {}
    try:
        trust_module = _load_trust_module()
        trusted_catalog = trust_module.load_trusted_bindings()
        metrics["trusted_catalog_sha256"] = trust_module.trusted_catalog_sha256()
        character_id = rig.get("character_id") if rig is not None else None
        if type(character_id) is not str:
            raise trust_module.TrustedBindingsError("trusted_character_missing")
        trusted_character = trust_module.character_binding(trusted_catalog, character_id)
        trusted_registry = trusted_character["registry"]
        metrics["trusted_profile_kind"] = trusted_character["profile_kind"]
        trusted_topology = trust_module.profile_topology(trusted_character)
    except (KeyError, OSError, RuntimeError, TypeError, ValueError):
        _add_issue(issues, reasons, "trusted_character_missing")

    if rig is not None and trusted_character is not None:
        trusted_rig_animations = {
            animation_id: animation
            for animation_id, animation in trusted_character["animations"].items()
            if animation["rig_sha256"] == before["rig"]
        }
        if not trusted_rig_animations:
            _add_issue(issues, reasons, "trusted_rig_binding_missing")
        else:
            first_binding = next(iter(trusted_rig_animations.values()))
            trusted_atlas = first_binding["atlas"]
            metrics["trusted_rig_sha256"] = first_binding["rig_sha256"]
            metrics["trusted_rig_id"] = first_binding["rig_id"]
            metrics["trusted_rig_animation_ids"] = sorted(trusted_rig_animations)
            metrics["trusted_animation_fps"] = {
                animation_id: binding["fps"]
                for animation_id, binding in sorted(trusted_rig_animations.items())
            }
            if rig.get("rig_id") != first_binding["rig_id"]:
                _add_issue(issues, reasons, "trusted_rig_id_mismatch")
            if before["atlas"] != trusted_atlas["sha256"]:
                _add_issue(issues, reasons, "trusted_rig_atlas_mismatch")
            atlas_contract = rig.get("atlas")
            if (
                type(atlas_contract) is not dict
                or atlas_contract.get("sha256") != trusted_atlas["sha256"]
                or atlas_contract.get("frame_size") != trusted_atlas["frame_size"]
                or atlas_contract.get("atlas_size") != trusted_atlas["atlas_size"]
                or atlas is None
                or list(atlas.size) != trusted_atlas["atlas_size"]
            ):
                _add_issue(issues, reasons, "trusted_rig_atlas_mismatch")
            rig_animations = rig.get("animations")
            actual_animation_ids = (
                set(rig_animations) if type(rig_animations) is dict else set()
            )
            if actual_animation_ids != set(trusted_rig_animations):
                _add_issue(issues, reasons, "trusted_animation_set_mismatch")
            for animation_id, binding in trusted_rig_animations.items():
                state = (
                    rig_animations.get(animation_id)
                    if type(rig_animations) is dict
                    else None
                )
                binding_atlas = binding["atlas"]
                if (
                    binding["rig_id"] != first_binding["rig_id"]
                    or binding_atlas["sha256"] != trusted_atlas["sha256"]
                    or binding_atlas["frame_size"] != trusted_atlas["frame_size"]
                    or binding_atlas["atlas_size"] != trusted_atlas["atlas_size"]
                    or binding_atlas["grid"]["columns"]
                    != trusted_atlas["grid"]["columns"]
                    or binding_atlas["grid"]["rows"]
                    != trusted_atlas["grid"]["rows"]
                    or type(state) is not dict
                    or state.get("frame_count") != binding["frame_count"]
                    or state.get("fps") != binding["fps"]
                    or state.get("row") != binding_atlas["grid"]["row"]
                    or type(state.get("frames")) is not list
                    or len(state["frames"]) != binding["frame_count"]
                ):
                    _add_issue(
                        issues,
                        reasons,
                        "trusted_animation_binding_mismatch",
                        animation=animation_id,
                    )
            metrics["source_profile_gates"] = {
                animation_id: _source_profile_gate(
                    rig_path=rig_path,
                    rig=rig,
                    atlas_path=atlas_path,
                    animation_id=animation_id,
                    binding=binding,
                    issues=issues,
                    reasons=reasons,
                )
                for animation_id, binding in sorted(trusted_rig_animations.items())
            }

    required_contracts, registry_item_count = _required_socket_contracts(
        asset_registry_path,
        issues,
        reasons,
        trusted_registry,
        trust_module,
    )
    metrics["registry_item_count"] = registry_item_count
    metrics["registry_required_socket_count"] = len(required_contracts)
    metrics["registry_required_sockets"] = {
        socket: {
            "slots": sorted(str(value) for value in contract["slots"]),
            "modes": sorted(str(value) for value in contract["modes"]),
            "depths": sorted(int(value) for value in contract["depths"]),
            "asset_ids": sorted(str(value) for value in contract["asset_ids"]),
        }
        for socket, contract in sorted(required_contracts.items())
    }

    if rig is not None:
        if rig.get("schema_version") != SCHEMA_VERSION:
            _add_issue(issues, reasons, "unsupported_schema")
        for field in ("rig_id", "character_id"):
            if type(rig.get(field)) is not str or not rig[field]:
                _add_issue(issues, reasons, "invalid_contract")
        atlas_contract = rig.get("atlas")
        if type(atlas_contract) is not dict:
            _add_issue(issues, reasons, "invalid_contract")
            atlas_contract = {}
        try:
            frame_size = _pair(atlas_contract.get("frame_size"))
            atlas_size = _pair(atlas_contract.get("atlas_size"))
        except ValueError as error:
            _add_issue(issues, reasons, str(error))
            frame_size = (0, 0)
            atlas_size = (0, 0)
        if frame_size[0] <= 0 or frame_size[1] <= 0:
            _add_issue(issues, reasons, "invalid_contract")
        if atlas_size[0] <= 0 or atlas_size[1] <= 0:
            _add_issue(issues, reasons, "invalid_contract")
        expected_hash = atlas_contract.get("sha256")
        if type(expected_hash) is not str or len(expected_hash) != 64:
            _add_issue(issues, reasons, "invalid_contract")
        elif before["atlas"] != expected_hash.lower():
            _add_issue(issues, reasons, "atlas_hash_mismatch")
        if atlas is not None and atlas.size != atlas_size:
            _add_issue(issues, reasons, "atlas_size_mismatch")

        atlas_columns = 0
        atlas_rows = 0
        if atlas is not None and frame_size[0] > 0 and frame_size[1] > 0:
            if atlas.width % frame_size[0] != 0 or atlas.height % frame_size[1] != 0:
                _add_issue(issues, reasons, "atlas_grid_mismatch")
            else:
                atlas_columns = atlas.width // frame_size[0]
                atlas_rows = atlas.height // frame_size[1]
        metrics["atlas_columns"] = atlas_columns
        metrics["atlas_rows"] = atlas_rows

        catalog = rig.get("socket_catalog")
        animations = rig.get("animations")
        if type(catalog) is not dict or not catalog:
            _add_issue(issues, reasons, "invalid_contract")
            catalog = {}
        if type(animations) is not dict or not animations:
            _add_issue(issues, reasons, "invalid_contract")
            animations = {}
        socket_ids = sorted(catalog)
        metrics["animation_count"] = len(animations)
        metrics["socket_count"] = len(socket_ids)
        for socket_id in socket_ids:
            profile = catalog[socket_id]
            if type(socket_id) is not str or type(profile) is not dict:
                _add_issue(
                    issues,
                    reasons,
                    "invalid_contract",
                    socket=socket_id if type(socket_id) is str else None,
                )
                continue
            if type(profile.get("slot_id")) is not str or not profile["slot_id"]:
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)
            modes = profile.get("allowed_modes")
            if (
                type(modes) is not list
                or not modes
                or any(type(mode) is not str or mode not in VALID_MODES for mode in modes)
            ):
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)
            if (
                type(profile.get("reference_region")) is not str
                or not profile["reference_region"]
            ):
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)
            if type(profile.get("flip_h")) is not bool:
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)
            if type(profile.get("default_depth")) is not int:
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)
            elif profile.get("slot_id") == "back" and profile["default_depth"] >= 0:
                _add_issue(issues, reasons, "back_depth_mismatch", socket=socket_id)
            jitter_limit = profile.get("max_residual_jitter_px")
            if type(jitter_limit) is not int or jitter_limit < 0:
                _add_issue(issues, reasons, "invalid_contract", socket=socket_id)

        for socket_id, required in sorted(trusted_topology.items()):
            profile = catalog.get(socket_id)
            if type(profile) is not dict:
                _add_issue(
                    issues,
                    reasons,
                    "trusted_topology_socket_missing",
                    socket=socket_id,
                )
                continue
            actual_modes = profile.get("allowed_modes")
            if (
                profile.get("slot_id") != required["slot_id"]
                or type(actual_modes) is not list
                or set(actual_modes) != set(required["allowed_modes"])
                or profile.get("default_depth") != required["default_depth"]
            ):
                _add_issue(
                    issues,
                    reasons,
                    "trusted_topology_socket_contract_mismatch",
                    socket=socket_id,
                )

        for socket_id, required in sorted(required_contracts.items()):
            if socket_id not in catalog:
                _add_issue(
                    issues, reasons, "required_socket_missing", socket=socket_id
                )
                continue
            profile = catalog[socket_id]
            if type(profile) is not dict:
                continue
            required_slots = required["slots"]
            required_modes = required["modes"]
            required_depths = required["depths"]
            profile_slot = profile.get("slot_id")
            if type(profile_slot) is not str or required_slots != {profile_slot}:
                _add_issue(
                    issues,
                    reasons,
                    "required_socket_slot_mismatch",
                    socket=socket_id,
                )
            allowed_modes = profile.get("allowed_modes")
            allowed_mode_set = (
                {mode for mode in allowed_modes if type(mode) is str}
                if type(allowed_modes) is list
                else set()
            )
            if not required_modes.issubset(allowed_mode_set):
                _add_issue(
                    issues,
                    reasons,
                    "required_socket_mode_mismatch",
                    socket=socket_id,
                )
            profile_depth = profile.get("default_depth")
            if type(profile_depth) is not int or required_depths != {profile_depth}:
                _add_issue(
                    issues,
                    reasons,
                    "required_socket_depth_mismatch",
                    socket=socket_id,
                )

        coverage = 0
        total_frames = 0
        positions: dict[str, list[list[int]]] = {socket_id: [] for socket_id in socket_ids}
        residuals: dict[str, list[list[int]]] = {socket_id: [] for socket_id in socket_ids}
        positions_by_animation: dict[str, dict[str, list[list[int]]]] = {}
        residuals_by_animation: dict[str, dict[str, list[list[int]]]] = {}
        frame_indexes_by_animation: dict[str, dict[str, list[int]]] = {}
        row_owners: dict[int, str] = {}
        for animation_id in sorted(animations):
            state = animations[animation_id]
            if type(animation_id) is not str or type(state) is not dict:
                _add_issue(issues, reasons, "invalid_contract")
                continue
            frame_count = state.get("frame_count")
            frames = state.get("frames")
            row = state.get("row")
            try:
                fps = _positive_fps(state.get("fps"))
            except ValueError as error:
                _add_issue(
                    issues,
                    reasons,
                    str(error),
                    animation=animation_id,
                )
            else:
                metrics["animation_fps"][animation_id] = fps
            if type(frame_count) is not int or frame_count <= 0 or type(row) is not int or row < 0:
                _add_issue(
                    issues, reasons, "invalid_contract", animation=animation_id
                )
                continue
            if row in row_owners:
                _add_issue(
                    issues,
                    reasons,
                    "animation_row_duplicate",
                    animation=row_owners[row],
                )
                _add_issue(
                    issues,
                    reasons,
                    "animation_row_duplicate",
                    animation=animation_id,
                )
            else:
                row_owners[row] = animation_id
            if atlas_columns > 0 and frame_count != atlas_columns:
                _add_issue(
                    issues,
                    reasons,
                    "animation_column_coverage_mismatch",
                    animation=animation_id,
                )
            if type(frames) is not list or len(frames) != frame_count:
                _add_issue(
                    issues,
                    reasons,
                    "frame_count_mismatch",
                    animation=animation_id,
                )
                continue
            total_frames += frame_count
            if atlas_rows > 0 and row >= atlas_rows:
                _add_issue(
                    issues,
                    reasons,
                    "animation_row_out_of_bounds",
                    animation=animation_id,
                )
            positions_by_animation[animation_id] = {
                socket_id: [] for socket_id in socket_ids
            }
            residuals_by_animation[animation_id] = {
                socket_id: [] for socket_id in socket_ids
            }
            frame_indexes_by_animation[animation_id] = {
                socket_id: [] for socket_id in socket_ids
            }
            for frame_index, frame in enumerate(frames):
                if type(frame) is not dict:
                    _add_issue(
                        issues,
                        reasons,
                        "frame_identity_mismatch",
                        animation=animation_id,
                        frame=frame_index,
                    )
                    continue
                if (
                    type(frame.get("frame_index")) is not int
                    or frame.get("frame_index") != frame_index
                ):
                    _add_issue(
                        issues,
                        reasons,
                        "frame_identity_mismatch",
                        animation=animation_id,
                        frame=frame_index,
                    )
                if frame.get("frame_name") != f"{animation_id}_{frame_index + 1:02d}":
                    _add_issue(
                        issues,
                        reasons,
                        "frame_identity_mismatch",
                        animation=animation_id,
                        frame=frame_index,
                    )
                regions = frame.get("regions")
                protected_regions = frame.get("protected_regions")
                sockets = frame.get("sockets")
                if type(regions) is not dict or type(sockets) is not dict:
                    _add_issue(
                        issues,
                        reasons,
                        "invalid_contract",
                        animation=animation_id,
                        frame=frame_index,
                    )
                    continue
                valid_regions: dict[str, tuple[int, int, int, int]] = {}
                for region_id, raw_box in regions.items():
                    if type(region_id) is not str:
                        _add_issue(
                            issues,
                            reasons,
                            "invalid_reference_region",
                            animation=animation_id,
                            frame=frame_index,
                        )
                        continue
                    try:
                        region_box = _box(raw_box)
                    except ValueError as error:
                        _add_issue(
                            issues,
                            reasons,
                            str(error),
                            animation=animation_id,
                            frame=frame_index,
                        )
                        continue
                    valid_regions[region_id] = region_box
                    if not _box_is_inside_frame(region_box, frame_size):
                        _add_issue(
                            issues,
                            reasons,
                            "region_out_of_bounds",
                            animation=animation_id,
                            frame=frame_index,
                        )
                if type(protected_regions) is not dict or not protected_regions:
                    _add_issue(
                        issues,
                        reasons,
                        "missing_protected_regions",
                        animation=animation_id,
                        frame=frame_index,
                    )
                else:
                    for raw_box in protected_regions.values():
                        try:
                            protected_box = _box(raw_box)
                        except ValueError:
                            _add_issue(
                                issues,
                                reasons,
                                "invalid_protected_region",
                                animation=animation_id,
                                frame=frame_index,
                            )
                            continue
                        if not _box_is_inside_frame(protected_box, frame_size):
                            _add_issue(
                                issues,
                                reasons,
                                "protected_region_out_of_bounds",
                                animation=animation_id,
                                frame=frame_index,
                            )

                socket_keys = {
                    key for key in sockets if type(key) is str
                }
                for missing_socket in sorted(set(trusted_topology) - socket_keys):
                    _add_issue(
                        issues,
                        reasons,
                        "trusted_topology_frame_coverage_mismatch",
                        animation=animation_id,
                        frame=frame_index,
                        socket=missing_socket,
                    )
                for missing_socket in sorted(set(socket_ids) - socket_keys):
                    _add_issue(
                        issues,
                        reasons,
                        "missing_socket",
                        animation=animation_id,
                        frame=frame_index,
                        socket=missing_socket,
                    )
                for unexpected_socket in sorted(socket_keys - set(socket_ids)):
                    _add_issue(
                        issues,
                        reasons,
                        "unexpected_socket",
                        animation=animation_id,
                        frame=frame_index,
                        socket=unexpected_socket,
                    )
                for socket_id in socket_ids:
                    if socket_id not in sockets:
                        continue
                    try:
                        position = _pair(sockets.get(socket_id))
                    except ValueError as error:
                        _add_issue(
                            issues,
                            reasons,
                            str(error),
                            animation=animation_id,
                            frame=frame_index,
                            socket=socket_id,
                        )
                        continue
                    profile = catalog[socket_id]
                    if type(profile) is not dict:
                        continue
                    region_id = profile.get("reference_region")
                    region = valid_regions.get(region_id)
                    if region is None:
                        _add_issue(
                            issues,
                            reasons,
                            "invalid_reference_region",
                            animation=animation_id,
                            frame=frame_index,
                            socket=socket_id,
                        )
                        continue
                    if (
                        position[0] < 0
                        or position[1] < 0
                        or position[0] >= frame_size[0]
                        or position[1] >= frame_size[1]
                    ):
                        _add_issue(
                            issues,
                            reasons,
                            "socket_out_of_bounds",
                            animation=animation_id,
                            frame=frame_index,
                            socket=socket_id,
                        )
                    elif (
                        atlas is not None
                        and trusted_topology.get(socket_id, {}).get(
                            "require_opaque_contact"
                        )
                    ):
                        atlas_x = frame_index * frame_size[0] + position[0]
                        atlas_y = row * frame_size[1] + position[1]
                        if not (
                            0 <= atlas_x < atlas.width
                            and 0 <= atlas_y < atlas.height
                        ):
                            pass
                        elif atlas.getpixel((atlas_x, atlas_y))[3] == 0:
                            _add_issue(
                                issues,
                                reasons,
                                "trusted_topology_transparent_contact",
                                animation=animation_id,
                                frame=frame_index,
                                socket=socket_id,
                            )
                        else:
                            metrics["trusted_opaque_contact_coverage"] += 1
                    if not (
                        region[0] <= position[0] < region[2]
                        and region[1] <= position[1] < region[3]
                    ):
                        _add_issue(
                            issues,
                            reasons,
                            "socket_region_mismatch",
                            animation=animation_id,
                            frame=frame_index,
                            socket=socket_id,
                        )
                    region_center = _center(region)
                    residual = [position[0] - region_center[0], position[1] - region_center[1]]
                    positions[socket_id].append(list(position))
                    residuals[socket_id].append(residual)
                    positions_by_animation[animation_id][socket_id].append(list(position))
                    residuals_by_animation[animation_id][socket_id].append(residual)
                    frame_indexes_by_animation[animation_id][socket_id].append(frame_index)
                    coverage += 1

        if atlas_rows > 0 and set(row_owners) != set(range(atlas_rows)):
            _add_issue(issues, reasons, "animation_row_coverage_mismatch")
        metrics["frame_count"] = total_frames
        metrics["socket_coverage"] = coverage
        metrics["trusted_opaque_contact_expected"] = total_frames * sum(
            1
            for contract in trusted_topology.values()
            if contract.get("require_opaque_contact") is True
        )
        metrics["socket_positions"] = positions
        metrics["socket_residuals"] = residuals
        metrics["socket_positions_by_animation"] = positions_by_animation
        metrics["socket_residuals_by_animation"] = residuals_by_animation
        jitter_by_animation: dict[str, dict[str, int]] = {}
        for animation_id in sorted(residuals_by_animation):
            jitter_by_animation[animation_id] = {}
            for socket_id in socket_ids:
                values = residuals_by_animation[animation_id][socket_id]
                if not values:
                    continue
                x_values = [value[0] for value in values]
                y_values = [value[1] for value in values]
                x_span = max(x_values) - min(x_values)
                y_span = max(y_values) - min(y_values)
                max_jitter = max(x_span, y_span)
                jitter_by_animation[animation_id][socket_id] = max_jitter
                profile = catalog[socket_id]
                limit = (
                    profile.get("max_residual_jitter_px", -1)
                    if type(profile) is dict
                    else -1
                )
                if type(limit) is int and max_jitter > limit:
                    extreme_indexes: set[int] = set()
                    if x_span == max_jitter:
                        extreme_indexes.update(
                            index
                            for index, value in enumerate(x_values)
                            if value == min(x_values) or value == max(x_values)
                        )
                    if y_span == max_jitter:
                        extreme_indexes.update(
                            index
                            for index, value in enumerate(y_values)
                            if value == min(y_values) or value == max(y_values)
                        )
                    frame_indexes = frame_indexes_by_animation[animation_id][socket_id]
                    for value_index in sorted(extreme_indexes):
                        _add_issue(
                            issues,
                            reasons,
                            "socket_residual_jitter",
                            animation=animation_id,
                            frame=frame_indexes[value_index],
                            socket=socket_id,
                        )
        metrics["socket_max_residual_jitter_by_animation"] = jitter_by_animation

    after = {
        "rig": _sha256(rig_path) if rig_path.is_file() else None,
        "atlas": _sha256(atlas_path) if atlas_path.is_file() else None,
        "source_profile": (
            _sha256(source_profile_path)
            if source_profile_path is not None and source_profile_path.is_file()
            else None
        ),
        "asset_registry": (
            _sha256(asset_registry_path)
            if asset_registry_path is not None and asset_registry_path.is_file()
            else None
        ),
    }
    if before != after:
        _add_issue(issues, reasons, "source_changed")
    report = {
        "verdict": "hard_fail" if reasons else "rig_pass",
        "reason_codes": sorted(reasons),
        "issues": _ordered_issues(issues),
        "input_sha256": before,
        "source_integrity": {
            "before": before,
            "after": after,
            "changed_keys": sorted(key for key in before if before[key] != after[key]),
        },
        "metrics": metrics,
    }
    return RigCheckResult(
        verdict=report["verdict"],
        reason_codes=tuple(report["reason_codes"]),
        report=report,
        atlas=atlas,
        rig=rig,
    )


def _draw_cross(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int]) -> None:
    draw.line((x - 3, y, x + 3, y), fill=color, width=1)
    draw.line((x, y - 3, x, y + 3), fill=color, width=1)
    draw.rectangle((x - 1, y - 1, x + 1, y + 1), outline=(255, 255, 255, 255))


def write_outputs(result: RigCheckResult, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    _canonical_json(out_dir / "socket-rig-report.json", result.report)
    if result.atlas is None or result.rig is None:
        return
    atlas_contract = result.rig.get("atlas", {})
    try:
        frame_width, frame_height = _pair(atlas_contract.get("frame_size"))
    except ValueError:
        return
    catalog = result.rig.get("socket_catalog")
    animations = result.rig.get("animations")
    if type(catalog) is not dict or type(animations) is not dict:
        return
    overview = result.atlas.copy()
    overview_draw = ImageDraw.Draw(overview)
    socket_ids = sorted(catalog)
    for animation_id in sorted(animations):
        animation = animations[animation_id]
        if type(animation) is not dict or type(animation.get("frames")) is not list:
            continue
        row = animation.get("row", 0)
        if type(row) is not int:
            continue
        for frame_index, frame in enumerate(animation["frames"]):
            if type(frame) is not dict or type(frame.get("sockets")) is not dict:
                continue
            for socket_index, socket_id in enumerate(socket_ids):
                try:
                    x, y = _pair(frame["sockets"].get(socket_id))
                except ValueError:
                    continue
                _draw_cross(
                    overview_draw,
                    frame_index * frame_width + x,
                    row * frame_height + y,
                    COLORS[socket_index % len(COLORS)],
                )
    overview.save(out_dir / "socket-rig-overview.png")

    for animation_id in sorted(animations):
        animation = animations[animation_id]
        if type(animation) is not dict or type(animation.get("frames")) is not list:
            continue
        frames = animation["frames"]
        row = animation.get("row", 0)
        if type(row) is not int:
            continue
        label_width = 150
        sheet = Image.new(
            "RGBA",
            (label_width + len(frames) * frame_width, len(socket_ids) * frame_height),
            (18, 22, 30, 255),
        )
        draw = ImageDraw.Draw(sheet)
        for socket_index, socket_id in enumerate(socket_ids):
            color = COLORS[socket_index % len(COLORS)]
            row_y = socket_index * frame_height
            draw.text((8, row_y + 8), socket_id, fill=color)
            profile = catalog[socket_id]
            if type(profile) is not dict:
                continue
            draw.text((8, row_y + 24), str(profile.get("slot_id", "")), fill=(210, 215, 225, 255))
            for frame_index, frame in enumerate(frames):
                source = (
                    frame_index * frame_width,
                    row * frame_height,
                    (frame_index + 1) * frame_width,
                    (row + 1) * frame_height,
                )
                cell = result.atlas.crop(source)
                cell_x = label_width + frame_index * frame_width
                sheet.alpha_composite(cell, (cell_x, row_y))
                if type(frame) is not dict:
                    continue
                regions = frame.get("regions", {})
                sockets = frame.get("sockets", {})
                if type(regions) is not dict or type(sockets) is not dict:
                    continue
                try:
                    left, top, right, bottom = _box(regions.get(profile.get("reference_region")))
                    x, y = _pair(sockets.get(socket_id))
                except ValueError:
                    continue
                draw.rectangle(
                    (cell_x + left, row_y + top, cell_x + right - 1, row_y + bottom - 1),
                    outline=(*color[:3], 180),
                )
                _draw_cross(draw, cell_x + x, row_y + y, color)
        sheet.save(out_dir / f"socket-rig-{animation_id}-contact-sheet.png")


def _arguments(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a GOGOBRO per-frame character socket rig.")
    parser.add_argument("--rig", required=True, type=Path)
    parser.add_argument("--atlas", required=True, type=Path)
    parser.add_argument("--asset-registry", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _arguments(argv)
    result = check_character_socket_rig(args.rig, args.atlas, args.asset_registry)
    write_outputs(result, args.out_dir)
    print(json.dumps({"verdict": result.verdict, "reason_codes": result.reason_codes}))
    return 0 if result.verdict == "rig_pass" else 2


if __name__ == "__main__":
    sys.exit(main())
