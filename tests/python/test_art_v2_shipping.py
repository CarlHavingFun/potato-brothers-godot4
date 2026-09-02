from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import unittest
from io import BytesIO
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[2]
APPROVAL_PATH = (
    PROJECT_ROOT
    / "game/content/assets/approvals/gogobro_art_v2_shipping_approval_2026-09-02.json"
)
APPROVAL_SHA256 = "4AFA9324F76E86F24B32E2DF96BBB6C93913407F1C23F0339DEDA8B979F283F0"
AUTHORITY = "user_authorized_supervisor_ordinary_visual_judgment"
EXPECTED = {
    "community_server_floor": {
        "raw": "res://game/assets/gogobro_static/world/community_server_floor_training_ground_v2_1448x1086.png",
        "raw_sha256": "FA7EF4C76185BC321F182D0838701AB4BB171E72CD936A3CC45296A62F3C70AA",
        "raw_size": (1448, 1086),
        "shipping": "res://game/assets/gogobro_static/world/community_server_floor_training_ground_v2_2048x1536_rgba8.png",
        "shipping_sha256": "AFD075592C1C7E6EC5423E2C63E09454C7222F4DAD23FFAD841B3F96708A0EEC",
        "rgba8_sha256": "C7641010C8FF6CD45C703C605FF734E6AF49F65937B3E6794BB9BF9ABB427917",
        "size": (2048, 1536),
        "role": "world_sprite",
        "source_contract_sha256": "243912DAC8D47EDCFA9800E88CF67552592674F8D0AE5E8A879BF87BE5DC7436",
        "review_sha256": "BE3AF83D035DC147F98162CD4DD43A7D8EE16542E3E0839C0873FF9C768F38F9",
    },
    "zone_thumbnail": {
        "raw": "res://game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_1672x941.png",
        "raw_sha256": "47FA7559B0774D5E514D9149464B1BC76BBE9DC33058FB4B2959A1620CEC00F8",
        "raw_size": (1672, 941),
        "shipping": "res://game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_256x144_rgba8.png",
        "shipping_sha256": "FB341F882F46D9EAD7C3D1601814481B9F4A090156B4DEFD5726569A98746584",
        "rgba8_sha256": "86A91AAB941868EB6EEF590D819FFD80199EB8174391FA1A7CBC721D198B3A7F",
        "size": (256, 144),
        "role": "ui_texture",
        "source_contract_sha256": "B24FE0218E596FF5BF8469778A4819FC7DAABD6BBC3311046DBA9F69B8D5931E",
        "review_sha256": "39ADF16532A41E71FC1F95BA5835AD54ED4E43FA6B7D23FE673116F7914EA3B1",
    },
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _resource_path(value: str) -> Path:
    return PROJECT_ROOT / value.removeprefix("res://")


def _load_builder():
    path = PROJECT_ROOT / "tools/build_static_shipping_install.py"
    spec = importlib.util.spec_from_file_location("build_static_shipping_install", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load static shipping builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ArtV2ShippingContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.builder = _load_builder()
        cls.approval = json.loads(APPROVAL_PATH.read_text(encoding="utf-8"))

    def test_exact_two_asset_authority_and_provenance_scope(self) -> None:
        self.assertEqual(_sha256(APPROVAL_PATH), APPROVAL_SHA256)
        self.assertEqual(self.approval["authority"], AUTHORITY)
        self.assertFalse(self.approval["per_image_explicit_user_approval"])
        self.builder._validate_art_v2_approval_scope(self.approval)

        delegation = self.approval["delegation_basis"]
        self.assertEqual(set(delegation["logical_asset_ids"]), set(EXPECTED))
        self.assertEqual(
            set(delegation["versioned_shipping_paths"]),
            {contract["shipping"] for contract in EXPECTED.values()},
        )
        self.assertEqual(
            set(delegation["raw_provenance_paths"]),
            {contract["raw"] for contract in EXPECTED.values()},
        )
        self.assertIn("not per-image explicit approval", delegation["statement"])

        units = {unit["asset_id"]: unit for unit in self.approval["units"]}
        self.assertEqual(set(units), set(EXPECTED))
        for asset_id, contract in EXPECTED.items():
            unit = units[asset_id]
            self.assertEqual(unit["authority"], AUTHORITY)
            self.assertFalse(unit["per_image_explicit_user_approval"])
            self.assertEqual(unit["binding_key"], f"{asset_id}|{contract['role']}|")
            self.assertEqual(unit["source"]["raw_resource_path"], contract["raw"])
            self.assertEqual(unit["source"]["sha256"], contract["raw_sha256"])
            self.assertEqual(tuple(unit["source"]["pixel_size"]), contract["raw_size"])
            self.assertEqual(unit["shipping_texture"]["resource_path"], contract["shipping"])
            self.assertEqual(unit["processing"], {
                "tool": "Pillow",
                "version": "12.2.0",
                "algorithm": "Image.Resampling.LANCZOS",
                "color_mode": "RGBA8",
                "crop": "none",
                "png_optimize": False,
                "png_compress_level": 9,
                "double_encode_identical": True,
            })

    def test_raw_derived_and_document_hash_chain_is_exact(self) -> None:
        units = {unit["asset_id"]: unit for unit in self.approval["units"]}
        for asset_id, contract in EXPECTED.items():
            unit = units[asset_id]
            raw_path = _resource_path(contract["raw"])
            shipping_path = _resource_path(contract["shipping"])
            self.assertEqual(_sha256(raw_path), contract["raw_sha256"])
            self.assertEqual(_sha256(shipping_path), contract["shipping_sha256"])
            with Image.open(raw_path) as raw:
                self.assertEqual(raw.size, contract["raw_size"])
                derived = raw.convert("RGBA").resize(
                    contract["size"],
                    resample=Image.Resampling.LANCZOS,
                )
            encodings = []
            for _ in range(2):
                output = BytesIO()
                derived.save(output, format="PNG", optimize=False, compress_level=9)
                encodings.append(output.getvalue())
            derived.close()
            self.assertEqual(encodings[0], encodings[1])
            self.assertEqual(encodings[0], shipping_path.read_bytes())
            with Image.open(shipping_path) as shipping:
                self.assertEqual(shipping.format, "PNG")
                self.assertEqual(shipping.mode, "RGBA")
                self.assertEqual(shipping.size, contract["size"])
                rgba8_sha256 = hashlib.sha256(shipping.tobytes()).hexdigest().upper()
            self.assertEqual(rgba8_sha256, contract["rgba8_sha256"])
            self.assertEqual(unit["shipping_texture"]["output_sha256"], contract["shipping_sha256"])
            self.assertEqual(unit["shipping_texture"]["rgba8_sha256"], contract["rgba8_sha256"])
            self.assertEqual(unit["shipping_texture"]["display_scale"], [1.0, 1.0])
            self.assertTrue(all(isinstance(value, float) for value in unit["shipping_texture"]["display_scale"]))
            for field, expected_sha256 in [
                ("source_contract", contract["source_contract_sha256"]),
                ("visual_review", contract["review_sha256"]),
            ]:
                self.assertEqual(unit[field]["sha256"], expected_sha256)
                self.assertEqual(_sha256(_resource_path(unit[field]["path"])), expected_sha256)
            self.assertEqual(_sha256(_resource_path(unit["prompt"]["path"])), unit["prompt"]["sha256"])

    def test_catalog_and_runtime_manifest_use_exact_derived_1to1_bindings(self) -> None:
        registry_path = PROJECT_ROOT / "game/content/assets/gogobro_static_assets_v1.json"
        manifest_path = (
            PROJECT_ROOT / "game/content/assets/gogobro_static_runtime_bindings_v1.json"
        )
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(len(registry["units"]), 70)
        self.assertEqual(len(manifest["units"]), 70)
        self.assertEqual(manifest["canonical_registry_sha256"], _sha256(registry_path))
        registry_units = {unit["asset_id"]: unit for unit in registry["units"]}
        manifest_units = {unit["asset_id"]: unit for unit in manifest["units"]}
        for asset_id, contract in EXPECTED.items():
            unit = registry_units[asset_id]
            runtime = manifest_units[asset_id]
            width, height = contract["size"]
            expected_binding = {
                "binding_key": f"{asset_id}|{contract['role']}|",
                "role": contract["role"],
                "selector": "",
                "display_size_px": [width, height],
                "display_scale": [1.0, 1.0],
                "pivot_px": [width // 2, height // 2],
                "atlas_rect_px": [0, 0, width, height],
                "anchors_px": {},
                "consumers": [{"kind": "global", "role": asset_id, "selector": ""}],
            }
            self.assertEqual(unit["intended_file_paths"], [contract["shipping"]])
            self.assertEqual(unit["hashes"], {
                "sha256": contract["shipping_sha256"],
                "rgba8_sha256": contract["rgba8_sha256"],
            })
            self.assertEqual(unit["output_spec"], {
                "type": "png",
                "width": width,
                "height": height,
                "alpha": True,
            })
            self.assertEqual(unit["runtime_bindings"], [expected_binding])
            self.assertEqual(
                unit["shipping_approval_evidence"]["approval_record_sha256"],
                APPROVAL_SHA256,
            )
            self.assertEqual(runtime["bindings"], [expected_binding])
            self.assertEqual(runtime["shipping"], {
                "resource_path": contract["shipping"],
                "sha256": contract["shipping_sha256"],
                "rgba8_sha256": contract["rgba8_sha256"],
                "pixel_size": [width, height],
                "texture_filter": "nearest",
                "mipmaps": False,
            })

    def test_unknown_or_expanded_authority_scope_is_rejected(self) -> None:
        mutations = []
        unknown_authority = copy.deepcopy(self.approval)
        unknown_authority["authority"] = "assistant_self_approval"
        mutations.append(unknown_authority)
        per_image_claim = copy.deepcopy(self.approval)
        per_image_claim["per_image_explicit_user_approval"] = True
        mutations.append(per_image_claim)
        extra_path = copy.deepcopy(self.approval)
        extra_path["delegation_basis"]["versioned_shipping_paths"].append(
            "res://game/assets/gogobro_static/ui/unapproved.png"
        )
        mutations.append(extra_path)
        duplicate_id = copy.deepcopy(self.approval)
        duplicate_id["delegation_basis"]["logical_asset_ids"] = [
            "community_server_floor",
            "community_server_floor",
        ]
        mutations.append(duplicate_id)
        unit_authority = copy.deepcopy(self.approval)
        unit_authority["units"][0]["authority"] = "explicit_user_approval_in_current_task"
        mutations.append(unit_authority)
        wrong_binding = copy.deepcopy(self.approval)
        wrong_binding["units"][0]["binding_key"] = "community_server_floor|world_sprite|extra"
        mutations.append(wrong_binding)
        widened_scope = copy.deepcopy(self.approval)
        widened_scope["units"][0]["scope"]["ordinary_run_props"] = 1
        mutations.append(widened_scope)

        for mutated in mutations:
            with self.subTest(mutated=mutated):
                with self.assertRaises(RuntimeError):
                    self.builder._validate_art_v2_approval_scope(mutated)

    def test_output_path_guards_reject_traversal_collisions_and_aliases(self) -> None:
        rejected_paths = [
            (
                "res://game/assets/gogobro_static/../gogobro_static/world/"
                "community_server_floor_training_ground_v2_2048x1536_rgba8.png"
            ),
            "res://game//assets/gogobro_static/world/arena.png",
            "res://game/./assets/gogobro_static/world/arena.png",
            "res://game/assets/gogobro_static/world/arena.png:stream",
            "res://game/assets/gogobro_static/world/CON.png",
            "res://game/assets/gogobro_static/world/arena.png.",
            "res://game/assets/gogobro_static/world/arena.png ",
            "res://game/assets/gogobro_static/world",
        ]
        for rejected in rejected_paths:
            with self.subTest(rejected=rejected):
                with self.assertRaises(RuntimeError):
                    self.builder._project_resource_target(
                        PROJECT_ROOT,
                        rejected,
                        "res://game/assets/gogobro_static/",
                    )

        protected = _resource_path(EXPECTED["community_server_floor"]["shipping"])
        with self.assertRaises(RuntimeError):
            self.builder._assert_no_protected_art_v2_overwrites(
                PROJECT_ROOT,
                {protected: b"forbidden"},
            )

        for contract in self.builder.SUPERSEDED_LEGACY_MEDIA.values():
            superseded = _resource_path(contract["resource_path"])
            with self.subTest(superseded=superseded):
                self.assertEqual(_sha256(superseded), contract["sha256"])
                with self.assertRaises(RuntimeError):
                    self.builder._assert_no_protected_art_v2_overwrites(
                        PROJECT_ROOT,
                        {superseded: b"forbidden"},
                    )

        desired: dict[Path, bytes] = {}
        self.builder._record_desired_media(desired, protected, b"first", "first")
        with self.assertRaises(RuntimeError):
            self.builder._record_desired_media(desired, protected, b"second", "second")


if __name__ == "__main__":
    unittest.main()
