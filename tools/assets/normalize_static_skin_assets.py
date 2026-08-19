#!/usr/bin/env python3
"""Deterministically install approved user-generated static skin art.

Source collections live outside shipping paths. This script intentionally
copies only hash-pinned approved PNGs plus the 37 QA-approved passive finals.
Prompt files, unselected candidates, review sheets, identity references and
videos are never copied into the skin.

Run with the sprite-gen virtual environment so Pillow's implementation is
explicit, for example:

  C:/Users/<user>/.codex/skills/sprite-gen/.venv/Scripts/python.exe \
    tools/assets/normalize_static_skin_assets.py \
    --source-root E:/01_gobro/resue/assets/assets \
    --title-background C:/path/to/approved-title-background.png
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

from PIL import Image


LOGICAL_CANVAS = 64
OUTPUT_CANVAS = 256
NEAREST_SCALE = OUTPUT_CANVAS // LOGICAL_CANVAS
SKIN_RELATIVE_ROOT = Path("content_packs/skins/lets_gooooo")
ASSET_RES_ROOT = "res://content_packs/skins/lets_gooooo/assets"
EXISTING_COLLECTION = "approved-static-set-2026-08-18"
CURATED_COLLECTION = "sprite-gen-curated-weapons-2026-08-18"
CURATED_WORLD_COLLECTION = "sprite-gen-curated-world-assets-2026-08-18"
CURATED_PROJECTILE_COLLECTION = "sprite-gen-curated-projectiles-2026-08-18"
CURATED_PASSIVE_COLLECTION = "sprite-gen-curated-passives-2026-08-18"
GENERATED_SCENE_COLLECTION = "generated-scene-art-2026-08-18"
CODE_NATIVE_COLLECTION = "original-code-native-vectors-2026-08-18"
OWNED_COLLECTIONS = {
    EXISTING_COLLECTION,
    CURATED_COLLECTION,
    CURATED_WORLD_COLLECTION,
    CURATED_PROJECTILE_COLLECTION,
    CURATED_PASSIVE_COLLECTION,
    GENERATED_SCENE_COLLECTION,
    CODE_NATIVE_COLLECTION,
}
PASSIVE_CURATION_REL_ROOT = Path("builds/skin_curation/passives_missing")
PASSIVE_SELECTION_SHA256 = "3ba081d98d3920629ff7c7bb67ff0103c5b5e50eadc9c17808e4c63dcbf54861"
PASSIVE_QA_SHA256 = "ce9c94ca4a3cbb2323cfd6eb801ce134dfbb08aeb48279cfa7cf62c0cf508e95"
CURATED_PASSIVE_IDS = (
    "passive.arc_lens",
    "passive.bargain_chip",
    "passive.blood_filter",
    "passive.blood_vial",
    "passive.butterfly",
    "passive.cinder_seed",
    "passive.coffee",
    "passive.crack",
    "passive.dash_blades",
    "passive.dash_charge",
    "passive.drone_uplink",
    "passive.ember_reservoir",
    "passive.fortune_charm",
    "passive.frost_capacitor",
    "passive.golden_seed",
    "passive.harvest_bell",
    "passive.iron_bark",
    "passive.knight_helmet",
    "passive.leech",
    "passive.market_map",
    "passive.medic_patch",
    "passive.merchant_badge",
    "passive.mighty_sword",
    "passive.missile",
    "passive.plant",
    "passive.power_ball",
    "passive.prospector_eye",
    "passive.rage",
    "passive.recycler_stamp",
    "passive.round_hat",
    "passive.salvage_hook",
    "passive.second_skin",
    "passive.shock_padding",
    "passive.storm_conductor",
    "passive.thorn_mesh",
    "passive.turret_gears",
    "passive.vest",
)


def _weapon(
    presentation_id: str,
    output_name: str,
    source_rel: str,
    source_sha256: str,
    source_ref: str,
    *,
    anchor_kind: str = "muzzle",
    content_limit: tuple[int, int] | None = None,
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": "weapon_icon",
        "output_rel": f"weapons/{output_name}.png",
        "source_rel": source_rel,
        "source_sha256": source_sha256,
        "source_ref": source_ref,
        "content_limit": list(content_limit or ((50, 50) if anchor_kind != "muzzle" else (58, 50))),
        "anchor_kind": anchor_kind,
        "source_scope": "external",
        "source_kind": "user_supplied_generated_art",
        "source_collection": EXISTING_COLLECTION,
        "approval_basis": "user_selected_existing_generated_asset_for_reuse",
        "rights_basis": "user_attested_reusable_generated_art",
    }


def _curated_weapon(
    presentation_id: str,
    output_name: str,
    source_rel: str,
    source_sha256: str,
    source_ref: str,
    *,
    anchor_kind: str,
    content_limit: tuple[int, int],
) -> dict[str, Any]:
    spec = _weapon(
        presentation_id,
        output_name,
        source_rel,
        source_sha256,
        source_ref,
        anchor_kind=anchor_kind,
        content_limit=content_limit,
    )
    spec.update(
        {
            "source_scope": "project",
            "source_kind": "generated_and_curated_art",
            "source_collection": CURATED_COLLECTION,
            "source_pipeline": ["built_in_image_gen", "sprite_gen_curation"],
            "approval_basis": "agent_visual_qa",
            "rights_basis": "generated_for_project",
            "chroma_cleanup": True,
        }
    )
    return spec


def _curated_world_asset(
    presentation_id: str,
    category: str,
    output_rel: str,
    source_rel: str,
    source_sha256: str,
    source_ref: str,
    use: str | tuple[str, ...],
    anchor_kind: str,
    content_limit: tuple[int, int] = (50, 50),
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": category,
        "output_rel": output_rel,
        "source_rel": source_rel,
        "source_sha256": source_sha256,
        "source_ref": source_ref,
        "content_limit": list(content_limit),
        "anchor_kind": anchor_kind,
        "source_scope": "project",
        "source_kind": "generated_and_curated_art",
        "source_collection": CURATED_WORLD_COLLECTION,
        "source_pipeline": ["built_in_image_gen", "sprite_gen_curation"],
        "approval_basis": "agent_visual_qa",
        "rights_basis": "generated_for_project",
        "chroma_cleanup": True,
        "uses": [use],
    }


def _curated_projectile(
    presentation_id: str,
    output_name: str,
    source_rel: str,
    source_sha256: str,
    source_ref: str,
    content_limit: tuple[int, int],
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": "projectile_world",
        "output_rel": f"projectiles/{output_name}.png",
        "source_rel": source_rel,
        "source_sha256": source_sha256,
        "source_ref": source_ref,
        "content_limit": list(content_limit),
        "anchor_kind": "projectile",
        "source_scope": "project",
        "source_kind": "generated_and_curated_art",
        "source_collection": CURATED_PROJECTILE_COLLECTION,
        "source_pipeline": ["built_in_image_gen", "sprite_gen_curation"],
        "approval_basis": "agent_visual_qa",
        "rights_basis": "generated_for_project",
        "chroma_cleanup": True,
        "component_policy": "significant_group",
        "uses": ["projectile.world"],
    }


def _passive(
    presentation_id: str,
    output_name: str,
    source_rel: str,
    source_sha256: str,
    source_ref: str,
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": "passive_icon",
        "output_rel": f"passives/{output_name}.png",
        "source_rel": source_rel,
        "source_sha256": source_sha256,
        "source_ref": source_ref,
        "content_limit": [50, 50],
        "anchor_kind": "none",
        "source_scope": "external",
        "source_kind": "user_supplied_generated_art",
        "source_collection": EXISTING_COLLECTION,
        "approval_basis": "user_selected_existing_generated_asset_for_reuse",
        "rights_basis": "user_attested_reusable_generated_art",
    }


def _generated_scene(
    presentation_id: str,
    category: str,
    output_rel: str,
    source_sha256: str,
    source_ref: str,
    source_arg: str,
    use: str,
    minimum_canvas: tuple[int, int],
    aspect: str,
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": category,
        "output_rel": output_rel,
        "source_sha256": source_sha256,
        "source_ref": source_ref,
        "source_arg": source_arg,
        "uses": list(use) if isinstance(use, tuple) else [use],
        "minimum_canvas": list(minimum_canvas),
        "aspect": aspect,
    }


def _code_native_vector(
    presentation_id: str,
    category: str,
    output_rel: str,
    sha256: str,
    asset_ref: str,
    use: str,
) -> dict[str, Any]:
    return {
        "presentation_id": presentation_id,
        "category": category,
        "output_rel": output_rel,
        "sha256": sha256,
        "asset_ref": asset_ref,
        "use": use,
    }


APPROVED_ASSETS: tuple[dict[str, Any], ...] = (
    _weapon(
        "weapon.carbine",
        "carbine",
        "weapons/ak_pattern_rifle/runtime/icon-right-v001.png",
        "07c1eecccda9259cb7894749005c720d57fd26a34df91deb33e6bed8719ba7b3",
        "static-weapon-01",
    ),
    _weapon(
        "weapon.shotgun",
        "shotgun",
        "weapons/m4_pattern_carbine/runtime/icon-right-v001.png",
        "ae10751a9046c72ce13ffc4258f089ce6eb7b6882e5487f1bde2d3c7223a0175",
        "static-weapon-02",
    ),
    _weapon(
        "weapon.railbow",
        "railbow",
        "weapons/m4a1_silenced/runtime/icon-right-v001.png",
        "f2dbcbe782e67686d3db461090b2fa4a10988bb9ab3300d07f4012822802ecf0",
        "static-weapon-03",
    ),
    _weapon(
        "weapon.laser",
        "laser",
        "weapons/heavy_bolt_sniper/runtime/icon-right-v001.png",
        "a726eb7b0f47b3c6de7b3ed5850b0d8c9504d90028aa564ddff919237c51dccd",
        "static-weapon-04",
    ),
    _weapon(
        "weapon.pistol",
        "pistol",
        "weapons/glock_service_pistol/runtime/icon-right-v001.png",
        "709c79c4b1854cffd5d56306031fef6fa7e04faf673e3191ee8d29d6d14eb0f4",
        "static-weapon-05",
    ),
    _weapon(
        "weapon.revolver",
        "revolver",
        "weapons/desert_eagle/runtime/icon-right-v001.png",
        "7ac3fa79f606addb750cfc627089d13e8c67d2f1512ae06bf36dabb38f2b505b",
        "static-weapon-06",
    ),
    _weapon(
        "weapon.smg",
        "smg",
        "weapons/p90_bullpup_pdw/runtime/icon-right-v001.png",
        "7b53eaa176dc38070ca22894b3aa6485a903c4fad27339ac717cba5da84739af",
        "static-weapon-07",
    ),
    _weapon(
        "weapon.shrapnel_launcher",
        "shrapnel_launcher",
        "weapons/ump45_folded_smg/runtime/icon-right-v001.png",
        "2622f3aee31809b1880e439ebcbb9007fc57793c289d442388981fb9992798ef",
        "static-weapon-08",
    ),
    _weapon(
        "weapon.needler",
        "needler",
        "weapons/mp9_compact_smg/runtime/icon-right-v001.png",
        "e08b9351ef78c1c734d52084f07522c94e5dd95a0e3cfda6e8fa2d0baf5387b3",
        "static-weapon-09",
    ),
    _weapon(
        "weapon.boomerang",
        "boomerang",
        "weapons/mac10_box_smg/runtime/icon-right-v001.png",
        "8c9031d48bc86afcba37566b10e27edbd29c2566b11fa61735ab57ef79297750",
        "static-weapon-10",
    ),
    _weapon(
        "weapon.drone_beacon",
        "drone_beacon",
        "weapons/usp_silenced/runtime/icon-right-v001.png",
        "8f49d720c2fc4865438283e8076df82971df38a0f60b2ec35cdbc42c72c5c174",
        "static-weapon-11",
    ),
    _weapon(
        "weapon.ember_staff",
        "ember_staff",
        "items/one_g_molotov/source/icon-v001.png",
        "c62f0a8449147b2865b92d32a21053c6b459ff049641495c2d623bf6a1e8e5c3",
        "static-weapon-12",
        anchor_kind="throw",
    ),
    _curated_weapon(
        "weapon.axe",
        "axe",
        "builds/skin_curation/melee_set_a/candidates/bowie_c.png",
        "7cf585aaaf8f910dfde45dccbc2881a75a21fc4be20d1c5b7871a8d21884176b",
        "curated-weapon-01",
        anchor_kind="melee",
        content_limit=(58, 50),
    ),
    _curated_weapon(
        "weapon.chainsaw",
        "chainsaw",
        "builds/skin_curation/melee_set_a/candidates/butterfly_c.png",
        "00bff3af1274788165b5c30a70ea5be19ff3c93594607df7c14aba0048ff5108",
        "curated-weapon-02",
        anchor_kind="melee",
        content_limit=(58, 50),
    ),
    _curated_weapon(
        "weapon.mace",
        "mace",
        "builds/skin_curation/melee_set_a/candidates/m9_c.png",
        "3713464d6773319de2c88e771abf82d6eb70cf0063e55e771f26fc8cb027368a",
        "curated-weapon-03",
        anchor_kind="melee",
        content_limit=(58, 50),
    ),
    _curated_weapon(
        "weapon.punch",
        "punch",
        "builds/skin_curation/melee_set_a/candidates/shadow_c.png",
        "e57feb389037cdc536fb5b8141b574d7b45520eaf5f4f73810f04d6877f95ac3",
        "curated-weapon-04",
        anchor_kind="melee",
        content_limit=(50, 50),
    ),
    _curated_weapon(
        "weapon.sword",
        "sword",
        "builds/skin_curation/melee_set_b/candidates/karambit_b.png",
        "a2bd8e81562f476c2414f7be8621390f265becd939416f52c59f053648249197",
        "curated-weapon-05",
        anchor_kind="melee",
        content_limit=(50, 50),
    ),
    _curated_weapon(
        "weapon.wand",
        "wand",
        "builds/skin_curation/melee_set_b/candidates/zeus_b.png",
        "68fe17eaf3e2296f5a0d313b88febbdb952c1613ab35bc85b87d6b60b414322f",
        "curated-weapon-06",
        anchor_kind="muzzle",
        content_limit=(52, 50),
    ),
    _curated_weapon(
        "weapon.spear",
        "spear",
        "builds/skin_curation/melee_set_b/candidates/bayonet_b.png",
        "8640cc7551e100c8da02e8036adc32a0bd0ec20b92ce172b3f016a3087383c76",
        "curated-weapon-07",
        anchor_kind="melee",
        content_limit=(58, 50),
    ),
    _curated_weapon(
        "weapon.cleaver",
        "cleaver",
        "builds/skin_curation/melee_set_b/candidates/huntsman_b.png",
        "58dc1ceb243c0dbd944416df400044c60f4b6ce951d9fec6d46cd90ccb768035",
        "curated-weapon-08",
        anchor_kind="melee",
        content_limit=(58, 50),
    ),
    _curated_weapon(
        "weapon.turret_kit",
        "turret_kit",
        "builds/skin_curation/tactical_set/candidates/c4_b.png",
        "b3879b507a51c81bcc73a30b30c9fcfc2961e838bffc755f63fbf27b2fe506cf",
        "curated-weapon-09",
        anchor_kind="place",
        content_limit=(50, 50),
    ),
    _curated_weapon(
        "weapon.void_prism",
        "void_prism",
        "builds/skin_curation/tactical_set/candidates/he_b.png",
        "c413d5dce03b5590f2ca86212c636124c35396985140933677a58f2509480606",
        "curated-weapon-10",
        anchor_kind="throw",
        content_limit=(50, 50),
    ),
    _curated_weapon(
        "weapon.storm_coil",
        "storm_coil",
        "builds/skin_curation/tactical_set/candidates/flash_b.png",
        "1dd94e86e19c9564a78a77521e1bd9b5750e1ecedd3c1bcdf6a3eda80e0a1cb2",
        "curated-weapon-11",
        anchor_kind="throw",
        content_limit=(50, 50),
    ),
    _curated_weapon(
        "weapon.frost_orb",
        "frost_orb",
        "builds/skin_curation/tactical_set/candidates/smoke_b.png",
        "b78c96277ed136449017be5b7b691a4434765ae647173743de77110db44b0e84",
        "curated-weapon-12",
        anchor_kind="throw",
        content_limit=(50, 50),
    ),
    _passive(
        "passive.helmet",
        "helmet",
        "items/smoke_grenade_helmet/source/icon-v001.png",
        "16a46c6664679124e93bd194d75c012de142a30bea161b57079a678a0ee3fa2e",
        "static-passive-01",
    ),
    _passive(
        "passive.cape",
        "cape",
        "items/rush_b_boots/source/icon-v001.png",
        "dec1037fbac0d2ef40dd659899c3fe679b56320b82811b1d11b5094294ccbe79",
        "static-passive-02",
    ),
    _passive(
        "passive.scrap_ledger",
        "scrap_ledger",
        "items/eco_coin_pouch/source/icon-v001.png",
        "291f3c8d7962b5023d839e652870c1b615e5870b0a38151606e2e7003253512b",
        "static-passive-03",
    ),
    _passive(
        "passive.muscle",
        "muscle",
        "items/pasha_biceps_dumbbell/source/icon-v001.png",
        "4531082f3a4336d740ad7fec9397535a2e324daffbdb7dd55f6cfaa52e0b50db",
        "static-passive-04",
    ),
    _passive(
        "passive.close_quarters_manual",
        "close_quarters_manual",
        "items/niko_shrimp_claw/source/icon-v001.png",
        "80e853b98b8805db1079e9846b4d52494887687f856d4d7794b438e271f969a2",
        "static-passive-05",
    ),
    _passive(
        "passive.repair_gel",
        "repair_gel",
        "items/burning_defuse_pliers/source/icon-v001.png",
        "e3951cd45a64cb111e86aeffd64848aee623d7bd5e8a1c1f08881085a855a22e",
        "static-passive-06",
    ),
    _passive(
        "passive.interest_coil",
        "interest_coil",
        "items/jame_time_watch/source/icon-v001.png",
        "8564db8787ebbeb34522d8c9e915c93f0e3b669ea4856ac733f11228a29889c7",
        "static-passive-07",
    ),
    _passive(
        "passive.volatile_core",
        "volatile_core",
        "items/x_god_grenade/source/icon-v001.png",
        "bc6bd9920699cf31b4f2385243cdcb0b80dcd1887f7eab18e3bf290aed47f86c",
        "static-passive-08",
    ),
    _passive(
        "passive.guardian_core",
        "guardian_core",
        "items/blast_broadcast_desk/source/icon-tier-1-v001.png",
        "071840bb513f28f4627f5e7a5081503892d94f94874b77954492f445685c642e",
        "static-passive-09",
    ),
    _passive(
        "passive.sharpshooter_lens",
        "sharpshooter_lens",
        "items/heavens_one_missed_shot/source/icon-v001.png",
        "d8c939dd1ca6759589ded5b52adcb19c849ad7f6426f1567772f4fc5653d601f",
        "static-passive-10",
    ),
    _passive(
        "passive.telescope",
        "telescope",
        "items/falling_awp_charm/source/icon-v001.png",
        "8c018b751ca20bf04c74a651368953ae7ddecff06efadd9da8a134a1dac0aa41",
        "static-passive-11",
    ),
    _passive(
        "passive.toxic_sludge",
        "toxic_sludge",
        "items/olofboost_step_stool/source/icon-v001.png",
        "b516ac8c635f8c84f534e056a1d8661b20b013c51c8a08ee68a13553c6d48681",
        "static-passive-12",
    ),
    _passive(
        "passive.echo_round",
        "echo_round",
        "items/xantares_interview_mic/source/icon-v001.png",
        "90e24d95810e0249f6785fb25aaa79a5752248fea99aec362850ae347816690c",
        "static-passive-13",
    ),
    _passive(
        "passive.flag",
        "flag",
        "items/zonic_law_halftime_board/source/icon-v001.png",
        "6f804725659aa6c43c267a16c228c64bc46564a577ac718bfa7d8a4745217d22",
        "static-passive-14",
    ),
    _passive(
        "passive.lucky_token",
        "lucky_token",
        "items/happy_deagle_ace_coin/source/icon-v001.png",
        "437ce60db13cdacaf93cf85bf37fb13e62ad2d8b56af3ca8e5020b5073d812b7",
        "static-passive-15",
    ),
    _passive(
        "passive.evasion_mesh",
        "evasion_mesh",
        "items/snax_sneaky_beaky_mask/source/icon-v001.png",
        "784d0bc0c54359ee98118a4759dfba92fdcf6a2ac11a474328b6bb04b71b76c0",
        "static-passive-16",
    ),
    _passive(
        "passive.battle_rhythm",
        "battle_rhythm",
        "items/ez4ence_music_cassette/source/icon-v001.png",
        "5001e054a88880645c07cf441fb4e661b5351703189bd2fc1c14d15070ab860a",
        "static-passive-17",
    ),
    _passive(
        "passive.rapid_loader",
        "rapid_loader",
        "items/flusha_mouse_lift/source/icon-v001.png",
        "6cc27c60750b5bb1efeb98ccf42390447324377c08b9dffa176a1fdf6db1996f",
        "static-passive-18",
    ),
    _passive(
        "passive.map",
        "map",
        "items/fallen_professor_lineup_chalk/source/icon-v001.png",
        "93209b6e225128c1b40e3f6f622a9d706571b5b0ce53b61f3ddb26ccb66ff3bb",
        "static-passive-19",
    ),
    _passive(
        "passive.panic_guard",
        "panic_guard",
        "items/stewie_b_hold_bandana/source/icon-v001.png",
        "9564c063aca9ba90feba8df9227fd16557145e2361ea312095ecf69be68ceb99",
        "static-passive-20",
    ),
    _passive(
        "passive.hunter_mark",
        "hunter_mark",
        "items/coldzera_jumping_awp_wing/source/icon-v001.png",
        "846e6b49b47f616dcb2be4fdf61c625b0a9916120a0391b0afc2652a08f7ce87",
        "static-passive-21",
    ),
    _passive(
        "passive.last_breath",
        "last_breath",
        "items/shox_clutch_stopwatch/source/icon-v001.png",
        "0d45d4e528b18a72ee8a7da003221428182d37bb31b7bd460ad1124eaba7a077",
        "static-passive-22",
    ),
    _passive(
        "passive.magazine",
        "magazine",
        "items/device_three_bullet_mag/source/icon-v001.png",
        "4931d66e149baed5d2e11d5fbf097c88dd0dcf60a11873f6b2d2a232dca62cb5",
        "static-passive-23",
    ),
    _curated_world_asset(
        "prop.supply_crate",
        "prop_world",
        "props/supply_crate.png",
        "builds/skin_curation/pickup_set/candidates/supply_crate_b.png",
        "913d9c966ae5baed7537a4152d83766a22d670bf8ff038e0c5c3122c0b32c155",
        "curated-world-01",
        "prop.world",
        "prop",
    ),
    _curated_world_asset(
        "pickup.material",
        "pickup_world",
        "pickups/material.png",
        "builds/skin_curation/pickup_set/candidates/material_b.png",
        "fda62a8b5414274f08c29b33b098ccfd44d466565497aa3a5ce75cc8c743c000",
        "curated-world-02",
        "pickup.world",
        "pickup",
        (48, 44),
    ),
    _curated_world_asset(
        "pickup.heal",
        "pickup_world",
        "pickups/heal.png",
        "builds/skin_curation/pickup_set/candidates/heal_b.png",
        "219e570c85393287d2c96965474169581d0837812ebeda8612fd196fb8bab154",
        "curated-world-03",
        "pickup.world",
        "pickup",
    ),
    _curated_world_asset(
        "pickup.chest",
        "pickup_world",
        "pickups/chest.png",
        "builds/skin_curation/pickup_set/candidates/reward_case_b.png",
        "6bfafc57495f76c4ba2aeb228022545eb539bb900e4e6d2db7f810148aef8d66",
        "curated-world-04",
        "pickup.world",
        "pickup",
    ),
    _curated_world_asset(
        "prop.weapon_rack",
        "prop_world",
        "props/weapon_rack.png",
        "builds/skin_curation/prop_ally_set/candidates/weapon_rack_a.png",
        "3fc7df32b9c450d57bdc478e3a4b385ee42a3c04f058b337f3ed52ceb108f113",
        "curated-world-05",
        "prop.world",
        "prop",
    ),
    _curated_world_asset(
        "ally.turret",
        "ally_world",
        "allies/turret.png",
        "builds/skin_curation/prop_ally_set/candidates/turret_a.png",
        "e4b8f99ae007ea55b9f8b610fd639e9abbdede97648ae885f213a4377570e2e1",
        "curated-world-06",
        "ally.world",
        "ally_turret",
    ),
    _curated_world_asset(
        "ally.drone",
        "ally_world",
        "allies/drone.png",
        "builds/skin_curation/prop_ally_set/candidates/drone_a.png",
        "830f392666d807a23ac8a09e83e1f57a4153c9fe76793f05e49976a43c640e5e",
        "curated-world-07",
        "ally.world",
        "ally_drone",
    ),
    _curated_world_asset(
        "prop.hazard_beacon",
        "prop_world",
        "props/hazard_beacon.png",
        "builds/skin_curation/prop_ally_set/candidates/hazard_beacon_a.png",
        "307a19857ada8fa7cfd5f964afa2bb416b2abe294b9465b31c12c9499f76ff85",
        "curated-world-08",
        "prop.world",
        "prop",
    ),
    _curated_projectile(
        "projectile.pistol",
        "pistol",
        "builds/skin_curation/projectile_set/candidates/pistol_b.png",
        "002b715eeed48f0ecd8c33af2cd0eff083216d39baf54638a1a7397f9ade770e",
        "curated-projectile-01",
        (36, 18),
    ),
    _curated_projectile(
        "projectile.rifle",
        "rifle",
        "builds/skin_curation/projectile_set/candidates/rifle_b.png",
        "695937ec7f8f5a898446863422bbc1e903ef9823c5ef96ebf040bf923322149e",
        "curated-projectile-02",
        (48, 18),
    ),
    _curated_projectile(
        "projectile.sniper",
        "sniper",
        "builds/skin_curation/projectile_set/candidates/sniper_b.png",
        "5481b5c091c445a1356a2901acbbb9b2c98fe1b2d77b69957179ad239fe60bd0",
        "curated-projectile-03",
        (54, 18),
    ),
    _curated_projectile(
        "projectile.enemy",
        "enemy",
        "builds/skin_curation/projectile_set/candidates/enemy_b.png",
        "dc1a9a2b8d6ed22c01c12f71655e2a8d2aba36c03af9b24a1cb01d70b8ad4d73",
        "curated-projectile-04",
        (32, 18),
    ),
)


GENERATED_SCENE_ASSETS: tuple[dict[str, Any], ...] = (
    _generated_scene(
        "scene.title_background",
        "scene_background",
        "ui/title_background.png",
        "eef00b4f5d009316f423d8f050a814c475987bfe0178984188b21043d5af6ed4",
        "generated-scene-01",
        "title_background",
        "scene.background",
        (1280, 720),
        "widescreen",
    ),
    _generated_scene(
        "scene.arena_floor",
        "scene_floor",
        "scenes/arena_floor.png",
        "536870cfa3b370492b88c37455c1f11f071018b396d06955ae3bf0766fea789f",
        "generated-scene-02",
        "arena_floor",
        ("scene.floor", "scene.background"),
        (1024, 1024),
        "square",
    ),
)


CODE_NATIVE_ASSETS: tuple[dict[str, Any], ...] = (
    _code_native_vector(
        "ui.logo",
        "ui_logo",
        "ui/logo.svg",
        "a33bf24f5168286b8e2d64798665e33fe361e8f13273bf73adac48edf22143f9",
        "original-vector-01",
        "ui.logo",
    ),
    _code_native_vector(
        "ui.app_icon",
        "ui_app_icon",
        "ui/app_icon.svg",
        "0502790f2d920f4590d62d7944b6bde927c3106beb5d3289ba69e52fe02903f4",
        "original-vector-02",
        "ui.app_icon",
    ),
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _audit_child(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    if not candidate.is_relative_to(root.resolve()):
        raise ValueError(f"Passive curation audit path escapes its root: {relative}")
    return candidate


def _load_curated_passive_specs(project_root: Path) -> list[dict[str, Any]]:
    audit_root = (project_root / PASSIVE_CURATION_REL_ROOT).resolve()
    selection_path = audit_root / "selection.json"
    qa_path = audit_root / "qa.json"
    if _sha256(selection_path) != PASSIVE_SELECTION_SHA256:
        raise ValueError("Passive curation selection audit hash changed")
    if _sha256(qa_path) != PASSIVE_QA_SHA256:
        raise ValueError("Passive curation QA audit hash changed")
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    qa = json.loads(qa_path.read_text(encoding="utf-8"))
    if selection.get("kind") != "lets-gooooo-passive-candidate-selection":
        raise ValueError("Unexpected passive curation selection kind")
    if qa.get("kind") != "lets-gooooo-passive-curation-qa" or not qa.get("ok"):
        raise ValueError("Passive curation QA did not pass")
    if qa.get("selection_sha256") != PASSIVE_SELECTION_SHA256:
        raise ValueError("Passive QA does not reference the approved selection audit")

    selection_items = {
        str(item["passive_id"]): item for item in selection.get("items", [])
    }
    qa_items = {str(item["passive_id"]): item for item in qa.get("items", [])}
    required_ids = set(CURATED_PASSIVE_IDS)
    if set(selection_items) != required_ids or set(qa_items) != required_ids:
        raise ValueError("Passive curation audit must contain the exact 37 missing passive IDs")

    raw_sheet_hashes: dict[str, str] = {}
    for record in qa.get("raw_sheet_hashes", []):
        raw_sheet = _audit_child(audit_root, str(record["path"]))
        expected_hash = str(record["sha256"])
        if _sha256(raw_sheet) != expected_hash:
            raise ValueError(f"Passive raw generation sheet hash changed: {raw_sheet.name}")
        raw_sheet_hashes[raw_sheet.stem] = expected_hash

    specs: list[dict[str, Any]] = []
    for index, passive_id in enumerate(sorted(required_ids), start=1):
        selection_item = selection_items[passive_id]
        qa_item = qa_items[passive_id]
        suffix = passive_id.removeprefix("passive.")
        if str(selection_item.get("stable_name", "")) != suffix:
            raise ValueError(f"Passive stable suffix changed: {passive_id}")
        picked = str(selection_item.get("picked", ""))
        candidate_rel = str(selection_item.get("candidates", {}).get(picked, ""))
        selected_candidate = _audit_child(audit_root, candidate_rel)
        normalized_input = _audit_child(
            audit_root,
            str(selection_item.get("picked_normalized_source", "")),
        )
        curated = _audit_child(audit_root, str(qa_item.get("path", "")))
        expected_curated_hash = str(qa_item.get("sha256", ""))
        if curated.name != f"{suffix}.png" or _sha256(curated) != expected_curated_hash:
            raise ValueError(f"Curated passive hash or filename changed: {passive_id}")
        for required_flag in [
            "binary_alpha",
            "transparent_rgb_zero",
            "exact_4x_nearest_grid",
            "content_within_50x50_logical",
            "ok",
        ]:
            if not qa_item.get(required_flag):
                raise ValueError(f"Curated passive failed {required_flag}: {passive_id}")
        source_batch = str(qa_item.get("source_batch", ""))
        if source_batch not in raw_sheet_hashes:
            raise ValueError(f"Curated passive has no approved raw sheet: {passive_id}")
        specs.append(
            {
                "presentation_id": passive_id,
                "category": "passive_icon",
                "output_rel": f"passives/{suffix}.png",
                "curated_path": curated,
                "curated_sha256": expected_curated_hash,
                "selected_candidate_sha256": _sha256(selected_candidate),
                "normalized_input_sha256": _sha256(normalized_input),
                "raw_sheet_sha256": raw_sheet_hashes[source_batch],
                "source_ref": f"curated-passive-{index:02d}",
                "picked": picked,
                "logical_bbox_xywh": list(qa_item["logical_bbox_xywh"]),
                "selection_sha256": PASSIVE_SELECTION_SHA256,
                "qa_sha256": PASSIVE_QA_SHA256,
            }
        )
    return specs


def _clean_curated_chroma(
    image: Image.Image,
    component_policy: str,
) -> Image.Image:
    """Use sprite-gen's established chroma matte, then keep the selected subject.

    The curation candidates intentionally retain a green review background.
    Keeping only the largest post-matte component also drops isolated generator
    specks without applying any semantic repainting to the approved silhouette.
    """
    try:
        from sprite_gen.frames.extract import (  # type: ignore[import-not-found]
            component_group_image,
            connected_components,
            remove_chroma_background_ycbcr,
        )
    except ImportError as error:
        raise RuntimeError(
            "Curated chroma cleanup requires the sprite-gen virtual environment"
        ) from error
    cleaned = remove_chroma_background_ycbcr(image, (0, 255, 112))
    components = connected_components(cleaned)
    if not components:
        raise ValueError("Chroma cleanup erased the curated subject")
    subject = max(components, key=lambda component: int(component["area"]))
    selected = [subject]
    if component_policy == "significant_group":
        minimum_area = max(24, round(int(subject["area"]) * 0.005))
        selected = [
            component
            for component in components
            if int(component["area"]) >= minimum_area
        ]
    elif component_policy != "largest_subject":
        raise ValueError(f"Unsupported curated component policy: {component_policy}")
    return component_group_image(cleaned, selected, padding=2)


def _normalize(
    source: Path,
    output: Path,
    content_limit: tuple[int, int],
    *,
    chroma_cleanup: bool = False,
    component_policy: str = "largest_subject",
) -> dict[str, Any]:
    with Image.open(source) as loaded:
        image = loaded.convert("RGBA")
    if chroma_cleanup:
        image = _clean_curated_chroma(image, component_policy)
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError(f"Source image has no visible pixels: {source}")
    crop = image.crop(bbox)
    max_width, max_height = content_limit
    scale = min(max_width / crop.width, max_height / crop.height)
    target_width = max(1, min(max_width, round(crop.width * scale)))
    target_height = max(1, min(max_height, round(crop.height * scale)))
    crop = crop.resize((target_width, target_height), Image.Resampling.NEAREST)

    # Hard alpha is the visual contract: every output pixel is a complete
    # logical pixel, never an antialiased fringe from the source render.
    pixels = list(crop.get_flattened_data())
    crop.putdata([(r, g, b, 255 if a >= 128 else 0) for r, g, b, a in pixels])
    cropped_alpha = crop.getchannel("A")
    hard_bbox = cropped_alpha.getbbox()
    if hard_bbox is None:
        raise ValueError(f"Alpha normalization erased the source image: {source}")
    crop = crop.crop(hard_bbox)

    logical = Image.new("RGBA", (LOGICAL_CANVAS, LOGICAL_CANVAS), (0, 0, 0, 0))
    offset_x = (LOGICAL_CANVAS - crop.width) // 2
    offset_y = (LOGICAL_CANVAS - crop.height) // 2
    logical.alpha_composite(crop, (offset_x, offset_y))
    output_image = logical.resize((OUTPUT_CANVAS, OUTPUT_CANVAS), Image.Resampling.NEAREST)
    output.parent.mkdir(parents=True, exist_ok=True)
    output_image.save(output, format="PNG", optimize=False, compress_level=9)
    logical_bbox = logical.getchannel("A").getbbox()
    if logical_bbox is None:
        raise ValueError(f"Normalized image has no visible pixels: {source}")
    return {
        "logical_bbox_xywh": [
            logical_bbox[0],
            logical_bbox[1],
            logical_bbox[2] - logical_bbox[0],
            logical_bbox[3] - logical_bbox[1],
        ],
        "content_limit": [max_width, max_height],
        "chroma_cleanup": f"sprite_gen_ycbcr_{component_policy}"
        if chroma_cleanup
        else "not_required",
    }


def _copy_curated_passive(
    source: Path,
    output: Path,
    expected_sha256: str,
    expected_logical_bbox: list[int],
) -> dict[str, Any]:
    if _sha256(source) != expected_sha256:
        raise ValueError(f"Curated passive input hash changed: {source.name}")
    with Image.open(source) as loaded:
        if loaded.format != "PNG":
            raise ValueError(f"Curated passive must be a PNG: {source.name}")
        image = loaded.convert("RGBA")
    if image.size != (OUTPUT_CANVAS, OUTPUT_CANVAS):
        raise ValueError(f"Curated passive must be 256x256: {source.name}")
    logical = image.resize((LOGICAL_CANVAS, LOGICAL_CANVAS), Image.Resampling.NEAREST)
    roundtrip = logical.resize((OUTPUT_CANVAS, OUTPUT_CANVAS), Image.Resampling.NEAREST)
    if roundtrip.tobytes() != image.tobytes():
        raise ValueError(f"Curated passive is not an exact 4x nearest grid: {source.name}")
    for red, green, blue, alpha in image.get_flattened_data():
        if alpha not in (0, 255):
            raise ValueError(f"Curated passive alpha is not binary: {source.name}")
        if alpha == 0 and (red != 0 or green != 0 or blue != 0):
            raise ValueError(f"Curated passive transparent RGB is not zero: {source.name}")
    bbox = logical.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"Curated passive has no visible pixels: {source.name}")
    actual_bbox = [bbox[0], bbox[1], bbox[2] - bbox[0], bbox[3] - bbox[1]]
    if actual_bbox != [int(value) for value in expected_logical_bbox]:
        raise ValueError(f"Curated passive logical bbox changed: {source.name}")
    if actual_bbox[2] > 50 or actual_bbox[3] > 50:
        raise ValueError(f"Curated passive exceeds the 50x50 content limit: {source.name}")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, output)
    if _sha256(output) != expected_sha256:
        raise ValueError(f"Lossless curated passive copy changed bytes: {source.name}")
    return {
        "mode": "lossless_curated_copy",
        "logical_bbox_xywh": actual_bbox,
        "content_limit": [50, 50],
        "logical_canvas": [LOGICAL_CANVAS, LOGICAL_CANVAS],
        "output_canvas": [OUTPUT_CANVAS, OUTPUT_CANVAS],
        "alpha": "binary",
        "transparent_rgb": "zero",
        "resampler": "nearest",
        "nearest_scale": NEAREST_SCALE,
    }


def _copy_generated_scene(
    source: Path,
    output: Path,
    minimum_canvas: tuple[int, int],
    aspect: str,
) -> dict[str, Any]:
    with Image.open(source) as loaded:
        if loaded.format != "PNG":
            raise ValueError(f"Generated scene source must be a PNG: {source}")
        width, height = loaded.size
        loaded.verify()
    minimum_width, minimum_height = minimum_canvas
    if width < minimum_width or height < minimum_height:
        raise ValueError(
            f"Generated scene source is too small: {width}x{height}, "
            f"minimum {minimum_width}x{minimum_height}"
        )
    ratio = width / height
    if aspect == "widescreen" and not 1.70 <= ratio <= 1.82:
        raise ValueError(f"Generated title background must be widescreen: {width}x{height}")
    if aspect == "square" and width != height:
        raise ValueError(f"Generated arena floor must be square: {width}x{height}")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, output)
    if _sha256(output) != _sha256(source):
        raise ValueError(f"Lossless scene copy changed bytes: {source}")
    return {
        "mode": "lossless_copy",
        "source_canvas": [width, height],
        "output_canvas": [width, height],
        "minimum_canvas": [minimum_width, minimum_height],
        "aspect": aspect,
    }


def _initial_anchors(normalization: dict[str, Any], anchor_kind: str) -> dict[str, Any]:
    x, y, width, height = normalization["logical_bbox_xywh"]
    pivot = [round(x + width * 0.42), round(y + height * 0.68)]
    anchors: dict[str, Any] = {
        "coordinate_space": "logical_64",
        "facing": "screen_right",
        "pivot_logical": pivot,
        "calibration_status": "initial_needs_gameplay_verification",
        "method": "alpha_bbox_heuristic",
        "anchor_kind": anchor_kind,
    }
    if anchor_kind == "throw":
        anchors["throw_origin_logical"] = [round(x + width * 0.5), round(y + height * 0.5)]
    elif anchor_kind == "place":
        anchors["placement_origin_logical"] = [
            round(x + width * 0.5),
            round(y + height * 0.72),
        ]
    elif anchor_kind == "melee":
        anchors["strike_origin_logical"] = [
            round(x + width * 0.78),
            round(y + height * 0.45),
        ]
    else:
        anchors["muzzle_logical"] = [x + width - 1, round(y + height * 0.4)]
    return anchors


def _initial_world_anchors(normalization: dict[str, Any], anchor_kind: str) -> dict[str, Any]:
    x, y, width, height = normalization["logical_bbox_xywh"]
    center = [round(x + width * 0.5), round(y + height * 0.5)]
    anchors: dict[str, Any] = {
        "coordinate_space": "logical_64",
        "pivot_logical": center,
        "ground_origin_logical": [center[0], y + height - 1],
        "anchor_kind": anchor_kind,
        "calibration_status": "initial_needs_gameplay_verification",
        "method": "alpha_bbox_heuristic",
    }
    if anchor_kind == "pickup":
        anchors["collection_origin_logical"] = center
    elif anchor_kind == "prop":
        anchors["interaction_origin_logical"] = center
    elif anchor_kind == "ally_turret":
        anchors["facing"] = "screen_left"
        anchors["muzzle_logical"] = [x, round(y + height * 0.42)]
    elif anchor_kind == "ally_drone":
        anchors["facing"] = "screen_down"
        anchors["muzzle_logical"] = [center[0], round(y + height * 0.68)]
    return anchors


def _initial_projectile_anchors(normalization: dict[str, Any]) -> dict[str, Any]:
    x, y, width, height = normalization["logical_bbox_xywh"]
    center = [round(x + width * 0.5), round(y + height * 0.5)]
    return {
        "coordinate_space": "logical_64",
        "facing": "screen_right",
        "pivot_logical": center,
        "center_logical": center,
        "calibration_status": "initial_needs_gameplay_verification",
        "method": "alpha_bbox_center",
    }


def _project_file_from_res_path(project_root: Path, res_path: str) -> Path | None:
    if not res_path.startswith("res://") or ".." in Path(res_path[6:]).parts:
        return None
    return project_root / res_path[6:]


def install(
    source_root: Path,
    project_root: Path,
    title_background: Path,
    arena_floor: Path,
) -> dict[str, Any]:
    skin_root = project_root / SKIN_RELATIVE_ROOT
    output_asset_root = skin_root / "assets"
    manifest_path = skin_root / "asset_manifest.json"
    curated_passive_specs = _load_curated_passive_specs(project_root)
    managed_ids = {
        str(spec["presentation_id"])
        for spec in (
            *APPROVED_ASSETS,
            *curated_passive_specs,
            *GENERATED_SCENE_ASSETS,
            *CODE_NATIVE_ASSETS,
        )
    }
    preserved_assets: list[dict[str, Any]] = []
    if manifest_path.is_file():
        existing = json.loads(manifest_path.read_text(encoding="utf-8"))
        if existing.get("kind") != "lets-gooooo-static-assets":
            raise ValueError(f"Cannot merge an unrelated manifest: {manifest_path}")
        for raw_entry in existing.get("assets", []):
            source = raw_entry.get("source", {}) if isinstance(raw_entry, dict) else {}
            asset_id = str(raw_entry.get("id", "")) if isinstance(raw_entry, dict) else ""
            if source.get("collection") not in OWNED_COLLECTIONS and asset_id not in managed_ids:
                preserved_assets.append(raw_entry)
    manifest_assets: list[dict[str, Any]] = preserved_assets
    expected_outputs: set[Path] = set()
    for preserved in preserved_assets:
        preserved_file = _project_file_from_res_path(project_root, str(preserved.get("path", "")))
        if preserved_file is not None:
            expected_outputs.add(preserved_file.resolve())

    for spec in APPROVED_ASSETS:
        source_base = project_root if spec["source_scope"] == "project" else source_root
        source = source_base / str(spec["source_rel"])
        if not source.is_file():
            raise FileNotFoundError(f"Approved source PNG is missing: {source}")
        source_sha256 = _sha256(source)
        if source_sha256 != spec["source_sha256"]:
            raise ValueError(
                f"Approved source hash changed for {spec['source_ref']}: "
                f"expected {spec['source_sha256']}, got {source_sha256}"
            )
        output = output_asset_root / str(spec["output_rel"])
        expected_outputs.add(output.resolve())
        normalization = _normalize(
            source,
            output,
            tuple(spec["content_limit"]),
            chroma_cleanup=bool(spec.get("chroma_cleanup", False)),
            component_policy=str(spec.get("component_policy", "largest_subject")),
        )
        source_record: dict[str, Any] = {
            "kind": spec["source_kind"],
            "collection": spec["source_collection"],
            "asset_ref": spec["source_ref"],
            "sha256": source_sha256,
        }
        if spec.get("source_pipeline"):
            source_record["pipeline"] = list(spec["source_pipeline"])
        entry: dict[str, Any] = {
            "id": spec["presentation_id"],
            "presentation_id": spec["presentation_id"],
            "category": spec["category"],
            "path": f"{ASSET_RES_ROOT}/{spec['output_rel']}",
            "sha256": _sha256(output),
            "source": source_record,
            "approval": {
                "status": "approved",
                "basis": spec["approval_basis"],
                "date": "2026-08-18",
            },
            "rights": {
                "status": "cleared",
                "basis": spec["rights_basis"],
                "restrictions": [
                    "no_official_inventory_icons",
                    "no_official_skin_textures",
                    "no_team_or_event_logos",
                ],
            },
            "shipping_allowed": True,
            "uses": spec.get(
                "uses",
                ["weapon.icon", "weapon.world"]
                if spec["category"] == "weapon_icon"
                else ["passive.icon"],
            ),
            "normalization": {
                **normalization,
                "logical_canvas": [LOGICAL_CANVAS, LOGICAL_CANVAS],
                "output_canvas": [OUTPUT_CANVAS, OUTPUT_CANVAS],
                "alpha": "binary",
                "resampler": "nearest",
                "nearest_scale": NEAREST_SCALE,
            },
        }
        if spec["category"] == "weapon_icon":
            entry["anchors"] = _initial_anchors(normalization, str(spec["anchor_kind"]))
        elif spec["category"] in ["pickup_world", "prop_world", "ally_world"]:
            entry["anchors"] = _initial_world_anchors(
                normalization,
                str(spec["anchor_kind"]),
            )
        elif spec["category"] == "projectile_world":
            entry["anchors"] = _initial_projectile_anchors(normalization)
        manifest_assets.append(entry)

    for spec in curated_passive_specs:
        output = output_asset_root / str(spec["output_rel"])
        expected_outputs.add(output.resolve())
        normalization = _copy_curated_passive(
            spec["curated_path"],
            output,
            str(spec["curated_sha256"]),
            list(spec["logical_bbox_xywh"]),
        )
        selected_candidate_sha256 = str(spec["selected_candidate_sha256"])
        manifest_assets.append(
            {
                "id": spec["presentation_id"],
                "presentation_id": spec["presentation_id"],
                "category": "passive_icon",
                "path": f"{ASSET_RES_ROOT}/{spec['output_rel']}",
                "sha256": _sha256(output),
                "source": {
                    "kind": "generated_and_curated_art",
                    "collection": CURATED_PASSIVE_COLLECTION,
                    "asset_ref": spec["source_ref"],
                    "sha256": selected_candidate_sha256,
                    "selected_candidate_sha256": selected_candidate_sha256,
                    "raw_sheet_sha256": spec["raw_sheet_sha256"],
                    "pipeline": ["built_in_image_gen", "sprite_gen_curation"],
                },
                "curation": {
                    "sha256": spec["curated_sha256"],
                    "normalized_input_sha256": spec["normalized_input_sha256"],
                    "selection_sha256": spec["selection_sha256"],
                    "qa_sha256": spec["qa_sha256"],
                    "picked": spec["picked"],
                    "pipeline": [
                        "sprite_gen_sheet_slice",
                        "sprite_gen_pixel_unfake",
                        "sprite_gen_unpack",
                        "sprite_gen_curation",
                        "sprite_gen_export",
                    ],
                },
                "approval": {
                    "status": "approved",
                    "basis": "agent_visual_qa",
                    "date": "2026-08-18",
                },
                "rights": {
                    "status": "cleared",
                    "basis": "generated_for_project",
                    "restrictions": [
                        "no_official_inventory_icons",
                        "no_official_skin_textures",
                        "no_team_or_event_logos",
                    ],
                },
                "shipping_allowed": True,
                "uses": ["passive.icon"],
                "normalization": normalization,
            }
        )

    scene_sources = {
        "title_background": title_background,
        "arena_floor": arena_floor,
    }
    for spec in GENERATED_SCENE_ASSETS:
        source = scene_sources[str(spec["source_arg"])]
        if not source.is_file():
            raise FileNotFoundError(f"Approved generated scene PNG is missing: {source}")
        source_sha256 = _sha256(source)
        if source_sha256 != spec["source_sha256"]:
            raise ValueError(
                f"Approved generated scene hash changed for {spec['source_ref']}: "
                f"expected {spec['source_sha256']}, got {source_sha256}"
            )
        output = output_asset_root / str(spec["output_rel"])
        expected_outputs.add(output.resolve())
        normalization = _copy_generated_scene(
            source,
            output,
            tuple(spec["minimum_canvas"]),
            str(spec["aspect"]),
        )
        scene_entry: dict[str, Any] = {
            "id": spec["presentation_id"],
            "presentation_id": spec["presentation_id"],
            "category": spec["category"],
            "path": f"{ASSET_RES_ROOT}/{spec['output_rel']}",
            "sha256": _sha256(output),
            "source": {
                "kind": "generated_art",
                "collection": GENERATED_SCENE_COLLECTION,
                "asset_ref": spec["source_ref"],
                "sha256": source_sha256,
                "pipeline": ["built_in_image_gen"],
            },
            "approval": {
                "status": "approved",
                "basis": "agent_visual_qa",
                "date": "2026-08-18",
            },
            "rights": {
                "status": "cleared",
                "basis": "generated_for_project",
                "restrictions": [
                    "no_official_map_layouts",
                    "no_official_logos",
                    "no_embedded_wordmarks",
                ],
            },
            "shipping_allowed": True,
            "uses": spec["uses"],
            "normalization": normalization,
        }
        if spec["category"] == "scene_floor":
            scene_entry["sampling"] = "nearest"
        manifest_assets.append(scene_entry)

    for spec in CODE_NATIVE_ASSETS:
        output = output_asset_root / str(spec["output_rel"])
        if not output.is_file():
            raise FileNotFoundError(f"Approved code-native vector is missing: {output}")
        output_sha256 = _sha256(output)
        if output_sha256 != spec["sha256"]:
            raise ValueError(
                f"Approved code-native vector changed for {spec['asset_ref']}: "
                f"expected {spec['sha256']}, got {output_sha256}"
            )
        expected_outputs.add(output.resolve())
        manifest_assets.append(
            {
                "id": spec["presentation_id"],
                "presentation_id": spec["presentation_id"],
                "category": spec["category"],
                "path": f"{ASSET_RES_ROOT}/{spec['output_rel']}",
                "sha256": output_sha256,
                "source": {
                    "kind": "original_code_native_vector",
                    "collection": CODE_NATIVE_COLLECTION,
                    "asset_ref": spec["asset_ref"],
                    "sha256": output_sha256,
                },
                "approval": {
                    "status": "approved",
                    "basis": "repository_authored_original_vector",
                    "date": "2026-08-18",
                },
                "rights": {
                    "status": "cleared",
                    "basis": "original_project_authorship",
                    "restrictions": ["no_external_embedded_payloads"],
                },
                "shipping_allowed": True,
                "uses": [spec["use"]],
                "format": "svg",
            }
        )

    # The output folders are owned by this importer. Refuse stale PNGs because
    # an unlisted image would bypass approval and provenance.
    if output_asset_root.exists():
        stale = sorted(
            path
            for path in output_asset_root.rglob("*.png")
            if path.resolve() not in expected_outputs
        )
        if stale:
            raise ValueError(
                "Unapproved/stale PNGs are present in the shipping asset root: "
                + ", ".join(str(path) for path in stale)
            )

    manifest = {
        "schema_version": 1,
        "kind": "lets-gooooo-static-assets",
        "skin_id": "lets_gooooo",
        "logical_canvas": LOGICAL_CANVAS,
        "output_canvas": OUTPUT_CANVAS,
        "nearest_scale": NEAREST_SCALE,
        "generated_by": "tools/assets/normalize_static_skin_assets.py",
        "source_collection": {
            "kind": "mixed_approved_generated_art",
            "provenance_policy": "source paths stay in the non-shipping import tool",
        },
        "assets": sorted(manifest_assets, key=lambda entry: str(entry["id"])),
    }
    skin_root.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--title-background", type=Path, required=True)
    parser.add_argument("--arena-floor", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    manifest = install(
        args.source_root.resolve(),
        args.project_root.resolve(),
        args.title_background.resolve(),
        args.arena_floor.resolve(),
    )
    print(
        f"STATIC_SKIN_ASSET_IMPORT passed: assets={len(manifest['assets'])} "
        f"skin={manifest['skin_id']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
