from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OLD_WAVE033_APPROVAL_SHA256 = (
    "55650881C916C9D886ED4B47CDEAA187487E4B4F3BE84A3D90B09105BE461786"
)
OLD_WAVE033_REVIEW_SHA256 = (
    "4E6770DF75EFB3A31126E62368C4F0E0B3A045F4647385580612B437B1AC82C9"
)


def _resource_path(value: str) -> Path:
    return PROJECT_ROOT / value.removeprefix("res://")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


class StaticShippingBuilderTest(unittest.TestCase):
    def test_shipping_builder_dry_run_reports_exact_release_union(self) -> None:
        result = subprocess.run(
            [sys.executable, "tools/build_static_shipping_install.py"],
            cwd=PROJECT_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("70 active / 0 inactive", result.stdout)
        self.assertIn("pending=0", result.stdout)
        approval = json.loads(
            (
                PROJECT_ROOT
                / "game/content/assets/gogobro_static_shipping_approval_2026-08-28.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(approval["accepted_candidate_unit_count"], 65)
        self.assertEqual(approval["shipping_only_unit_count"], 5)
        self.assertEqual(approval["approved_unit_count"], 70)
        self.assertEqual(
            sorted(approval["overlap_replacements"]),
            [
                "ballistic_liner",
                "service_pistol",
                "smoke_shell_helmet",
                "warmup_shiv",
            ],
        )
        self.assertEqual(len(approval["units"]), 70)
        self.assertNotEqual(approval["review_board_sha256"], OLD_WAVE033_REVIEW_SHA256)

        candidate = json.loads(
            _resource_path(
                "res://game/content/assets/gogobro_static_candidate_preview_v1.json"
            ).read_text(encoding="utf-8")
        )
        manifest = json.loads(
            _resource_path(
                "res://game/content/assets/gogobro_static_runtime_bindings_v1.json"
            ).read_text(encoding="utf-8")
        )
        registry = json.loads(
            _resource_path(
                "res://game/content/assets/gogobro_static_assets_v1.json"
            ).read_text(encoding="utf-8")
        )
        candidate_by_id = {unit["asset_id"]: unit for unit in candidate["units"]}
        approval_by_id = {unit["asset_id"]: unit for unit in approval["units"]}
        manifest_by_id = {unit["asset_id"]: unit for unit in manifest["units"]}
        registry_by_id = {unit["asset_id"]: unit for unit in registry["units"]}

        self.assertEqual(len(candidate_by_id), 65)
        self.assertEqual(len(approval_by_id), 70)
        self.assertEqual(len(manifest_by_id), 70)
        self.assertEqual(len(registry_by_id), 70)
        self.assertEqual(set(approval_by_id), set(manifest_by_id))
        self.assertEqual(set(approval_by_id), set(registry_by_id))
        self.assertEqual(set(approval_by_id) - set(candidate_by_id), {
            "control_icon_kit",
            "difficulty_badge_kit",
            "hud_icon_kit",
            "one_more_round",
            "projectile_hit_kit",
        })

        approval_record_sha256 = _sha256(
            _resource_path(
                "res://game/content/assets/gogobro_static_shipping_approval_2026-08-28.json"
            )
        )
        self.assertNotEqual(approval_record_sha256, OLD_WAVE033_APPROVAL_SHA256)
        for asset_id, candidate_unit in candidate_by_id.items():
            preview_path = _resource_path(candidate_unit["resource_path"])
            self.assertEqual(_sha256(preview_path), candidate_unit["sha256"], asset_id)
            approved_unit = approval_by_id[asset_id]
            self.assertEqual(approved_unit["source_kind"], "accepted_candidate_preview")
            self.assertEqual(
                approved_unit["accepted_sources"][0]["sha256"],
                candidate_unit["sha256"],
                asset_id,
            )

        for asset_id in approval["overlap_replacements"]:
            shipping = approval_by_id[asset_id]["shipping_texture"]
            self.assertEqual(shipping["sha256"], candidate_by_id[asset_id]["sha256"])
            self.assertEqual(_sha256(_resource_path(shipping["resource_path"])), shipping["sha256"])

        for asset_id, manifest_unit in manifest_by_id.items():
            registry_unit = registry_by_id[asset_id]
            approved_unit = approval_by_id[asset_id]
            self.assertEqual(manifest_unit["declared_runtime_state"], "requested_active")
            self.assertEqual(manifest_unit["approval_status"], "approved")
            self.assertEqual(registry_unit["approval_status"], "approved")
            self.assertEqual(
                registry_unit["shipping_approval_evidence"]["approval_record_sha256"],
                approval_record_sha256,
            )
            self.assertNotEqual(
                registry_unit["shipping_approval_evidence"]["review_board_sha256"],
                OLD_WAVE033_REVIEW_SHA256,
            )
            self.assertEqual(manifest_unit["shipping"], {
                **approved_unit["shipping_texture"],
                "texture_filter": "nearest",
                "mipmaps": False,
            })
            self.assertEqual(manifest_unit["bindings"], approved_unit["runtime_bindings"])


if __name__ == "__main__":
    unittest.main()
