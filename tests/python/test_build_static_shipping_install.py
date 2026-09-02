from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
OLD_WAVE033_APPROVAL_SHA256 = (
    "55650881C916C9D886ED4B47CDEAA187487E4B4F3BE84A3D90B09105BE461786"
)
OLD_WAVE033_REVIEW_SHA256 = (
    "4E6770DF75EFB3A31126E62368C4F0E0B3A045F4647385580612B437B1AC82C9"
)
LEGACY_APPROVAL_SHA256 = "D52BDE81CB2C192F53A02CFFBC7D300EBBC0900ED00256F4E4D637824112C27A"
ART_V2_APPROVAL_PATH = (
    "res://game/content/assets/approvals/"
    "gogobro_art_v2_shipping_approval_2026-09-02.json"
)
ART_V2_APPROVAL_SHA256 = "02E50A9FB29227B8FA1640A3C98738CA93FBABED7B57330BA6F0096AA05FB348"
ART_V2_AUTHORITY = "user_authorized_supervisor_ordinary_visual_judgment"
ART_V2_IDS = {"community_server_floor", "zone_thumbnail"}


def _resource_path(value: str) -> Path:
    return PROJECT_ROOT / value.removeprefix("res://")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def _load_builder():
    path = PROJECT_ROOT / "tools/build_static_shipping_install.py"
    spec = importlib.util.spec_from_file_location("build_static_shipping_install", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load static shipping builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StaticShippingBuilderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.builder = _load_builder()

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
        art_v2_approval = json.loads(
            _resource_path(ART_V2_APPROVAL_PATH).read_text(encoding="utf-8")
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
        art_v2_approval_by_id = {
            unit["asset_id"]: unit for unit in art_v2_approval["units"]
        }
        manifest_by_id = {unit["asset_id"]: unit for unit in manifest["units"]}
        registry_by_id = {unit["asset_id"]: unit for unit in registry["units"]}

        self.assertEqual(len(candidate_by_id), 65)
        self.assertEqual(len(approval_by_id), 70)
        self.assertEqual(len(manifest_by_id), 70)
        self.assertEqual(len(registry_by_id), 70)
        self.assertEqual(set(approval_by_id), set(manifest_by_id))
        self.assertEqual(set(approval_by_id), set(registry_by_id))
        self.assertEqual(set(art_v2_approval_by_id), ART_V2_IDS)
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
        self.assertEqual(approval_record_sha256, LEGACY_APPROVAL_SHA256)
        self.assertEqual(_sha256(_resource_path(ART_V2_APPROVAL_PATH)), ART_V2_APPROVAL_SHA256)
        for asset_id, candidate_unit in candidate_by_id.items():
            preview_path = _resource_path(candidate_unit["resource_path"])
            self.assertEqual(_sha256(preview_path), candidate_unit["sha256"], asset_id)
            if asset_id in ART_V2_IDS:
                continue
            approved_unit = approval_by_id[asset_id]
            self.assertEqual(approved_unit["source_kind"], "accepted_candidate_preview")
            artifacts = [candidate_unit, *candidate_unit.get("variants", [])]
            accepted_sources = approved_unit["accepted_sources"]
            self.assertEqual(len(accepted_sources), len(artifacts), asset_id)
            for artifact, accepted_source in zip(artifacts, accepted_sources):
                expected_selector = artifact.get("selector", "")
                self.assertEqual(accepted_source["selector"], expected_selector, asset_id)
                self.assertEqual(
                    accepted_source["preview_resource_path"],
                    artifact["resource_path"],
                    asset_id,
                )
                self.assertEqual(
                    accepted_source["source_candidate_path"],
                    artifact["source_candidate_path"],
                    asset_id,
                )
                for field in [
                    "sha256",
                    "pixel_size",
                    "display_size_px",
                    "pivot_px",
                    "anchors_px",
                ]:
                    self.assertEqual(accepted_source[field], artifact[field], f"{asset_id}:{field}")
            self.assertEqual(
                [record["selector"] for record in approved_unit["selector_pixels"]],
                [artifact.get("selector", "") for artifact in artifacts],
                asset_id,
            )

        for asset_id in approval["overlap_replacements"]:
            shipping = approval_by_id[asset_id]["shipping_texture"]
            self.assertEqual(shipping["sha256"], candidate_by_id[asset_id]["sha256"])
            self.assertEqual(_sha256(_resource_path(shipping["resource_path"])), shipping["sha256"])

        for asset_id, manifest_unit in manifest_by_id.items():
            registry_unit = registry_by_id[asset_id]
            self.assertEqual(manifest_unit["declared_runtime_state"], "requested_active")
            self.assertEqual(manifest_unit["approval_status"], "approved")
            self.assertEqual(registry_unit["approval_status"], "approved")
            evidence = registry_unit["shipping_approval_evidence"]
            if asset_id in ART_V2_IDS:
                approved_unit = art_v2_approval_by_id[asset_id]
                art_shipping = approved_unit["shipping_texture"]
                self.assertEqual(evidence["authority"], ART_V2_AUTHORITY)
                self.assertEqual(evidence["approval_record_sha256"], ART_V2_APPROVAL_SHA256)
                self.assertFalse(approved_unit["per_image_explicit_user_approval"])
                self.assertEqual(manifest_unit["shipping"], {
                    "resource_path": art_shipping["resource_path"],
                    "sha256": art_shipping["output_sha256"],
                    "rgba8_sha256": art_shipping["rgba8_sha256"],
                    "pixel_size": art_shipping["pixel_size"],
                    "texture_filter": "nearest",
                    "mipmaps": False,
                })
                self.assertEqual(manifest_unit["bindings"], registry_unit["runtime_bindings"])
            else:
                approved_unit = approval_by_id[asset_id]
                self.assertEqual(evidence["authority"], "explicit_user_approval_in_current_task")
                self.assertEqual(evidence["approval_record_sha256"], approval_record_sha256)
                self.assertNotEqual(
                    evidence["review_board_sha256"],
                    OLD_WAVE033_REVIEW_SHA256,
                )
                self.assertEqual(manifest_unit["shipping"], {
                    **approved_unit["shipping_texture"],
                    "texture_filter": "nearest",
                    "mipmaps": False,
                })
                self.assertEqual(manifest_unit["bindings"], approved_unit["runtime_bindings"])

        delegated_ids = {
            asset_id
            for asset_id, unit in registry_by_id.items()
            if unit["shipping_approval_evidence"]["authority"] == ART_V2_AUTHORITY
        }
        self.assertEqual(delegated_ids, ART_V2_IDS)

    def test_all_legacy_media_is_immutable_and_excluded_from_write_plan(self) -> None:
        registry = self.builder._production_scope(json.loads(
            (PROJECT_ROOT / "game/content/assets/gogobro_static_assets_v1.json").read_text(
                encoding="utf-8"
            )
        ))
        registry_units = {unit["asset_id"]: unit for unit in registry["units"]}
        workspace = (
            PROJECT_ROOT.parents[1]
            if PROJECT_ROOT.parent.name == ".worktrees"
            else PROJECT_ROOT.parent
        )
        candidate_specs, expected_candidate_media = self.builder._candidate_specs(
            workspace,
            PROJECT_ROOT,
            registry_units,
            self.builder.ART_V2_OVERRIDE_IDS,
        )
        shipping_only_specs = self.builder._shipping_only_specs(workspace, PROJECT_ROOT)
        superseded_media = self.builder._validated_superseded_legacy_media(PROJECT_ROOT)
        self.builder._assert_immutable_media(
            expected_candidate_media,
            "test legacy candidate media",
        )

        self.assertEqual(len(candidate_specs), 63)
        self.assertEqual(len(expected_candidate_media), 80)
        self.assertEqual(len(shipping_only_specs), 5)
        self.assertEqual(len(superseded_media), 2)
        legacy_specs = {**shipping_only_specs, **candidate_specs}
        legacy_primary_paths = {
            self.builder._project_resource_target(PROJECT_ROOT, spec["resource_path"])
            for spec in legacy_specs.values()
        }
        self.assertEqual(len(legacy_primary_paths), 68)
        immutable_paths = {
            *expected_candidate_media,
            *legacy_primary_paths,
            *superseded_media,
        }
        protected = self.builder._protected_media_paths(PROJECT_ROOT, immutable_paths)
        exact_required = legacy_primary_paths | set(superseded_media)
        self.assertEqual(len(exact_required), 70)
        for path in exact_required:
            with self.subTest(protected=path):
                self.assertIn(path.resolve(strict=False), protected)
        for path in expected_candidate_media:
            with self.subTest(candidate_output=path):
                self.assertIn(path.resolve(strict=False), protected)

        write_plan = self.builder._metadata_write_plan(
            PROJECT_ROOT,
            "registry\n",
            "manifest\n",
            immutable_paths,
        )
        self.assertEqual(set(write_plan), {
            PROJECT_ROOT / "game/content/assets/gogobro_static_assets_v1.json",
            PROJECT_ROOT / "game/content/assets/gogobro_static_runtime_bindings_v1.json",
        })
        self.assertTrue(exact_required.isdisjoint(write_plan))
        self.assertTrue(set(expected_candidate_media).isdisjoint(write_plan))

        # Exercise fail-on-drift for each of the exact 68 legacy primary targets
        # plus the two superseded v1 paths without mutating repository evidence.
        with tempfile.TemporaryDirectory() as temporary:
            mirror: dict[Path, bytes] = {}
            for index, _path in enumerate(sorted(exact_required)):
                target = Path(temporary) / f"legacy-{index:02d}.png"
                content = f"immutable-{index}".encode("ascii")
                target.write_bytes(content)
                mirror[target] = content
            self.builder._assert_immutable_media(mirror, "test mirror")
            for target, content in mirror.items():
                with self.subTest(drift=target.name):
                    target.write_bytes(content + b"-drift")
                    with self.assertRaises(RuntimeError):
                        self.builder._assert_immutable_media(mirror, "test mirror")
                    target.write_bytes(content)


if __name__ == "__main__":
    unittest.main()
