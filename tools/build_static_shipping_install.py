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
EXPECTED_SHIPPING_ONLY_UNITS = 5
CANDIDATE_MANIFEST_PATH = "game/content/assets/gogobro_static_candidate_preview_v1.json"
APPROVAL_PATH = "game/content/assets/gogobro_static_shipping_approval_2026-08-28.json"
SOURCE_SPEC_PATH = "docs/superpowers/specs/2026-08-28-runtime-clarity-combat-completion-design.md"
REVIEW_REPORT_PATHS = [
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-1-report.md",
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-2-report.md",
    ".superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-3-report.md",
]
OVERLAP_REPLACEMENTS = {
    "ballistic_liner",
    "service_pistol",
    "smoke_shell_helmet",
    "warmup_shiv",
}
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


def _binding(
    asset_id: str,
    role: str,
    selector: str,
    atlas_rect: list[int],
    display_size: list[int],
    display_scale: list[float | int],
    consumers: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "binding_key": f"{asset_id}|{role}|{selector}",
        "role": role,
        "selector": selector,
        "display_size_px": display_size,
        "display_scale": display_scale,
        "pivot_px": [32, 32],
        "atlas_rect_px": atlas_rect,
        "anchors_px": {},
        "consumers": consumers or [],
    }


def _global_binding(asset_id: str, selector: str, order: int) -> dict[str, Any]:
    return _binding(
        asset_id,
        asset_id,
        selector,
        [order * 64, 0, 64, 64],
        [64, 64],
        [1, 1],
        [{"kind": "global", "role": asset_id, "selector": selector}],
    )


