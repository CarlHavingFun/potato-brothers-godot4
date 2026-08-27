#!/usr/bin/env python3
"""Deterministically install the first Wave033-approved static runtime bindings.

This tool intentionally activates only geometry-safe surfaces. Weapon world pivots,
the incomplete four-state button atlas, supply-crate placement, and worn appearance
layers remain inactive. Non-Niko character concepts and the revoked generic service
carbine are excluded from the canonical static-production scope.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

from PIL import Image


APPROVAL_RECORDED_UTC = "2026-08-26T13:18:20Z"
APPROVAL_RECORD_SHA256 = "55650881C916C9D886ED4B47CDEAA187487E4B4F3BE84A3D90B09105BE461786"
SOURCE_CONTRACT_SHA256 = "3BC5F2E3E52922F8BEDD72AA4FF30F9198EF025FCD4DDBE772EC1AD667363973"
REVIEW_BOARD_SHA256 = "4E6770DF75EFB3A31126E62368C4F0E0B3A045F4647385580612B437B1AC82C9"
EVIDENCE_SCHEMA = "gogobro-static-shipping-approval-v1"
MANIFEST_SCHEMA = "gogobro-static-runtime-bindings-v1"
MANIFEST_KIND = "shipping_runtime_bindings"
EXPECTED_NONCHARACTER_UNITS = 70
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


def _augment_unit(unit: dict[str, Any], spec: dict[str, Any]) -> dict[str, Any]:
    result = json.loads(json.dumps(unit, ensure_ascii=False))
    result["hashes"] = {
        "sha256": spec["sha256"],
        "rgba8_sha256": spec["rgba8_sha256"],
    }
    result["approval_status"] = "approved"
    result["runtime_bindings"] = spec["bindings"]
    if spec.get("approval_mode") == "candidate_history":
        active_candidate_id = result["active_candidate_id"]
        active_candidate = next(
            candidate
            for candidate in result["candidate_history"]
            if candidate["candidate_id"] == active_candidate_id
        )
        active_candidate["runtime_bindings_sha256"] = _canonical_sha256(spec["bindings"])
        icon_artifact = next(
            artifact
            for artifact in active_candidate["artifacts"]
            if artifact["role"] == "icon"
        )
        icon_artifact["rgba8_sha256"] = spec["rgba8_sha256"]
        icon_artifact["pixel_size"] = spec["pixel_size"]
        result.pop("shipping_approval_evidence", None)
        return result
    selectors = [binding["selector"] for binding in spec["bindings"]] if spec["scope"] == "selector_set" else []
    width, height = spec["pixel_size"]
    result["shipping_approval_evidence"] = {
        "schema_version": EVIDENCE_SCHEMA,
        "decision": "approved",
        "authority": "explicit_user_approval_in_current_task",
        "approved_at_utc": APPROVAL_RECORDED_UTC,
        "approval_record_sha256": APPROVAL_RECORD_SHA256,
        "source_contract_sha256": SOURCE_CONTRACT_SHA256,
        "review_board_sha256": REVIEW_BOARD_SHA256,
        "scope": {"kind": spec["scope"], "selectors": selectors},
        "shipping_texture": {
            "sha256": spec["sha256"],
            "rgba8_sha256": spec["rgba8_sha256"],
            "pixel_size": spec["pixel_size"],
            "output_spec": {"format": "PNG", "width": width, "height": height, "alpha": True},
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


def _render_registry(original_text: str, registry: dict[str, Any], approved: dict[str, dict[str, Any]]) -> str:
    augmented = {
        unit["asset_id"]: _augment_unit(unit, approved[unit["asset_id"]])
        for unit in registry["units"]
        if unit["asset_id"] in approved
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
            "declared_runtime_state": "requested_active" if asset_id in approved else "inactive",
            "approval_status": unit.get("approval_status", "planned"),
        }
        if asset_id in approved:
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


def _validate_media(workspace: Path, project_root: Path, approved: dict[str, dict[str, Any]]) -> None:
    for asset_id, spec in approved.items():
        source = workspace / spec["source"]
        target = project_root / spec["resource_path"].removeprefix("res://")
        if not source.is_file() or not target.is_file():
            raise RuntimeError(f"{asset_id}: source or target media missing")
        source_bytes = source.read_bytes()
        target_bytes = target.read_bytes()
        if source_bytes != target_bytes or _sha256_bytes(target_bytes) != spec["sha256"]:
            raise RuntimeError(f"{asset_id}: target bytes do not match approved source")
        with Image.open(target) as image:
            rgba = image.convert("RGBA")
            if list(rgba.size) != spec["pixel_size"]:
                raise RuntimeError(f"{asset_id}: pixel size mismatch")
            if _sha256_bytes(rgba.tobytes()) != spec["rgba8_sha256"]:
                raise RuntimeError(f"{asset_id}: decoded RGBA8 hash mismatch")
            alpha = set(rgba.getchannel("A").get_flattened_data())
            if not alpha.issubset({0, 255}):
                raise RuntimeError(f"{asset_id}: alpha is not binary")
            if any(
                pixel[3] == 0 and pixel[:3] != (0, 0, 0)
                for pixel in rgba.get_flattened_data()
            ):
                raise RuntimeError(f"{asset_id}: transparent RGB is not zero")


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".wave033.tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write registry and shipping manifest")
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    workspace = project_root.parents[1] if project_root.parent.name == ".worktrees" else project_root.parent
    registry_path = project_root / "game/content/assets/gogobro_static_assets_v1.json"
    manifest_path = project_root / "game/content/assets/gogobro_static_runtime_bindings_v1.json"
    approved = _approved_units()
    original_text = registry_path.read_text(encoding="utf-8")
    registry = _production_scope(json.loads(original_text))
    desired_registry_text = _render_registry(original_text, registry, approved)
    desired_registry = json.loads(desired_registry_text)
    desired_registry_sha256 = _sha256_bytes(desired_registry_text.encode("utf-8"))
    manifest = _build_manifest(desired_registry, desired_registry_sha256, approved)
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    _validate_media(workspace, project_root, approved)
    if args.apply:
        _atomic_write(registry_path, desired_registry_text)
        _atomic_write(manifest_path, manifest_text)
    elif registry_path.read_text(encoding="utf-8") != desired_registry_text:
        raise RuntimeError("registry does not match the deterministic Wave033 shipping plan; run with --apply")
    elif not manifest_path.is_file() or manifest_path.read_text(encoding="utf-8") != manifest_text:
        raise RuntimeError("shipping manifest does not match the deterministic Wave033 plan; run with --apply")

    print(
        f"PASS static shipping plan: {len(approved)} active / "
        f"{EXPECTED_NONCHARACTER_UNITS - len(approved)} inactive; registry={desired_registry_sha256}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
