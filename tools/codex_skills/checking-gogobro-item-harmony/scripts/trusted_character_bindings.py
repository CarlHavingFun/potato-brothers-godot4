"""Load the checker-owned GOGOBRO character/animation trust catalog."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "gogobro-trusted-character-animation-bindings-v1"
BINDINGS_PATH = (
    Path(__file__).parents[1]
    / "references"
    / "trusted-character-animation-bindings-v1.json"
)
VALID_MODES = {"RIGID", "FRAME_OVERLAY"}
SHA256_LENGTH = 64

# Profile kinds are code-reviewed topology policies. The catalog must choose one
# explicitly; callers cannot invent a kind or provide a replacement catalog.
PROFILE_KINDS: dict[str, dict[str, dict[str, object]]] = {
    "humanoid_v1": {
        "clothes_body": {
            "slot_id": "clothes",
            "allowed_modes": ["FRAME_OVERLAY"],
            "default_depth": 20,
            "require_opaque_contact": True,
        },
        "shoulder_left": {
            "slot_id": "arm_left",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "upper_arm_left": {
            "slot_id": "arm_left",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "forearm_left": {
            "slot_id": "arm_left",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "hand_left": {
            "slot_id": "arm_left",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "shoulder_right": {
            "slot_id": "arm_right",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "upper_arm_right": {
            "slot_id": "arm_right",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "forearm_right": {
            "slot_id": "arm_right",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
        "hand_right": {
            "slot_id": "arm_right",
            "allowed_modes": ["RIGID", "FRAME_OVERLAY"],
            "default_depth": 50,
            "require_opaque_contact": True,
        },
    }
}


class TrustedBindingsError(ValueError):
    pass


def _exact_keys(value: object, expected: set[str]) -> bool:
    return type(value) is dict and set(value) == expected


def _nonempty_string(value: object) -> str:
    if type(value) is not str or not value.strip():
        raise TrustedBindingsError("trusted_binding_invalid_string")
    return value


def _sha256_string(value: object) -> str:
    result = _nonempty_string(value)
    if len(result) != SHA256_LENGTH or any(character not in "0123456789abcdef" for character in result):
        raise TrustedBindingsError("trusted_binding_invalid_sha256")
    return result


def _positive_integer(value: object) -> int:
    if type(value) is not int or value <= 0:
        raise TrustedBindingsError("trusted_binding_invalid_integer")
    return value


def _positive_fps(value: object) -> int | float:
    if type(value) is int:
        if value > 0:
            return value
        raise TrustedBindingsError("trusted_binding_invalid_fps")
    if type(value) is not float or not math.isfinite(value) or value <= 0:
        raise TrustedBindingsError("trusted_binding_invalid_fps")
    return value


def _nonnegative_integer(value: object) -> int:
    if type(value) is not int or value < 0:
        raise TrustedBindingsError("trusted_binding_invalid_integer")
    return value


def _positive_size(value: object) -> tuple[int, int]:
    if type(value) is not list or len(value) != 2:
        raise TrustedBindingsError("trusted_binding_invalid_size")
    return _positive_integer(value[0]), _positive_integer(value[1])


def _relative_path(value: object) -> str:
    result = _nonempty_string(value)
    path = Path(result)
    if path.is_absolute() or ".." in path.parts:
        raise TrustedBindingsError("trusted_binding_invalid_relative_path")
    return result


def _validate_animation(animation: object) -> None:
    if not _exact_keys(
        animation,
        {"rig_id", "rig_sha256", "source_profile", "atlas", "frame_count", "fps"},
    ):
        raise TrustedBindingsError("trusted_animation_invalid_shape")
    _nonempty_string(animation["rig_id"])
    _sha256_string(animation["rig_sha256"])
    frame_count = _positive_integer(animation["frame_count"])
    _positive_fps(animation["fps"])

    source_profile = animation["source_profile"]
    if not _exact_keys(source_profile, {"relative_path", "schema_version", "sha256"}):
        raise TrustedBindingsError("trusted_source_profile_invalid_shape")
    _relative_path(source_profile["relative_path"])
    _nonempty_string(source_profile["schema_version"])
    _sha256_string(source_profile["sha256"])

    atlas = animation["atlas"]
    if not _exact_keys(atlas, {"sha256", "frame_size", "atlas_size", "grid"}):
        raise TrustedBindingsError("trusted_atlas_invalid_shape")
    _sha256_string(atlas["sha256"])
    frame_width, frame_height = _positive_size(atlas["frame_size"])
    atlas_width, atlas_height = _positive_size(atlas["atlas_size"])
    grid = atlas["grid"]
    if not _exact_keys(grid, {"columns", "rows", "row"}):
        raise TrustedBindingsError("trusted_grid_invalid_shape")
    columns = _positive_integer(grid["columns"])
    rows = _positive_integer(grid["rows"])
    row = _nonnegative_integer(grid["row"])
    if (
        row >= rows
        or frame_count != columns
        or atlas_width != frame_width * columns
        or atlas_height != frame_height * rows
    ):
        raise TrustedBindingsError("trusted_grid_inconsistent")


def _validate_catalog(payload: object) -> dict[str, Any]:
    if not _exact_keys(payload, {"schema_version", "characters"}):
        raise TrustedBindingsError("trusted_catalog_invalid_shape")
    if payload["schema_version"] != SCHEMA_VERSION:
        raise TrustedBindingsError("trusted_catalog_unknown_schema")
    characters = payload["characters"]
    if type(characters) is not dict or not characters:
        raise TrustedBindingsError("trusted_catalog_has_no_characters")
    for character_id, character in characters.items():
        _nonempty_string(character_id)
        if not _exact_keys(
            character, {"playable", "profile_kind", "registry", "animations"}
        ):
            raise TrustedBindingsError("trusted_character_invalid_shape")
        if type(character["playable"]) is not bool:
            raise TrustedBindingsError("trusted_character_invalid_playable_flag")
        profile_kind = _nonempty_string(character["profile_kind"])
        if profile_kind not in PROFILE_KINDS:
            raise TrustedBindingsError("trusted_profile_kind_unknown")
        registry = character["registry"]
        if not _exact_keys(registry, {"schema_version", "item_count", "mapping_sha256"}):
            raise TrustedBindingsError("trusted_registry_invalid_shape")
        _nonempty_string(registry["schema_version"])
        _positive_integer(registry["item_count"])
        _sha256_string(registry["mapping_sha256"])
        animations = character["animations"]
        if type(animations) is not dict or not animations:
            raise TrustedBindingsError("trusted_character_has_no_animations")
        for animation_id, animation in animations.items():
            _nonempty_string(animation_id)
            _validate_animation(animation)
        rig_groups: dict[str, list[dict[str, Any]]] = {}
        for animation in animations.values():
            rig_groups.setdefault(animation["rig_sha256"], []).append(animation)
        for group in rig_groups.values():
            first = group[0]
            first_atlas = first["atlas"]
            common = (
                first["rig_id"],
                first["source_profile"]["relative_path"],
                first["source_profile"]["schema_version"],
                first["source_profile"]["sha256"],
                first_atlas["sha256"],
                first_atlas["frame_size"],
                first_atlas["atlas_size"],
                first_atlas["grid"]["columns"],
                first_atlas["grid"]["rows"],
            )
            rows: set[int] = set()
            for animation in group:
                atlas = animation["atlas"]
                candidate_common = (
                    animation["rig_id"],
                    animation["source_profile"]["relative_path"],
                    animation["source_profile"]["schema_version"],
                    animation["source_profile"]["sha256"],
                    atlas["sha256"],
                    atlas["frame_size"],
                    atlas["atlas_size"],
                    atlas["grid"]["columns"],
                    atlas["grid"]["rows"],
                )
                if candidate_common != common or atlas["grid"]["row"] in rows:
                    raise TrustedBindingsError("trusted_rig_animation_group_inconsistent")
                rows.add(atlas["grid"]["row"])
            if rows != set(range(first_atlas["grid"]["rows"])):
                raise TrustedBindingsError("trusted_rig_animation_group_incomplete")
    return payload


def load_trusted_bindings() -> dict[str, Any]:
    """Load only the catalog shipped beside this checker; callers cannot select a path."""
    try:
        payload = json.loads(BINDINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise TrustedBindingsError("trusted_catalog_unreadable") from error
    return _validate_catalog(payload)


def character_binding(catalog: dict[str, Any], character_id: str) -> dict[str, Any]:
    character = catalog["characters"].get(character_id)
    if type(character) is not dict:
        raise TrustedBindingsError("trusted_character_missing")
    return character


def animation_binding(
    catalog: dict[str, Any], character_id: str, animation_id: str
) -> tuple[dict[str, Any], dict[str, Any]]:
    character = character_binding(catalog, character_id)
    animation = character["animations"].get(animation_id)
    if type(animation) is not dict:
        raise TrustedBindingsError("trusted_animation_missing")
    return character, animation


def profile_topology(character: dict[str, Any]) -> dict[str, dict[str, object]]:
    profile_kind = character.get("profile_kind")
    topology = PROFILE_KINDS.get(profile_kind)
    if topology is None:
        raise TrustedBindingsError("trusted_profile_kind_unknown")
    return topology


def playable_character_ids(catalog: dict[str, Any]) -> tuple[str, ...]:
    """Return the code-reviewed playable-character set in stable order."""
    return tuple(
        sorted(
            character_id
            for character_id, character in catalog["characters"].items()
            if character["playable"] is True
        )
    )


def registry_mapping_sha256(registry: dict[str, Any]) -> tuple[str | None, int]:
    units = registry.get("units")
    if type(units) is not list:
        return None, 0
    rows: list[dict[str, object]] = []
    for unit in units:
        if type(unit) is not dict or unit.get("category") != "item":
            continue
        if "appearance" not in unit:
            continue
        asset_id = unit.get("asset_id")
        appearance = unit.get("appearance")
        if (
            type(asset_id) is not str
            or not asset_id
            or not _exact_keys(appearance, {"slot", "socket", "mode", "depth"})
        ):
            return None, 0
        mapping = {
            name: appearance.get(name) for name in ("slot", "socket", "mode", "depth")
        }
        if (
            type(mapping["slot"]) is not str
            or type(mapping["socket"]) is not str
            or type(mapping["mode"]) is not str
            or mapping["mode"] not in VALID_MODES
            or type(mapping["depth"]) is not int
        ):
            return None, 0
        rows.append({"asset_id": asset_id, "appearance": mapping})
    canonical = json.dumps(
        sorted(rows, key=lambda row: str(row["asset_id"])),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest(), len(rows)


def trusted_catalog_sha256() -> str:
    return hashlib.sha256(BINDINGS_PATH.read_bytes()).hexdigest()