def _approved_units() -> dict[str, dict[str, Any]]:
    units: dict[str, dict[str, Any]] = {
        "service_pistol": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/service_pistol/final/service_pistol.png",
            "resource_path": "res://game/assets/gogobro_static/weapons/service_pistol.png",
            "sha256": "E477BE6A44C4873F63939EBB2FBF6EE2247C2A5C7DC15FF8B6FE2D1C7C1A6654",
            "rgba8_sha256": "8C1F394E9035345057C0E11DA93F09E62506989CE72C7BDF912AF6CEF7617CE6",
            "pixel_size": [512, 512],
            "scope": "whole_texture",
            "bindings": [
                _binding(
                    "service_pistol",
                    "icon",
                    "",
                    [0, 0, 512, 512],
                    [64, 64],
                    [0.125, 0.125],
                    [{
                        "kind": "content",
                        "content_kind": "weapon",
                        "content_id": "weapon.training_blaster:weapon/training_blaster",
                        "role": "icon",
                        "selector": "",
                    }],
                )
            ],
        },
        "warmup_shiv": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/warmup_shiv/final/warmup_shiv.png",
            "resource_path": "res://game/assets/gogobro_static/weapons/warmup_shiv.png",
            "sha256": "E2B6A36BCDCF108A2F8E29492F1419AE07CC4E4BC5C6FACFBA4EF2EDEF186B93",
            "rgba8_sha256": "83963A0EC2A4B744A22A07C887648AE8617041FA159762A42C3D5655246D099E",
            "pixel_size": [512, 512],
            "scope": "whole_texture",
            "bindings": [
                _binding(
                    "warmup_shiv",
                    "icon",
                    "",
                    [0, 0, 512, 512],
                    [64, 64],
                    [0.125, 0.125],
                    [{
                        "kind": "content",
                        "content_kind": "weapon",
                        "content_id": "weapon.training_blade:weapon/training_blade",
                        "role": "icon",
                        "selector": "",
                    }],
                )
            ],
        },
        "ballistic_liner": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/ballistic_liner/final/ballistic_liner.png",
            "resource_path": "res://game/assets/gogobro_static/items/ballistic_liner.png",
            "sha256": "1F673E6190EB9627B58EAA287FD22DB0F113AE80A6C7529C63EC4FBCDF89BC9F",
            "rgba8_sha256": "C7E158C4AFB1B82AA67356460BEAB74DA3FA81B01882DAE0977487DF9340D6AC",
            "pixel_size": [256, 256],
            "scope": "inventory_icon_only",
            "bindings": [
                _binding("ballistic_liner", "icon", "", [0, 0, 256, 256], [64, 64], [0.25, 0.25])
            ],
        },
        "smoke_shell_helmet": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/icon-256.png",
            "resource_path": "res://game/assets/gogobro_static/items/smoke_shell_helmet.png",
            "sha256": "9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC",
            "rgba8_sha256": "464024337E477016C80D4D54AB2D959B323F6D8748EEF6D4B5A6FC595A047741",
            "pixel_size": [256, 256],
            "scope": "inventory_icon_only",
            "approval_mode": "candidate_history",
            "bindings": [
                _binding("smoke_shell_helmet", "icon", "", [0, 0, 256, 256], [64, 64], [0.25, 0.25])
            ],
        },
        "one_more_round": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/one_more_round/final/one_more_round.png",
            "resource_path": "res://game/assets/gogobro_static/upgrades/one_more_round.png",
            "sha256": "6B817E9938A96E18622177CC15C9BDD4D880A40360FD471363F879C2BE78881A",
            "rgba8_sha256": "FF56FDBB2DAEE9A9B0CA94C1D416E75A11C341C8930DBB6684B2F0F21455895D",
            "pixel_size": [256, 256],
            "scope": "whole_texture",
            "bindings": [
                _binding("one_more_round", "icon", "", [0, 0, 256, 256], [64, 64], [0.25, 0.25])
            ],
        },
        "hud_icon_kit": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/hud_icon_kit/atlas-candidate/hud_icon_kit.png",
            "resource_path": "res://game/assets/gogobro_static/ui/hud_icon_kit.png",
            "sha256": "EDEBA2203CA8B36CA38FA9E62EFDA768091DE003E56AD88D0125E83C63764A77",
            "rgba8_sha256": "CAA1C67F314BAE0CBCEB78644C04E4DFD579B2AFC4430389D8A951BF8ED2C9D1",
            "pixel_size": [1024, 1024],
            "scope": "selector_set",
            "bindings": [
                _global_binding("hud_icon_kit", selector, order)
                for order, selector in enumerate(["health", "wave", "wave_timer"])
            ],
        },
        "control_icon_kit": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/control_icon_kit/atlas-candidate/control_icon_kit-1024x1024-candidate.png",
            "resource_path": "res://game/assets/gogobro_static/ui/control_icon_kit.png",
            "sha256": "933674F3631D2607A23D086E95BF4328EF916E53275F4C8F409EF87FE1F0374F",
            "rgba8_sha256": "9F19DB4AD816755F11076769CEBC11184CEE4B8E8C1811EB3BC84A7DD96DBECC",
            "pixel_size": [1024, 1024],
            "scope": "selector_set",
            "bindings": [
                _global_binding("control_icon_kit", selector, order)
                for order, selector in enumerate([
                    "move_keyboard_wasd", "move_gamepad_left_stick", "auto_attack"
                ])
            ],
        },
        "difficulty_badge_kit": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/difficulty_badge_kit/atlas-candidate/difficulty_badge_kit.png",
            "resource_path": "res://game/assets/gogobro_static/ui/difficulty_badge_kit.png",
            "sha256": "628FE9252024323F4FE83D00B62B71C626EE58F51D446BD02C784973135E0BE4",
            "rgba8_sha256": "ED0F78DA10A24846136B02B21338484C666019D309260A216F7F3BF117B95D19",
            "pixel_size": [1024, 256],
            "scope": "selector_set",
            "bindings": [_global_binding("difficulty_badge_kit", "standard", 0)],
        },
        "projectile_hit_kit": {
            "source": "GOGOBRO_ASSET_INBOX/02_static_assets/batches/wave-032-first-approved-production/projectile_hit_kit/atlas-candidate/projectile_hit_kit-atlas-candidate.png",
            "resource_path": "res://game/assets/gogobro_static/projectiles/projectile_hit_kit.png",
            "sha256": "989759C33AC95BE5FAF6F28A9DFBCF50A903B46FCDF6AA0B098F30FBD4BE5992",
            "rgba8_sha256": "3A310B8B6D05E7971C89E33983A0DDFC3C49136A23CD1FD4BF6016C5D59041D0",
            "pixel_size": [1024, 1024],
            "scope": "selector_set",
            "bindings": [
                _binding(
                    "projectile_hit_kit",
                    "projectile_sprite" if order < 4 else "impact_sprite",
                    selector,
                    [order * 64, 0, 64, 64],
                    [64, 64],
                    [1, 1],
                )
                for order, selector in enumerate([
                    "pistol_smg_round", "rifle_round", "sniper_round", "hostile_pulse",
                    "static_hit_mark", "static_critical_mark", "static_pierce_mark",
                    "static_explosion_mark",
                ])
            ],
        },
    }
    return units


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


