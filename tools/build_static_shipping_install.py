#!/usr/bin/env python3
"""Deterministically promote the accepted 70-unit static set into shipping."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image


APPROVAL_RECORDED_UTC = "2026-08-27T22:00:00Z"
EVIDENCE_SCHEMA = "gogobro-static-shipping-approval-v1"
MANIFEST_SCHEMA = "gogobro-static-runtime-bindings-v1"
MANIFEST_KIND = "shipping_runtime_bindings"
EXPECTED_NONCHARACTER_UNITS = 70
EXPECTED_CANDIDATE_UNITS = 65
CANDIDATE_MANIFEST_PATH = "game/content/assets/gogobro_static_candidate_preview_v1.json"
APPROVAL_PATH = "game/content/assets/gogobro_static_shipping_approval_2026-08-28.json"
LEGACY_APPROVAL_SHA256 = "D52BDE81CB2C192F53A02CFFBC7D300EBBC0900ED00256F4E4D637824112C27A"
LEGACY_APPROVED_CANDIDATE_MANIFEST_SHA256 = (
    "23CE4206AB7B59A01A3BA8A39ECA6F994E12ADBFF9E3D536740A8B80B7BF4927"
)
ART_V2_APPROVAL_PATH = (
    "game/content/assets/approvals/gogobro_art_v2_shipping_approval_2026-09-02.json"
)
ART_V2_APPROVAL_SHA256 = "4AFA9324F76E86F24B32E2DF96BBB6C93913407F1C23F0339DEDA8B979F283F0"
ART_V2_AUTHORITY = "user_authorized_supervisor_ordinary_visual_judgment"
ART_V2_OVERRIDE_PATHS = {
    "community_server_floor": {
        "shipping": (
            "res://game/assets/gogobro_static/world/"
            "community_server_floor_training_ground_v2_2048x1536_rgba8.png"
        ),
        "raw": (
            "res://game/assets/gogobro_static/world/"
            "community_server_floor_training_ground_v2_1448x1086.png"
        ),
        "source_sha256": "FA7EF4C76185BC321F182D0838701AB4BB171E72CD936A3CC45296A62F3C70AA",
        "source_size": [1448, 1086],
        "source_thread_id": "01a05797-4ca9-7ed2-9a85-134105673148",
        "source_tool_call_ordinal": 21263,
        "source_raw_filename": "exec-392ba628-94e8-4c08-80af-77ae96296fd5.png",
        "output_sha256": "AFD075592C1C7E6EC5423E2C63E09454C7222F4DAD23FFAD841B3F96708A0EEC",
        "output_rgba8_sha256": "C7641010C8FF6CD45C703C605FF734E6AF49F65937B3E6794BB9BF9ABB427917",
        "output_size": [2048, 1536],
        "prompt": "res://game/content/assets/approvals/community_server_floor_training_ground_v2_prompt.md",
        "prompt_sha256": "D128E9F125951CBF738732892AA4A787A4929B524A20AC6F8547FEE0851ED47F",
        "source_contract": "res://game/content/assets/approvals/community_server_floor_training_ground_v2_source_contract.md",
        "source_contract_sha256": "243912DAC8D47EDCFA9800E88CF67552592674F8D0AE5E8A879BF87BE5DC7436",
        "visual_review": "res://game/content/assets/approvals/community_server_floor_training_ground_v2_visual_review.md",
        "visual_review_sha256": "BE3AF83D035DC147F98162CD4DD43A7D8EE16542E3E0839C0873FF9C768F38F9",
    },
    "zone_thumbnail": {
        "shipping": (
            "res://game/assets/gogobro_static/ui/"
            "zone_thumbnail_training_ground_v2_256x144_rgba8.png"
        ),
        "raw": (
            "res://game/assets/gogobro_static/ui/"
            "zone_thumbnail_training_ground_v2_1672x941.png"
        ),
        "source_sha256": "47FA7559B0774D5E514D9149464B1BC76BBE9DC33058FB4B2959A1620CEC00F8",
        "source_size": [1672, 941],
        "source_thread_id": "01a05797-4ca9-7ed2-9a85-134105673148",
        "source_tool_call_ordinal": 21240,
        "source_raw_filename": "exec-ed6f3d07-e44b-4375-aece-7d5bb800156e.png",
        "output_sha256": "FB341F882F46D9EAD7C3D1601814481B9F4A090156B4DEFD5726569A98746584",
        "output_rgba8_sha256": "86A91AAB941868EB6EEF590D819FFD80199EB8174391FA1A7CBC721D198B3A7F",
        "output_size": [256, 144],
        "prompt": "res://game/content/assets/approvals/zone_thumbnail_training_ground_v2_prompt.md",
        "prompt_sha256": "FF383EEEF175E2B58790C428080A7D2A9FCD4859E5628DB0005A0266B22DC7D0",
        "source_contract": "res://game/content/assets/approvals/zone_thumbnail_training_ground_v2_source_contract.md",
        "source_contract_sha256": "B24FE0218E596FF5BF8469778A4819FC7DAABD6BBC3311046DBA9F69B8D5931E",
        "visual_review": "res://game/content/assets/approvals/zone_thumbnail_training_ground_v2_visual_review.md",
        "visual_review_sha256": "39ADF16532A41E71FC1F95BA5835AD54ED4E43FA6B7D23FE673116F7914EA3B1",
    },
}
ART_V2_OVERRIDE_IDS = frozenset(ART_V2_OVERRIDE_PATHS)
SUPERSEDED_LEGACY_MEDIA = {
    "community_server_floor": {
        "resource_path": "res://game/assets/gogobro_static/world/community_server_floor.png",
        "sha256": "21E66402E309A8212AB59263E36FB32E842EEFADC18BE675860DF359F7AF58CC",
    },
    "zone_thumbnail": {
        "resource_path": "res://game/assets/gogobro_static/ui/zone_thumbnail.png",
        "sha256": "6856B72C4594AFB44E2F82CA050F879E5C45FDFEDC02FFC2D1B13D4CB0D32531",
    },
}
SOURCE_SPEC_PATH = "docs/superpowers/specs/2026-08-28-runtime-clarity-combat-completion-design.md"
REVIEW_REPORT_PATHS = [
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-1-report.md",
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-2-report.md",
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-3-report.md",
]
SHIPPING_ONLY_IDS = {
    "control_icon_kit",
    "difficulty_badge_kit",
    "hud_icon_kit",
    "one_more_round",
    "projectile_hit_kit",
}
CORE_ITEM_CONTENT_IDS = {
    "ballistic_liner": "gogobro.core:item/training_1",
    "silent_step_insoles": "gogobro.core:item/training_2",
    "crosshair_shim": "gogobro.core:item/training_3",
    "supply_radar": "gogobro.core:item/training_4",
    "trade_guard": "gogobro.core:item/training_5",
    "tactical_med_patch": "gogobro.core:item/training_6",
}
CORE_UPGRADE_CONTENT_IDS = {
    "one_more_round": "gogobro.core:upgrade/training_1",
    "trade_step_drills": "gogobro.core:upgrade/training_2",
    "pre_aim_drills": "gogobro.core:upgrade/training_3",
    "economy_sense": "gogobro.core:upgrade/training_4",
    "kevlar_reinforcement": "gogobro.core:upgrade/training_5",
    "medical_timeout": "gogobro.core:upgrade/training_6",
}
REQUIRED_VARIANT_SELECTORS = {
    "community_server_decor_pack": [f"decor_variant_{index:02d}" for index in range(1, 7)],
    "card_and_rarity_frame_kit": ["common", "uncommon", "rare", "legendary"],
    "four_state_button": ["normal", "hover", "pressed", "disabled"],
}
EXCLUDED_STATIC_SCOPE_IDS = {
    "service_carbine",
    "master_ni",
    "lost_rotator",
    "long_angle_sentry",
    "force_buy_rusher",
    "site_scout_chicken",
}


def _godot_json_number_shape(value: Any) -> Any:
    """Mirror Godot JSON.parse_string: JSON numbers become Variant floats."""
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, int):
        return float(value)
    if isinstance(value, float):
        return value
    if isinstance(value, list):
        return [_godot_json_number_shape(item) for item in value]
    if isinstance(value, dict):
        return {key: _godot_json_number_shape(item) for key, item in value.items()}
    raise TypeError(f"unsupported canonical JSON value: {type(value).__name__}")


def _canonical_sha256(value: Any) -> str:
    encoded = json.dumps(
        _godot_json_number_shape(value),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest().upper()


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def _content_consumer(category: str, asset_id: str) -> dict[str, Any]:
    if category == "weapon":
        if asset_id == "warmup_shiv":
            content_id = "weapon.training_blade:weapon/training_blade"
        elif asset_id == "service_pistol":
            content_id = "weapon.training_blaster:weapon/training_blaster"
        else:
            content_id = f"gogobro.preview:weapon/{asset_id}"
    elif category == "item":
        content_id = CORE_ITEM_CONTENT_IDS.get(asset_id, f"gogobro.preview:item/{asset_id}")
    elif category == "upgrade":
        content_id = CORE_UPGRADE_CONTENT_IDS[asset_id]
    else:
        raise RuntimeError(f"{asset_id}: no content consumer for category {category}")
    return {
        "kind": "content",
        "content_kind": category,
        "content_id": content_id,
        "role": "icon",
        "selector": "",
    }


def _runtime_binding(
    asset_id: str,
    role: str,
    selector: str,
    display_size: list[int],
    pivot: list[int],
    anchors: dict[str, Any],
    atlas_rect: list[int],
    consumers: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "binding_key": f"{asset_id}|{role}|{selector}",
        "role": role,
        "selector": selector,
        "display_size_px": display_size,
        "display_scale": [
            display_size[0] / atlas_rect[2],
            display_size[1] / atlas_rect[3],
        ],
        "pivot_px": pivot,
        "atlas_rect_px": atlas_rect,
        "anchors_px": anchors,
        "consumers": consumers,
    }


def _image_metadata(
    data: bytes,
    label: str,
    *,
    require_clean_alpha: bool = False,
) -> tuple[Image.Image, list[int], str]:
    try:
        with Image.open(BytesIO(data)) as opened:
            rgba = opened.convert("RGBA")
    except Exception as error:
        raise RuntimeError(f"{label}: unreadable PNG") from error
    if require_clean_alpha:
        alpha = set(rgba.getchannel("A").get_flattened_data())
        if not alpha.issubset({0, 255}):
            raise RuntimeError(f"{label}: alpha is not binary")
        if any(
            pixel[3] == 0 and pixel[:3] != (0, 0, 0)
            for pixel in rgba.get_flattened_data()
        ):
            raise RuntimeError(f"{label}: transparent RGB is not zero")
    return rgba, list(rgba.size), _sha256_bytes(rgba.tobytes())


def _shipping_ready_image(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    normalized = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    normalized.putdata([
        (red, green, blue, 255) if alpha >= 128 else (0, 0, 0, 0)
        for red, green, blue, alpha in rgba.get_flattened_data()
    ])
    return normalized


def _validate_pair(value: Any, label: str, *, positive: bool = False) -> list[int]:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or any(isinstance(component, bool) or not isinstance(component, int) for component in value)
        or (positive and any(component <= 0 for component in value))
    ):
        raise RuntimeError(f"{label}: expected an exact integer pair")
    return value


def _validate_candidate_artifact(
    workspace: Path,
    project_root: Path,
    artifact: dict[str, Any],
    label: str,
    selector: str,
) -> tuple[Image.Image, bytes, dict[str, Any]]:
    preview_path = project_root / str(artifact["resource_path"]).removeprefix("res://")
    source_path = workspace / str(artifact["source_candidate_path"])
    if not preview_path.is_file() or not source_path.is_file():
        raise RuntimeError(f"{label}: accepted source or preview copy is missing")
    preview_bytes = preview_path.read_bytes()
    source_bytes = source_path.read_bytes()
    declared_hash = str(artifact.get("sha256", "")).upper()
    if preview_bytes != source_bytes or _sha256_bytes(preview_bytes) != declared_hash:
        raise RuntimeError(f"{label}: source/preview bytes do not match the accepted hash")
    image, pixel_size, rgba8_sha256 = _image_metadata(preview_bytes, label)
    if pixel_size != _validate_pair(artifact.get("pixel_size"), f"{label} pixel_size", positive=True):
        raise RuntimeError(f"{label}: decoded pixel size mismatch")
    display_size = _validate_pair(
        artifact.get("display_size_px"), f"{label} display_size_px", positive=True
    )
    if display_size != pixel_size:
        raise RuntimeError(f"{label}: accepted display size must equal current real dimensions")
    pivot = _validate_pair(artifact.get("pivot_px"), f"{label} pivot_px")
    if not (0 <= pivot[0] < display_size[0] and 0 <= pivot[1] < display_size[1]):
        raise RuntimeError(f"{label}: pivot is outside the accepted image")
    anchors = artifact.get("anchors_px", {})
    if not isinstance(anchors, dict):
        raise RuntimeError(f"{label}: anchors must be an object")
    for anchor_name, value in anchors.items():
        anchor = _validate_pair(value, f"{label} anchor {anchor_name}")
        if not (0 <= anchor[0] < display_size[0] and 0 <= anchor[1] < display_size[1]):
            raise RuntimeError(f"{label}: anchor {anchor_name} is outside the accepted image")
    return image, preview_bytes, {
        "selector": selector,
        "preview_resource_path": artifact["resource_path"],
        "source_candidate_path": artifact["source_candidate_path"],
        "sha256": declared_hash,
        "rgba8_sha256": rgba8_sha256,
        "pixel_size": pixel_size,
        "display_size_px": display_size,
        "pivot_px": pivot,
        "anchors_px": anchors,
    }


def _encode_png(image: Image.Image) -> bytes:
    output = BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()


def _accepted_copy_path(resource_path: str, selector: str) -> str:
    path = Path(resource_path.removeprefix("res://"))
    suffix = f"__{selector}" if selector else "__accepted_source"
    return "res://" + (path.parent / f"{path.stem}{suffix}{path.suffix}").as_posix()


def _project_resource_target(
    project_root: Path,
    resource_path: str,
    allowed_prefix: str | None = None,
) -> Path:
    if not isinstance(resource_path, str) or not resource_path.startswith("res://"):
        raise RuntimeError(f"resource path is not project-relative: {resource_path}")
    relative_text = resource_path.removeprefix("res://")
    raw_parts = relative_text.split("/")
    reserved_names = {
        "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$",
        *(f"COM{index}" for index in range(1, 10)),
        *(f"LPT{index}" for index in range(1, 10)),
    }
    if (
        "\\" in relative_text
        or not relative_text
        or any(
            not part
            or part in {".", ".."}
            or part.endswith((" ", "."))
            or any(character in '<>:"|?*' or ord(character) < 32 for character in part)
            or part.split(".", 1)[0].upper() in reserved_names
            for part in raw_parts
        )
    ):
        raise RuntimeError(f"resource path must use canonical separators: {resource_path}")
    relative = Path(relative_text)
    if relative.is_absolute() or not relative.parts:
        raise RuntimeError(f"resource path is not canonical: {resource_path}")
    root = project_root.resolve()
    target = (root / relative).resolve(strict=False)
    if target != root and root not in target.parents:
        raise RuntimeError(f"resource path escapes the project: {resource_path}")
    if target.exists() and target.is_dir():
        raise RuntimeError(f"resource path resolves to a directory: {resource_path}")
    if allowed_prefix is not None:
        if not allowed_prefix.startswith("res://"):
            raise RuntimeError(f"allowed resource root is invalid: {allowed_prefix}")
        allowed_relative_text = allowed_prefix.removeprefix("res://").rstrip("/")
        allowed_parts = allowed_relative_text.split("/")
        if (
            not allowed_relative_text
            or any(not part or part in {".", ".."} for part in allowed_parts)
        ):
            raise RuntimeError(f"allowed resource root is invalid: {allowed_prefix}")
        allowed_root = (root / Path(allowed_relative_text)).resolve(strict=False)
        if target != allowed_root and allowed_root not in target.parents:
            raise RuntimeError(f"resource path is outside the allowed root: {resource_path}")
    return target


def _record_desired_media(
    desired_media: dict[Path, bytes],
    target: Path,
    content: bytes,
    label: str,
) -> None:
    resolved = target.resolve(strict=False)
    for existing in desired_media:
        if existing.resolve(strict=False) == resolved:
            raise RuntimeError(f"{label}: duplicate resolved shipping destination")
    desired_media[target] = content


def _validated_superseded_legacy_media(project_root: Path) -> dict[Path, bytes]:
    if set(SUPERSEDED_LEGACY_MEDIA) != ART_V2_OVERRIDE_IDS:
        raise RuntimeError("superseded legacy media scope must equal the exact art-v2 asset IDs")
    media: dict[Path, bytes] = {}
    for asset_id, contract in SUPERSEDED_LEGACY_MEDIA.items():
        target = _project_resource_target(
            project_root,
            contract["resource_path"],
            "res://game/assets/gogobro_static/",
        )
        if not target.is_file():
            raise RuntimeError(f"{asset_id}: superseded legacy media is missing")
        data = target.read_bytes()
        if _sha256_bytes(data) != contract["sha256"]:
            raise RuntimeError(f"{asset_id}: superseded legacy media changed")
        _record_desired_media(media, target, data, f"{asset_id}:superseded-legacy")
    return media


def _assert_immutable_media(expected_media: dict[Path, bytes], label: str) -> None:
    if not expected_media:
        raise RuntimeError(f"{label}: immutable media set is empty")
    for target, expected in expected_media.items():
        if not target.is_file():
            raise RuntimeError(f"{label}: approved media is missing: {target}")
        if target.read_bytes() != expected:
            raise RuntimeError(f"{label}: approved media drifted: {target}")


def _protected_media_paths(
    project_root: Path,
    immutable_legacy_paths: set[Path] | frozenset[Path] = frozenset(),
) -> set[Path]:
    return {
        (project_root / APPROVAL_PATH).resolve(strict=False),
        (project_root / ART_V2_APPROVAL_PATH).resolve(strict=False),
        *(
            _project_resource_target(project_root, path)
            for contract in ART_V2_OVERRIDE_PATHS.values()
            for path in (contract["shipping"], contract["raw"])
        ),
        *(
            _project_resource_target(project_root, contract["resource_path"])
            for contract in SUPERSEDED_LEGACY_MEDIA.values()
        ),
        *(path.resolve(strict=False) for path in immutable_legacy_paths),
    }


def _assert_no_protected_art_v2_overwrites(
    project_root: Path,
    desired_media: dict[Path, bytes],
    immutable_legacy_paths: set[Path] | frozenset[Path] = frozenset(),
) -> None:
    protected_paths = _protected_media_paths(project_root, immutable_legacy_paths)
    desired_paths = {
        path.resolve(strict=False)
        for path in desired_media
    }
    collisions = desired_paths.intersection(protected_paths)
    if collisions:
        raise RuntimeError(
            "legacy promotion attempted to overwrite protected art-v2 evidence: "
            + ", ".join(sorted(str(path) for path in collisions))
        )


def _metadata_write_plan(
    project_root: Path,
    registry_text: str,
    manifest_text: str,
    immutable_legacy_paths: set[Path],
) -> dict[Path, bytes]:
    desired_files = {
        project_root / "game/content/assets/gogobro_static_assets_v1.json": registry_text.encode("utf-8"),
        project_root / "game/content/assets/gogobro_static_runtime_bindings_v1.json": manifest_text.encode("utf-8"),
    }
    _assert_no_protected_art_v2_overwrites(
        project_root,
        desired_files,
        immutable_legacy_paths,
    )
    return desired_files


def _candidate_specs(
    workspace: Path,
    project_root: Path,
    registry_units: dict[str, dict[str, Any]],
    excluded_asset_ids: frozenset[str] = frozenset(),
) -> tuple[dict[str, dict[str, Any]], dict[Path, bytes]]:
    manifest_path = project_root / CANDIDATE_MANIFEST_PATH
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        manifest.get("schema_version") != "gogobro-static-candidate-preview-v1"
        or manifest.get("kind") != "development_candidate_preview_only"
        or manifest.get("enabled_in_shipping") is not False
        or manifest.get("human_approval_implied") is not False
        or manifest.get("character_assets_included") is not False
        or manifest.get("expected_unit_count") != EXPECTED_CANDIDATE_UNITS
    ):
        raise RuntimeError("accepted candidate manifest header is invalid")
    units = manifest.get("units")
    if not isinstance(units, list) or len(units) != EXPECTED_CANDIDATE_UNITS:
        raise RuntimeError("accepted candidate manifest must contain exactly 65 units")
    candidate_ids = {str(unit.get("asset_id", "")) for unit in units if isinstance(unit, dict)}
    if len(candidate_ids) != EXPECTED_CANDIDATE_UNITS or not candidate_ids.issubset(registry_units):
        raise RuntimeError("accepted candidate IDs must be unique canonical registry IDs")

    specs: dict[str, dict[str, Any]] = {}
    desired_media: dict[Path, bytes] = {}
    expected_roles = {
        "weapon": "world_sprite",
        "item": "icon",
        "upgrade": "icon",
        "world": "world_sprite",
        "ui_brand": "ui_texture",
    }
    for unit in units:
        asset_id = str(unit["asset_id"])
        if asset_id in excluded_asset_ids:
            continue
        category = str(unit.get("category", ""))
        role = str(unit.get("role", ""))
        if role != expected_roles.get(category):
            raise RuntimeError(f"{asset_id}: candidate role/category mismatch")
        if (
            unit.get("texture_filter") != "nearest"
            or unit.get("mipmaps") is not False
            or unit.get("approval_status") != "candidate_preview_only"
            or unit.get("preview_alias_asset_ids") != []
        ):
            raise RuntimeError(f"{asset_id}: candidate runtime contract mismatch")
        registry_unit = registry_units[asset_id]
        shipping_path = str((registry_unit.get("intended_file_paths") or [""])[0])
        shipping_target = _project_resource_target(
            project_root,
            shipping_path,
            "res://game/assets/gogobro_static/",
        )

        variants = unit.get("variants", [])
        if not isinstance(variants, list):
            raise RuntimeError(f"{asset_id}: variants must be an array")
        variant_selectors = [str(variant.get("selector", "")) for variant in variants]
        if variant_selectors != REQUIRED_VARIANT_SELECTORS.get(asset_id, []):
            raise RuntimeError(f"{asset_id}: selector order does not match the accepted selector contract")

        artifact_values = [("", unit), *[(selector, value) for selector, value in zip(variant_selectors, variants)]]
        images: list[Image.Image] = []
        media_bytes: list[bytes] = []
        source_records: list[dict[str, Any]] = []
        for selector, artifact in artifact_values:
            image, data, source_record = _validate_candidate_artifact(
                workspace, project_root, artifact, f"{asset_id}:{selector or 'primary'}", selector
            )
            images.append(image)
            media_bytes.append(data)
            source_records.append(source_record)

        main_size = source_records[0]["pixel_size"]
        if any(record["pixel_size"] != main_size for record in source_records):
            raise RuntimeError(f"{asset_id}: all selector sources must share current real dimensions")
        if variants:
            atlas = Image.new("RGBA", (main_size[0] * len(images), main_size[1]), (0, 0, 0, 0))
            for index, image in enumerate(images):
                atlas.paste(_shipping_ready_image(image), (index * main_size[0], 0))
            shipping_bytes = _encode_png(atlas)
            for index, (selector, _) in enumerate(artifact_values):
                copy_path = _accepted_copy_path(shipping_path, selector)
                _record_desired_media(
                    desired_media,
                    _project_resource_target(
                        project_root,
                        copy_path,
                        "res://game/assets/gogobro_static/",
                    ),
                    media_bytes[index],
                    f"{asset_id}:{selector or 'primary'}",
                )
                source_records[index]["shipping_source_copy_path"] = copy_path
        else:
            shipping_bytes = media_bytes[0]
        _record_desired_media(
            desired_media,
            shipping_target,
            shipping_bytes,
            f"{asset_id}:shipping",
        )
        shipping_image, shipping_size, shipping_rgba8 = _image_metadata(
            shipping_bytes, f"{asset_id}:shipping", require_clean_alpha=True
        )

        bindings: list[dict[str, Any]] = []
        for index, source_record in enumerate(source_records):
            selector = str(source_record["selector"])
            atlas_rect = [index * main_size[0], 0, main_size[0], main_size[1]]
            consumers: list[dict[str, Any]] = []
            if category in {"world", "ui_brand"}:
                consumers.append({"kind": "global", "role": asset_id, "selector": selector})
            elif category in {"item", "upgrade"} and not selector:
                consumers.append(_content_consumer(category, asset_id))
            bindings.append(_runtime_binding(
                asset_id,
                role,
                selector,
                source_record["display_size_px"],
                source_record["pivot_px"],
                source_record["anchors_px"],
                atlas_rect,
                consumers,
            ))
        if category == "weapon":
            bindings.append(_runtime_binding(
                asset_id,
                "icon",
                "",
                source_records[0]["display_size_px"],
                [source_records[0]["display_size_px"][0] // 2, source_records[0]["display_size_px"][1] // 2],
                {},
                [0, 0, main_size[0], main_size[1]],
                [_content_consumer(category, asset_id)],
            ))

        selector_pixels = []
        for index, source_record in enumerate(source_records):
            rect = [index * main_size[0], 0, main_size[0], main_size[1]]
            crop = shipping_image.crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
            selector_pixels.append({
                "selector": source_record["selector"],
                "atlas_rect_px": rect,
                "rgba8_sha256": _sha256_bytes(crop.tobytes()),
            })
        specs[asset_id] = {
            "resource_path": shipping_path,
            "sha256": _sha256_bytes(shipping_bytes),
            "rgba8_sha256": shipping_rgba8,
            "pixel_size": shipping_size,
            "alpha": bool(registry_unit.get("output_spec", {}).get("alpha", True)),
            "scope": "selector_set" if variants else ("inventory_icon_only" if category == "item" else "whole_texture"),
            "bindings": bindings,
            "source_kind": "accepted_candidate_preview",
            "accepted_sources": source_records,
            "selector_pixels": selector_pixels,
            "packed_selector_count": len(variants),
        }
    return specs, desired_media


def _shipping_only_specs(
    workspace: Path,
    project_root: Path,
) -> dict[str, dict[str, Any]]:
    approval_bytes = (project_root / APPROVAL_PATH).read_bytes()
    if _sha256_bytes(approval_bytes) != LEGACY_APPROVAL_SHA256:
        raise RuntimeError("legacy approval record changed")
    approval = json.loads(approval_bytes.decode("utf-8"))
    approved_units = {
        str(unit.get("asset_id", "")): unit
        for unit in approval.get("units", [])
        if isinstance(unit, dict)
    }
    if set(approved_units).intersection(SHIPPING_ONLY_IDS) != SHIPPING_ONLY_IDS:
        raise RuntimeError("legacy shipping-only approval is incomplete")
    specs: dict[str, dict[str, Any]] = {}
    for asset_id in sorted(SHIPPING_ONLY_IDS):
        approved = approved_units[asset_id]
        shipping = approved.get("shipping_texture")
        bindings = approved.get("runtime_bindings")
        if not isinstance(shipping, dict) or not isinstance(bindings, list):
            raise RuntimeError(f"{asset_id}: legacy shipping-only record is invalid")
        accepted_sources = approved.get("accepted_sources")
        if not isinstance(accepted_sources, list):
            raise RuntimeError(f"{asset_id}: legacy accepted sources are invalid")
        for source in accepted_sources:
            if not isinstance(source, dict):
                raise RuntimeError(f"{asset_id}: legacy accepted source is invalid")
            source_path = Path(str(source.get("source_candidate_path", "")))
            if (
                source_path.is_absolute()
                or not source_path.parts
                or any(part in {"", ".", ".."} for part in source_path.parts)
            ):
                raise RuntimeError(f"{asset_id}: legacy accepted source path is invalid")
            source_target = (workspace.resolve() / source_path).resolve(strict=False)
            if workspace.resolve() not in source_target.parents or not source_target.is_file():
                raise RuntimeError(f"{asset_id}: legacy accepted source is missing")
            if _sha256_bytes(source_target.read_bytes()) != source.get("sha256"):
                raise RuntimeError(f"{asset_id}: legacy accepted source changed")
        spec = {
            "resource_path": shipping.get("resource_path"),
            "sha256": shipping.get("sha256"),
            "rgba8_sha256": shipping.get("rgba8_sha256"),
            "pixel_size": shipping.get("pixel_size"),
            "bindings": bindings,
        }
        target = project_root / spec["resource_path"].removeprefix("res://")
        if not target.is_file():
            raise RuntimeError(f"{asset_id}: shipping-only texture is missing")
        data = target.read_bytes()
        image, pixel_size, rgba8 = _image_metadata(data, asset_id, require_clean_alpha=True)
        if (
            _sha256_bytes(data) != spec["sha256"]
            or rgba8 != spec["rgba8_sha256"]
            or pixel_size != spec["pixel_size"]
        ):
            raise RuntimeError(f"{asset_id}: shipping-only approved texture changed")
        selector_pixels: list[dict[str, Any]] = []
        seen: set[tuple[str, tuple[int, ...]]] = set()
        for binding in spec["bindings"]:
            selector = str(binding["selector"])
            rect = tuple(binding["atlas_rect_px"])
            key = (selector, rect)
            if key in seen:
                continue
            seen.add(key)
            crop = image.crop((rect[0], rect[1], rect[0] + rect[2], rect[1] + rect[3]))
            selector_pixels.append({
                "selector": selector,
                "atlas_rect_px": list(rect),
                "rgba8_sha256": _sha256_bytes(crop.tobytes()),
            })
        nonempty_selectors = {
            str(binding.get("selector", ""))
            for binding in spec["bindings"]
            if str(binding.get("selector", ""))
        }
        spec.update({
            "alpha": True,
            "scope": "selector_set" if nonempty_selectors else "whole_texture",
            "source_kind": approved.get("source_kind", "retained_shipping_only"),
            "accepted_sources": accepted_sources,
            "selector_pixels": selector_pixels,
            "packed_selector_count": len([row for row in selector_pixels if row["selector"]]),
        })
        specs[asset_id] = spec
    return specs


def _project_resource_file(project_root: Path, resource_path: str) -> Path:
    target = _project_resource_target(project_root, resource_path)
    if not target.is_file():
        raise RuntimeError(f"resource file is missing: {resource_path}")
    return target


def _validate_art_v2_approval_scope(
    approval: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    if (
        approval.get("schema_version") != "gogobro-supervised-art-shipping-approval-v1"
        or approval.get("decision") != "approved"
        or approval.get("authority") != ART_V2_AUTHORITY
        or approval.get("per_image_explicit_user_approval") is not False
    ):
        raise RuntimeError("art-v2 approval header is invalid")
    delegation = approval.get("delegation_basis")
    expected_shipping_paths = {
        value["shipping"] for value in ART_V2_OVERRIDE_PATHS.values()
    }
    expected_raw_paths = {value["raw"] for value in ART_V2_OVERRIDE_PATHS.values()}
    logical_ids = delegation.get("logical_asset_ids") if isinstance(delegation, dict) else None
    shipping_paths = (
        delegation.get("versioned_shipping_paths") if isinstance(delegation, dict) else None
    )
    raw_paths = (
        delegation.get("raw_provenance_paths") if isinstance(delegation, dict) else None
    )
    if (
        not isinstance(delegation, dict)
        or delegation.get("goal") != "gobro-art-v2-20260902"
        or delegation.get("statement")
        != (
            "The user authorized the supervisor to make ordinary visual choices for this goal; "
            "this is not per-image explicit approval."
        )
        or not isinstance(logical_ids, list)
        or set(logical_ids) != ART_V2_OVERRIDE_IDS
        or len(logical_ids) != len(ART_V2_OVERRIDE_IDS)
        or not isinstance(shipping_paths, list)
        or set(shipping_paths) != expected_shipping_paths
        or len(shipping_paths) != len(expected_shipping_paths)
        or not isinstance(raw_paths, list)
        or set(raw_paths) != expected_raw_paths
        or len(raw_paths) != len(expected_raw_paths)
    ):
        raise RuntimeError("art-v2 delegation scope is invalid")

    units = approval.get("units")
    if not isinstance(units, list) or len(units) != len(ART_V2_OVERRIDE_IDS):
        raise RuntimeError("art-v2 approval must contain exactly two units")
    units_by_id = {
        str(unit.get("asset_id", "")): unit
        for unit in units
        if isinstance(unit, dict)
    }
    if set(units_by_id) != ART_V2_OVERRIDE_IDS:
        raise RuntimeError("art-v2 approval asset IDs are invalid")
    for asset_id in ART_V2_OVERRIDE_IDS:
        unit = units_by_id[asset_id]
        expected = ART_V2_OVERRIDE_PATHS[asset_id]
        expected_role = "world_sprite" if asset_id == "community_server_floor" else "ui_texture"
        expected_scope = (
            {
                "kind": "whole_texture",
                "runtime_role": "ordinary_combat_arena_background",
                "ordinary_run_props": 0,
            }
            if asset_id == "community_server_floor"
            else {
                "kind": "whole_texture",
                "runtime_role": "training_ground_task_art",
            }
        )
        source = unit.get("source")
        shipping = unit.get("shipping_texture")
        if (
            unit.get("binding_key") != f"{asset_id}|{expected_role}|"
            or unit.get("authority") != ART_V2_AUTHORITY
            or unit.get("per_image_explicit_user_approval") is not False
            or unit.get("delegation_basis")
            != "gobro-art-v2-20260902 ordinary visual choice authorization"
            or unit.get("scope") != expected_scope
            or not isinstance(source, dict)
            or source.get("raw_resource_path") != expected["raw"]
            or not isinstance(shipping, dict)
            or shipping.get("resource_path") != expected["shipping"]
        ):
            raise RuntimeError(f"{asset_id}: art-v2 approval scope is invalid")
    return units_by_id


def _art_v2_override_specs(
    project_root: Path,
    registry_units: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    approval_path = project_root / ART_V2_APPROVAL_PATH
    approval_bytes = approval_path.read_bytes()
    approval_sha256 = _sha256_bytes(approval_bytes)
    if approval_sha256 != ART_V2_APPROVAL_SHA256:
        raise RuntimeError("art-v2 approval record hash changed")
    approval = json.loads(approval_bytes.decode("utf-8"))
    units_by_id = _validate_art_v2_approval_scope(approval)

    specs: dict[str, dict[str, Any]] = {}
    for asset_id in sorted(ART_V2_OVERRIDE_IDS):
        expected = ART_V2_OVERRIDE_PATHS[asset_id]
        unit = units_by_id[asset_id]
        if (
            unit.get("authority") != ART_V2_AUTHORITY
            or unit.get("per_image_explicit_user_approval") is not False
            or unit.get("delegation_basis")
            != "gobro-art-v2-20260902 ordinary visual choice authorization"
        ):
            raise RuntimeError(f"{asset_id}: art-v2 unit authority is invalid")

        source = unit.get("source")
        if (
            not isinstance(source, dict)
            or source.get("thread_id") != expected["source_thread_id"]
            or source.get("tool_call_ordinal") != expected["source_tool_call_ordinal"]
            or source.get("raw_filename") != expected["source_raw_filename"]
            or source.get("raw_resource_path") != expected["raw"]
            or source.get("sha256") != expected["source_sha256"]
            or source.get("pixel_size") != expected["source_size"]
        ):
            raise RuntimeError(f"{asset_id}: art-v2 raw provenance is invalid")
        raw_bytes = _project_resource_file(project_root, expected["raw"]).read_bytes()
        raw_image, raw_size, _ = _image_metadata(raw_bytes, f"{asset_id}:raw")
        if (
            _sha256_bytes(raw_bytes) != expected["source_sha256"]
            or raw_size != expected["source_size"]
        ):
            raise RuntimeError(f"{asset_id}: art-v2 raw source changed")

        for field, path_key, sha_key in [
            ("prompt", "prompt", "prompt_sha256"),
            ("source_contract", "source_contract", "source_contract_sha256"),
            ("visual_review", "visual_review", "visual_review_sha256"),
        ]:
            record = unit.get(field)
            if record != {"path": expected[path_key], "sha256": expected[sha_key]}:
                raise RuntimeError(f"{asset_id}: art-v2 {field} record is invalid")
            document = _project_resource_file(project_root, expected[path_key])
            if _sha256_bytes(document.read_bytes()) != expected[sha_key]:
                raise RuntimeError(f"{asset_id}: art-v2 {field} changed")

        if unit.get("processing") != {
            "tool": "Pillow",
            "version": "12.2.0",
            "algorithm": "Image.Resampling.LANCZOS",
            "color_mode": "RGBA8",
            "crop": "none",
            "png_optimize": False,
            "png_compress_level": 9,
            "double_encode_identical": True,
        }:
            raise RuntimeError(f"{asset_id}: art-v2 processing contract is invalid")

        shipping = unit.get("shipping_texture")
        if not isinstance(shipping, dict):
            raise RuntimeError(f"{asset_id}: art-v2 shipping texture record is missing")
        if (
            shipping.get("resource_path") != expected["shipping"]
            or shipping.get("source_sha256") != expected["source_sha256"]
            or shipping.get("output_sha256") != expected["output_sha256"]
            or shipping.get("rgba8_sha256") != expected["output_rgba8_sha256"]
            or shipping.get("pixel_size") != expected["output_size"]
            or shipping.get("display_size_px") != expected["output_size"]
            or shipping.get("display_scale") != [1.0, 1.0]
            or not all(isinstance(value, float) for value in shipping.get("display_scale", []))
            or shipping.get("texture_filter") != "nearest"
            or shipping.get("mipmaps") is not False
        ):
            raise RuntimeError(f"{asset_id}: art-v2 shipping contract is invalid")
        if asset_id == "community_server_floor" and (
            shipping.get("mount_count") != 1
            or shipping.get("tiled") is not False
            or unit.get("scope", {}).get("ordinary_run_props") != 0
        ):
            raise RuntimeError("community_server_floor: single-sprite arena contract is invalid")

        shipping_bytes = _project_resource_file(project_root, expected["shipping"]).read_bytes()
        derived_image = raw_image.resize(
            tuple(expected["output_size"]),
            resample=Image.Resampling.LANCZOS,
        )
        first_encoding = _encode_png(derived_image)
        second_encoding = _encode_png(derived_image)
        raw_image.close()
        derived_image.close()
        if first_encoding != second_encoding or first_encoding != shipping_bytes:
            raise RuntimeError(
                f"{asset_id}: derived runtime image is not the declared deterministic no-crop resize"
            )
        try:
            with Image.open(BytesIO(shipping_bytes)) as opened:
                if opened.format != "PNG" or opened.mode != "RGBA":
                    raise RuntimeError(f"{asset_id}: derived runtime image must be RGBA8 PNG")
        except RuntimeError:
            raise
        except Exception as error:
            raise RuntimeError(f"{asset_id}: derived runtime image is unreadable") from error
        shipping_image, shipping_size, shipping_rgba8 = _image_metadata(
            shipping_bytes,
            f"{asset_id}:shipping",
        )
        if (
            _sha256_bytes(shipping_bytes) != expected["output_sha256"]
            or shipping_rgba8 != expected["output_rgba8_sha256"]
            or shipping_size != expected["output_size"]
        ):
            raise RuntimeError(f"{asset_id}: derived runtime image changed")

        registry_unit = registry_units[asset_id]
        bindings = registry_unit.get("runtime_bindings")
        expected_role = "world_sprite" if asset_id == "community_server_floor" else "ui_texture"
        expected_consumer = {"kind": "global", "role": asset_id, "selector": ""}
        expected_size = expected["output_size"]
        expected_binding = {
            "binding_key": f"{asset_id}|{expected_role}|",
            "role": expected_role,
            "selector": "",
            "display_size_px": expected_size,
            "display_scale": [1.0, 1.0],
            "pivot_px": [expected_size[0] // 2, expected_size[1] // 2],
            "atlas_rect_px": [0, 0, *expected_size],
            "anchors_px": {},
            "consumers": [expected_consumer],
        }
        expected_evidence_texture = {
            "sha256": expected["output_sha256"],
            "rgba8_sha256": expected["output_rgba8_sha256"],
            "pixel_size": expected_size,
            "output_spec": {
                "format": "PNG",
                "width": expected_size[0],
                "height": expected_size[1],
                "alpha": True,
            },
        }
        evidence = registry_unit.get("shipping_approval_evidence")
        if (
            registry_unit.get("approval_status") != "approved"
            or registry_unit.get("intended_file_paths") != [expected["shipping"]]
            or registry_unit.get("hashes")
            != {
                "sha256": expected["output_sha256"],
                "rgba8_sha256": expected["output_rgba8_sha256"],
            }
            or registry_unit.get("output_spec")
            != {
                "type": "png",
                "width": expected_size[0],
                "height": expected_size[1],
                "alpha": True,
            }
            or bindings != [expected_binding]
            or not isinstance(evidence, dict)
            or evidence.get("schema_version") != EVIDENCE_SCHEMA
            or evidence.get("decision") != "approved"
            or evidence.get("authority") != ART_V2_AUTHORITY
            or evidence.get("approved_at_utc") != "2026-09-01T23:04:01Z"
            or evidence.get("approval_record_sha256") != approval_sha256
            or evidence.get("source_contract_sha256") != expected["source_contract_sha256"]
            or evidence.get("review_board_sha256") != expected["visual_review_sha256"]
            or evidence.get("scope") != {"kind": "whole_texture", "selectors": []}
            or evidence.get("shipping_texture") != expected_evidence_texture
            or evidence.get("runtime_bindings_sha256") != _canonical_sha256(bindings)
        ):
            raise RuntimeError(f"{asset_id}: canonical registry does not preserve art-v2")

        specs[asset_id] = {
            "resource_path": expected["shipping"],
            "sha256": expected["output_sha256"],
            "rgba8_sha256": expected["output_rgba8_sha256"],
            "pixel_size": expected_size,
            "alpha": True,
            "scope": "whole_texture",
            "bindings": bindings,
            "source_kind": ART_V2_AUTHORITY,
            "accepted_sources": [source],
            "selector_pixels": [{
                "selector": "",
                "atlas_rect_px": [0, 0, *expected_size],
                "rgba8_sha256": expected["output_rgba8_sha256"],
            }],
            "packed_selector_count": 0,
        }
        shipping_image.close()
    return specs


def _legacy_approval_evidence(
    project_root: Path,
    legacy_specs: dict[str, dict[str, Any]],
) -> tuple[str, str, str]:
    approval_path = project_root / APPROVAL_PATH
    approval_bytes = approval_path.read_bytes()
    approval_sha256 = _sha256_bytes(approval_bytes)
    if approval_sha256 != LEGACY_APPROVAL_SHA256:
        raise RuntimeError("legacy approval record changed")
    approval = json.loads(approval_bytes.decode("utf-8"))
    units = approval.get("units")
    if (
        approval.get("schema_version") != "gogobro-static-shipping-approval-2026-08-28-v1"
        or approval.get("decision") != "approved"
        or approval.get("authority") != "explicit_user_approval_in_current_task"
        or not isinstance(units, list)
        or len(units) != EXPECTED_NONCHARACTER_UNITS
    ):
        raise RuntimeError("legacy approval record is invalid")
    if approval.get("accepted_candidate_manifest") != {
        "path": CANDIDATE_MANIFEST_PATH,
        "sha256": LEGACY_APPROVED_CANDIDATE_MANIFEST_SHA256,
    }:
        raise RuntimeError("legacy approval candidate-manifest reference changed")
    # The development preview manifest continued evolving after this immutable
    # approval record. Validate every surviving 63 candidate unit below against
    # the approval's embedded source records instead of pretending the current
    # whole-manifest bytes still equal the historical hash.
    units_by_id = {
        str(unit.get("asset_id", "")): unit
        for unit in units
        if isinstance(unit, dict)
    }
    if len(units_by_id) != EXPECTED_NONCHARACTER_UNITS:
        raise RuntimeError("legacy approval unit IDs are invalid")
    for asset_id, spec in legacy_specs.items():
        approved = units_by_id.get(asset_id)
        if (
            not isinstance(approved, dict)
            or approved.get("source_kind") != spec["source_kind"]
            or approved.get("shipping_texture")
            != {
                "resource_path": spec["resource_path"],
                "sha256": spec["sha256"],
                "rgba8_sha256": spec["rgba8_sha256"],
                "pixel_size": spec["pixel_size"],
            }
            or approved.get("accepted_sources") != spec["accepted_sources"]
            or approved.get("selector_pixels") != spec["selector_pixels"]
            or approved.get("runtime_bindings") != spec["bindings"]
            or approved.get("runtime_bindings_sha256")
            != _canonical_sha256(spec["bindings"])
        ):
            raise RuntimeError(f"{asset_id}: legacy approval no longer matches shipping")

    source_spec = approval.get("source_spec")
    if (
        not isinstance(source_spec, dict)
        or source_spec.get("path") != SOURCE_SPEC_PATH
        or _sha256_bytes((project_root / SOURCE_SPEC_PATH).read_bytes())
        != source_spec.get("sha256")
    ):
        raise RuntimeError("legacy source contract changed")
    review_reports = approval.get("final_review_reports")
    if not isinstance(review_reports, list) or [
        str(report.get("path", "")) for report in review_reports if isinstance(report, dict)
    ] != REVIEW_REPORT_PATHS:
        raise RuntimeError("legacy review report set changed")
    for report in review_reports:
        report_path = project_root / str(report["path"])
        if _sha256_bytes(report_path.read_bytes()) != report.get("sha256"):
            raise RuntimeError(f"legacy review report changed: {report['path']}")
    review_board_sha256 = _canonical_sha256(review_reports)
    if approval.get("review_board_sha256") != review_board_sha256:
        raise RuntimeError("legacy review-board hash changed")
    return approval_sha256, str(source_spec["sha256"]), review_board_sha256


def _augment_unit(
    unit: dict[str, Any],
    spec: dict[str, Any],
    approval_record_sha256: str,
    source_contract_sha256: str,
    review_board_sha256: str,
) -> dict[str, Any]:
    result = json.loads(json.dumps(unit, ensure_ascii=False))
    width, height = spec["pixel_size"]
    output_spec = result.get("output_spec", {}).copy()
    output_spec["width"] = width
    output_spec["height"] = height
    output_spec["alpha"] = spec["alpha"]
    if spec["packed_selector_count"]:
        output_spec["type"] = "png_atlas"
    result["output_spec"] = output_spec
    result["hashes"] = {
        "sha256": spec["sha256"],
        "rgba8_sha256": spec["rgba8_sha256"],
    }
    result["approval_status"] = "approved"
    result["runtime_bindings"] = spec["bindings"]
    selectors = sorted({
        str(binding["selector"])
        for binding in spec["bindings"]
        if str(binding["selector"])
    })
    result["shipping_approval_evidence"] = {
        "schema_version": EVIDENCE_SCHEMA,
        "decision": "approved",
        "authority": "explicit_user_approval_in_current_task",
        "approved_at_utc": APPROVAL_RECORDED_UTC,
        "approval_record_sha256": approval_record_sha256,
        "source_contract_sha256": source_contract_sha256,
        "review_board_sha256": review_board_sha256,
        "scope": {"kind": spec["scope"], "selectors": selectors},
        "shipping_texture": {
            "sha256": spec["sha256"],
            "rgba8_sha256": spec["rgba8_sha256"],
            "pixel_size": spec["pixel_size"],
            "output_spec": {
                "format": "PNG",
                "width": width,
                "height": height,
                "alpha": spec["alpha"],
            },
        },
        "runtime_bindings_sha256": _canonical_sha256(spec["bindings"]),
    }
    return result


def _production_scope(registry: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(registry, ensure_ascii=False))
    result["units"] = [
        unit for unit in result["units"]
        if unit["asset_id"] not in EXCLUDED_STATIC_SCOPE_IDS
    ]
    category_counts: dict[str, int] = {}
    for unit in result["units"]:
        category = unit["category"]
        category_counts[category] = category_counts.get(category, 0) + 1
    result["category_counts"] = category_counts
    if len(result["units"]) != EXPECTED_NONCHARACTER_UNITS:
        raise RuntimeError(
            f"expected {EXPECTED_NONCHARACTER_UNITS} scoped units, got {len(result['units'])}"
        )
    if "character_creature" in category_counts:
        raise RuntimeError("non-Niko character concepts must not enter the static-production scope")
    return result


def _render_registry(
    original_text: str,
    registry: dict[str, Any],
    approved: dict[str, dict[str, Any]],
    approval_record_sha256: str,
    source_contract_sha256: str,
    review_board_sha256: str,
    preserved_asset_ids: frozenset[str] = frozenset(),
) -> str:
    augmented = {
        unit["asset_id"]: _augment_unit(
            unit,
            approved[unit["asset_id"]],
            approval_record_sha256,
            source_contract_sha256,
            review_board_sha256,
        )
        for unit in registry["units"]
        if unit["asset_id"] not in preserved_asset_ids
    }
    seen: set[str] = set()
    rendered: list[str] = []
    for line in original_text.splitlines():
        if any(f'"asset_id":"{asset_id}"' in line for asset_id in EXCLUDED_STATIC_SCOPE_IDS):
            continue
        if '"category_counts"' in line:
            rendered.append(
                '  "category_counts": '
                + json.dumps(registry["category_counts"], ensure_ascii=False, separators=(", ", ": "))
                + ","
            )
            continue
        replacement = None
        for asset_id, unit in augmented.items():
            if f'"asset_id":"{asset_id}"' in line:
                trailing_comma = "," if line.rstrip().endswith(",") else ""
                replacement = (
                    "    "
                    + json.dumps(unit, ensure_ascii=False, separators=(",", ":"))
                    + trailing_comma
                )
                seen.add(asset_id)
                break
        rendered.append(replacement if replacement is not None else line)
    if seen != set(augmented):
        raise RuntimeError(f"registry unit replacement mismatch: {sorted(set(augmented) - seen)}")
    return "\n".join(rendered) + "\n"


def _build_manifest(registry: dict[str, Any], registry_sha256: str, approved: dict[str, dict[str, Any]]) -> dict[str, Any]:
    units: list[dict[str, Any]] = []
    for unit in registry["units"]:
        asset_id = unit["asset_id"]
        entry: dict[str, Any] = {
            "asset_id": asset_id,
            "static_content_id": unit["content_id"],
            "category": unit["category"],
            "declared_runtime_state": "requested_active",
            "approval_status": unit.get("approval_status", "planned"),
        }
        spec = approved[asset_id]
        entry["shipping"] = {
            "resource_path": spec["resource_path"],
            "sha256": spec["sha256"],
            "rgba8_sha256": spec["rgba8_sha256"],
            "pixel_size": spec["pixel_size"],
            "texture_filter": "nearest",
            "mipmaps": False,
        }
        entry["bindings"] = spec["bindings"]
        units.append(entry)
    if len(units) != EXPECTED_NONCHARACTER_UNITS:
        raise RuntimeError(f"expected {EXPECTED_NONCHARACTER_UNITS} non-character units, got {len(units)}")
    return {
        "schema_version": MANIFEST_SCHEMA,
        "kind": MANIFEST_KIND,
        "canonical_registry_sha256": registry_sha256,
        "expected_noncharacter_units": EXPECTED_NONCHARACTER_UNITS,
        "units": units,
    }


def _validate_media(project_root: Path, approved: dict[str, dict[str, Any]]) -> None:
    for asset_id, spec in approved.items():
        target = project_root / spec["resource_path"].removeprefix("res://")
        if not target.is_file():
            raise RuntimeError(f"{asset_id}: target media missing")
        target_bytes = target.read_bytes()
        _, pixel_size, rgba8 = _image_metadata(
            target_bytes, asset_id, require_clean_alpha=True
        )
        if _sha256_bytes(target_bytes) != spec["sha256"]:
            raise RuntimeError(f"{asset_id}: target byte hash mismatch")
        if pixel_size != spec["pixel_size"] or rgba8 != spec["rgba8_sha256"]:
            raise RuntimeError(f"{asset_id}: target decoded metadata mismatch")


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".task6.tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _atomic_write_bytes(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".task6.tmp")
    temporary.write_bytes(content)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write registry/runtime metadata only; approved media and approval records stay read-only",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    workspace = project_root.parents[1] if project_root.parent.name == ".worktrees" else project_root.parent
    registry_path = project_root / "game/content/assets/gogobro_static_assets_v1.json"
    manifest_path = project_root / "game/content/assets/gogobro_static_runtime_bindings_v1.json"
    original_text = registry_path.read_text(encoding="utf-8")
    registry = _production_scope(json.loads(original_text))
    registry_units = {unit["asset_id"]: unit for unit in registry["units"]}
    candidate_specs, expected_candidate_media = _candidate_specs(
        workspace,
        project_root,
        registry_units,
        ART_V2_OVERRIDE_IDS,
    )
    _assert_immutable_media(expected_candidate_media, "legacy candidate media")
    shipping_only_specs = _shipping_only_specs(workspace, project_root)
    superseded_legacy_media = _validated_superseded_legacy_media(project_root)
    art_v2_specs = _art_v2_override_specs(project_root, registry_units)
    if len(candidate_specs) != EXPECTED_CANDIDATE_UNITS - len(ART_V2_OVERRIDE_IDS):
        raise RuntimeError("accepted candidate set must retain exactly 63 non-art-v2 units")
    release_sets = [set(candidate_specs), set(shipping_only_specs), set(art_v2_specs)]
    if (
        any(release_sets[left].intersection(release_sets[right]) for left in range(3) for right in range(left + 1, 3))
        or set().union(*release_sets) != set(registry_units)
    ):
        raise RuntimeError("accepted 63 + shipping-only 5 + art-v2 2 must form the exact canonical 70-unit set")
    legacy_specs = {**shipping_only_specs, **candidate_specs}
    legacy_primary_paths = {
        _project_resource_target(project_root, str(spec["resource_path"]))
        for spec in legacy_specs.values()
    }
    if len(legacy_primary_paths) != EXPECTED_NONCHARACTER_UNITS - len(ART_V2_OVERRIDE_IDS):
        raise RuntimeError("legacy immutable primary media must contain exactly 68 targets")
    immutable_legacy_paths = {
        *expected_candidate_media,
        *legacy_primary_paths,
        *superseded_legacy_media,
    }
    approval_sha256, source_contract_sha256, review_board_sha256 = _legacy_approval_evidence(
        project_root,
        legacy_specs,
    )
    approved = {**legacy_specs, **art_v2_specs}
    desired_registry_text = _render_registry(
        original_text,
        registry,
        approved,
        approval_sha256,
        source_contract_sha256,
        review_board_sha256,
        ART_V2_OVERRIDE_IDS,
    )
    desired_registry = json.loads(desired_registry_text)
    desired_registry_units = {unit["asset_id"]: unit for unit in desired_registry["units"]}
    for asset_id in ART_V2_OVERRIDE_IDS:
        if desired_registry_units[asset_id] != registry_units[asset_id]:
            raise RuntimeError(f"{asset_id}: art-v2 registry override was not preserved byte-semantically")
    if _art_v2_override_specs(project_root, desired_registry_units) != art_v2_specs:
        raise RuntimeError("art-v2 overlay changed while rendering the registry")
    desired_registry_sha256 = _sha256_bytes(desired_registry_text.encode("utf-8"))
    manifest = _build_manifest(desired_registry, desired_registry_sha256, approved)
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    desired_files = _metadata_write_plan(
        project_root,
        desired_registry_text,
        manifest_text,
        immutable_legacy_paths,
    )
    changed = sorted(
        path
        for path, desired in desired_files.items()
        if not path.is_file() or path.read_bytes() != desired
    )
    if args.apply:
        for path in changed:
            desired = desired_files[path]
            if path.suffix.lower() == ".png":
                raise RuntimeError(f"immutable media write was scheduled: {path}")
            _atomic_write(path, desired.decode("utf-8"))
    if args.apply or not changed:
        _validate_media(project_root, approved)

    print(
        f"PASS static shipping plan: {len(approved)} active / "
        f"{EXPECTED_NONCHARACTER_UNITS - len(approved)} inactive; "
        f"pending={len(changed) if not args.apply else 0}; registry={desired_registry_sha256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