def _candidate_specs(
    workspace: Path,
    project_root: Path,
    registry_units: dict[str, dict[str, Any]],
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
        if not shipping_path.startswith("res://game/assets/gogobro_static/"):
            raise RuntimeError(f"{asset_id}: canonical shipping path is invalid")

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
                desired_media[project_root / copy_path.removeprefix("res://")] = media_bytes[index]
                source_records[index]["shipping_source_copy_path"] = copy_path
        else:
            shipping_bytes = media_bytes[0]
        desired_media[project_root / shipping_path.removeprefix("res://")] = shipping_bytes
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


def _shipping_only_specs(project_root: Path) -> dict[str, dict[str, Any]]:
    legacy = _approved_units()
    if set(legacy).intersection(SHIPPING_ONLY_IDS) != SHIPPING_ONLY_IDS:
        raise RuntimeError("legacy shipping-only baseline is incomplete")
    specs: dict[str, dict[str, Any]] = {}
    for asset_id in sorted(SHIPPING_ONLY_IDS):
        spec = json.loads(json.dumps(legacy[asset_id]))
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
            raise RuntimeError(f"{asset_id}: shipping-only baseline changed")
        if asset_id == "one_more_round":
            spec["bindings"][0]["consumers"] = [_content_consumer("upgrade", asset_id)]
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
        spec.update({
            "alpha": True,
            "source_kind": "retained_shipping_only",
            "accepted_sources": [],
            "selector_pixels": selector_pixels,
            "packed_selector_count": len([row for row in selector_pixels if row["selector"]]),
        })
        specs[asset_id] = spec
    return specs


def _build_approval_record(
    project_root: Path,
    registry: dict[str, Any],
    specs: dict[str, dict[str, Any]],
) -> tuple[str, str, str, str]:
    source_spec_path = project_root / SOURCE_SPEC_PATH
    source_spec_sha256 = _sha256_bytes(source_spec_path.read_bytes())
    review_reports = []
    for path in REVIEW_REPORT_PATHS:
        review_path = project_root / path
        review_reports.append({
            "path": path,
            "sha256": _sha256_bytes(review_path.read_bytes()),
        })
    review_board_sha256 = _canonical_sha256(review_reports)
    units = []
    for unit in registry["units"]:
        asset_id = unit["asset_id"]
        spec = specs[asset_id]
        units.append({
            "asset_id": asset_id,
            "source_kind": spec["source_kind"],
            "shipping_texture": {
                "resource_path": spec["resource_path"],
                "sha256": spec["sha256"],
                "rgba8_sha256": spec["rgba8_sha256"],
                "pixel_size": spec["pixel_size"],
            },
            "accepted_sources": spec["accepted_sources"],
            "selector_pixels": spec["selector_pixels"],
            "runtime_bindings": spec["bindings"],
            "runtime_bindings_sha256": _canonical_sha256(spec["bindings"]),
        })
    record = {
        "schema_version": "gogobro-static-shipping-approval-2026-08-28-v1",
        "decision": "approved",
        "authority": "explicit_user_approval_in_current_task",
        "approved_at_utc": APPROVAL_RECORDED_UTC,
        "completion_scope": "runtime_clarity_combat_completion_70_static_units",
        "source_spec": {"path": SOURCE_SPEC_PATH, "sha256": source_spec_sha256},
        "accepted_candidate_manifest": {
            "path": CANDIDATE_MANIFEST_PATH,
            "sha256": _sha256_bytes((project_root / CANDIDATE_MANIFEST_PATH).read_bytes()),
        },
        "final_review_reports": review_reports,
        "review_board_sha256": review_board_sha256,
        "accepted_candidate_unit_count": EXPECTED_CANDIDATE_UNITS,
        "shipping_only_unit_count": EXPECTED_SHIPPING_ONLY_UNITS,
        "approved_unit_count": EXPECTED_NONCHARACTER_UNITS,
        "overlap_replacements": sorted(OVERLAP_REPLACEMENTS),
        "shipping_only_asset_ids": sorted(SHIPPING_ONLY_IDS),
        "units": units,
    }
    text = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
    return text, _sha256_bytes(text.encode("utf-8")), source_spec_sha256, review_board_sha256


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
    if seen != set(approved):
        raise RuntimeError(f"registry unit replacement mismatch: {sorted(set(approved) - seen)}")
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
    parser.add_argument("--apply", action="store_true", help="write promoted media, approval, registry, and manifest")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    workspace = project_root.parents[1] if project_root.parent.name == ".worktrees" else project_root.parent
    registry_path = project_root / "game/content/assets/gogobro_static_assets_v1.json"
    manifest_path = project_root / "game/content/assets/gogobro_static_runtime_bindings_v1.json"
    approval_path = project_root / APPROVAL_PATH
    original_text = registry_path.read_text(encoding="utf-8")
    registry = _production_scope(json.loads(original_text))
    registry_units = {unit["asset_id"]: unit for unit in registry["units"]}
    candidate_specs, desired_media = _candidate_specs(workspace, project_root, registry_units)
    shipping_only_specs = _shipping_only_specs(project_root)
    if set(candidate_specs).intersection(shipping_only_specs) or set(candidate_specs).union(shipping_only_specs) != set(registry_units):
        raise RuntimeError("accepted 65 + shipping-only 5 must form the exact canonical 70-unit set")
    if set(candidate_specs).intersection(set(_approved_units())) != OVERLAP_REPLACEMENTS:
        raise RuntimeError("accepted candidate overlap must be the exact four replacement IDs")
    approved = {**shipping_only_specs, **candidate_specs}
    approval_text, approval_sha256, source_contract_sha256, review_board_sha256 = _build_approval_record(
        project_root, registry, approved
    )
    desired_registry_text = _render_registry(
        original_text,
        registry,
        approved,
        approval_sha256,
        source_contract_sha256,
        review_board_sha256,
    )
    desired_registry = json.loads(desired_registry_text)
    desired_registry_sha256 = _sha256_bytes(desired_registry_text.encode("utf-8"))
    manifest = _build_manifest(desired_registry, desired_registry_sha256, approved)
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    desired_files: dict[Path, bytes] = {
        **desired_media,
        approval_path: approval_text.encode("utf-8"),
        registry_path: desired_registry_text.encode("utf-8"),
        manifest_path: manifest_text.encode("utf-8"),
    }
    changed = sorted(
        path
        for path, desired in desired_files.items()
        if not path.is_file() or path.read_bytes() != desired
    )
    if args.apply:
        for path in changed:
            desired = desired_files[path]
            if path.suffix.lower() == ".png":
                _atomic_write_bytes(path, desired)
            else:
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
