from __future__ import annotations

import copy
import contextlib
import hashlib
import io
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_ROOT = Path(__file__).parents[1]
SCRIPTS = SKILL_ROOT / "scripts"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


TRUST = _load("test_trusted_character_bindings", SCRIPTS / "trusted_character_bindings.py")
RIG_CHECKER = _load("test_character_socket_rig", SCRIPTS / "check_character_socket_rig.py")
STALE = _load("test_stale_socket_geometry", SCRIPTS / "check_stale_socket_geometry.py")


class TrustedFpsTests(unittest.TestCase):
    def test_current_niko_binding_is_exactly_eight_fps(self) -> None:
        catalog = TRUST.load_trusted_bindings()
        animation = catalog["characters"]["character.niko:character/niko"]["animations"][
            "walk_down"
        ]
        self.assertEqual(animation["fps"], 8)

    def test_fps_is_required_and_must_be_positive_finite_number(self) -> None:
        valid = TRUST.load_trusted_bindings()
        animation = valid["characters"]["character.niko:character/niko"]["animations"][
            "walk_down"
        ]
        invalid_values = (True, "8", 0, -1, float("inf"), float("nan"))
        for invalid in invalid_values:
            with self.subTest(invalid=invalid):
                payload = copy.deepcopy(valid)
                payload["characters"]["character.niko:character/niko"]["animations"][
                    "walk_down"
                ]["fps"] = invalid
                with self.assertRaises(TRUST.TrustedBindingsError):
                    TRUST._validate_catalog(payload)
        missing = copy.deepcopy(valid)
        del missing["characters"]["character.niko:character/niko"]["animations"][
            "walk_down"
        ]["fps"]
        with self.assertRaises(TRUST.TrustedBindingsError):
            TRUST._validate_catalog(missing)
        huge = copy.deepcopy(valid)
        huge["characters"]["character.niko:character/niko"]["animations"][
            "walk_down"
        ]["fps"] = 10**10000
        TRUST._validate_catalog(huge)
        self.assertEqual(animation["fps"], 8)

    def test_one_rig_group_cannot_bind_conflicting_source_profiles(self) -> None:
        payload = copy.deepcopy(TRUST.load_trusted_bindings())
        animations = payload["characters"]["character.niko:character/niko"][
            "animations"
        ]
        first = animations["walk_down"]
        first["atlas"]["atlas_size"] = [1024, 256]
        first["atlas"]["grid"]["rows"] = 2
        second = copy.deepcopy(first)
        second["atlas"]["grid"]["row"] = 1
        second["source_profile"]["relative_path"] = "tools/profiles/other.json"
        second["source_profile"]["sha256"] = "a" * 64
        animations["walk_alt"] = second
        with self.assertRaises(TRUST.TrustedBindingsError):
            TRUST._validate_catalog(payload)


class SourceProfileAlignmentTests(unittest.TestCase):
    def _fixture(self, root: Path):
        atlas_path = root / "atlas.bin"
        atlas_path.write_bytes(b"profile-bound-atlas")
        atlas_hash = hashlib.sha256(atlas_path.read_bytes()).hexdigest()
        profile = {
            "schema_version": "gogobro-rig-profile-v1",
            "character_atlas_sha256": atlas_hash.upper(),
            "frame_size": [4, 4],
            "atlas_size": [8, 4],
            "frames": [],
        }
        rig_frames = []
        for frame_index in range(2):
            left = frame_index
            profile["frames"].append(
                {
                    "frame_index": frame_index,
                    "attachment_regions": {"side_left": [left, 0, left + 1, 1]},
                    "face_roi": [1, 1, 3, 3],
                    "protected_regions": {"eyes": [1, 1, 2, 2]},
                }
            )
            rig_frames.append(
                {
                    "frame_index": frame_index,
                    "frame_name": f"walk_down_{frame_index + 1:02d}",
                    "regions": {
                        "hip_left": [left, 0, left + 1, 1],
                        "face": [1, 1, 3, 3],
                    },
                    "protected_regions": {"eyes": [1, 1, 2, 2]},
                    "sockets": {},
                }
            )
        profile_path = root / "tools" / "profiles" / "walk.json"
        profile_path.parent.mkdir(parents=True)
        profile_path.write_text(json.dumps(profile), encoding="utf-8")
        rig_path = root / "game" / "rig.json"
        rig_path.parent.mkdir(parents=True)
        rig = {
            "source_profile": "tools/profiles/walk.json",
            "animations": {
                "walk_down": {
                    "frame_count": 2,
                    "fps": 8,
                    "row": 0,
                    "frames": rig_frames,
                }
            },
        }
        rig_path.write_text(json.dumps(rig), encoding="utf-8")
        binding = {
            "frame_count": 2,
            "fps": 8,
            "source_profile": {
                "relative_path": "tools/profiles/walk.json",
                "schema_version": "gogobro-rig-profile-v1",
                "sha256": hashlib.sha256(profile_path.read_bytes()).hexdigest(),
            },
            "atlas": {
                "sha256": atlas_hash,
                "frame_size": [4, 4],
                "atlas_size": [8, 4],
                "grid": {"columns": 2, "rows": 1, "row": 0},
            },
        }
        return rig_path, rig, atlas_path, binding

    def _gate(self, rig_path, rig, atlas_path, binding):
        issues = {}
        reasons = set()
        summary = RIG_CHECKER._source_profile_gate(
            rig_path=rig_path,
            rig=rig,
            atlas_path=atlas_path,
            animation_id="walk_down",
            binding=binding,
            issues=issues,
            reasons=reasons,
        )
        return summary, reasons

    def test_regions_and_protected_regions_align_per_frame(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = self._fixture(Path(temporary))
            summary, reasons = self._gate(*fixture)
            self.assertEqual(summary["verdict"], "rig_pass")
            self.assertEqual(reasons, set())
            self.assertEqual(summary["aligned_region_count"], 4)
            self.assertEqual(summary["aligned_protected_region_count"], 2)

    def test_stale_region_or_protected_box_hard_fails_alignment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            rig_path, rig, atlas_path, binding = self._fixture(Path(temporary))
            stale = copy.deepcopy(rig)
            stale["animations"]["walk_down"]["frames"][1]["regions"]["hip_left"] = [
                0,
                0,
                1,
                1,
            ]
            stale["animations"]["walk_down"]["frames"][0]["protected_regions"][
                "eyes"
            ] = [0, 0, 1, 1]
            summary, reasons = self._gate(rig_path, stale, atlas_path, binding)
            self.assertEqual(summary["verdict"], "hard_fail")
            self.assertIn("source_profile_region_mismatch", reasons)
            self.assertIn("source_profile_protected_regions_mismatch", reasons)

    def test_exact_fps_mismatch_hard_fails_profile_binding(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            rig_path, rig, atlas_path, binding = self._fixture(Path(temporary))
            rig["animations"]["walk_down"]["fps"] = 7.999
            summary, reasons = self._gate(rig_path, rig, atlas_path, binding)
            self.assertEqual(summary["verdict"], "hard_fail")
            self.assertIn("source_profile_fps_mismatch", reasons)

    def test_profile_region_alias_collision_is_malformed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            rig_path, rig, atlas_path, binding = self._fixture(Path(temporary))
            profile_path = Path(temporary) / "tools" / "profiles" / "walk.json"
            profile = json.loads(profile_path.read_text(encoding="utf-8"))
            profile["frames"][0]["attachment_regions"]["hip_left"] = [0, 0, 1, 1]
            profile_path.write_text(json.dumps(profile), encoding="utf-8")
            binding["source_profile"]["sha256"] = hashlib.sha256(
                profile_path.read_bytes()
            ).hexdigest()
            summary, reasons = self._gate(rig_path, rig, atlas_path, binding)
            self.assertEqual(summary["verdict"], "hard_fail")
            self.assertIn("source_profile_malformed", reasons)


class StaleGeometryTests(unittest.TestCase):
    def _check_stale_geometry(
        self, baseline_path: Path, candidate_path: Path, animation_id: str
    ):
        return STALE.check_stale_geometry(
            baseline_path,
            candidate_path,
            animation_id,
            require_trusted_baseline=False,
        )

    def _write_rig(self, path: Path, frames: list[dict]) -> None:
        normalized_frames = [
            {"frame_index": frame_index, **frame}
            for frame_index, frame in enumerate(frames)
        ]
        payload = {
            "schema_version": "gogobro-character-attachment-rig-v2",
            "rig_id": f"test_rig_{path.stem}",
            "character_id": "character.test",
            "animations": {
                "walk_down": {
                    "frame_count": len(normalized_frames),
                    "frames": normalized_frames,
                }
            },
        }
        path.write_text(json.dumps(payload), encoding="utf-8")

    def _baseline_frames(self) -> list[dict]:
        return [
            {"sockets": {"a": [1, 2], "b": [3, 4], "c": [5, 7]}},
            {"sockets": {"a": [2, 4], "b": [4, 5], "c": [7, 8]}},
        ]

    def _affine_cycle(self, count: int) -> list[dict]:
        baseline = self._baseline_frames()
        result = []
        for index in range(count):
            sockets = {
                socket_id: [2 * point[0] + 7, 3 * point[1] - 1]
                for socket_id, point in baseline[index % len(baseline)]["sockets"].items()
            }
            result.append({"sockets": sockets})
        return result

    def test_old_frames_scaled_and_cycled_into_new_frames_hard_fail(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            self._write_rig(baseline_path, self._baseline_frames())
            self._write_rig(candidate_path, self._affine_cycle(5))
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertIn(
                "stale_geometry_affine_cycle_reuse", report["reason_codes"]
            )

    def test_sparse_snapping_does_not_hide_stale_reuse(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            candidate = self._affine_cycle(5)
            candidate[4]["sockets"]["c"][0] += 1
            candidate[3]["sockets"]["b"][1] -= 1
            self._write_rig(baseline_path, self._baseline_frames())
            self._write_rig(candidate_path, candidate)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertIn(
                "stale_geometry_affine_cycle_reuse", report["reason_codes"]
            )

    def test_independently_authored_geometry_passes_stale_gate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            candidate = []
            socket_ids = ("a", "b", "c")
            for frame_index in range(5):
                candidate.append(
                    {
                        "sockets": {
                            socket_id: [
                                20 + frame_index * frame_index + socket_index * 7,
                                30 + frame_index * (socket_index + 2) + socket_index**2,
                            ]
                            for socket_index, socket_id in enumerate(socket_ids)
                        }
                    }
                )
            self._write_rig(baseline_path, self._baseline_frames())
            self._write_rig(candidate_path, candidate)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "stale_geometry_pass")
            self.assertEqual(report["reason_codes"], [])

    def test_cycle_phase_shift_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            baseline = self._baseline_frames()
            candidate = [copy.deepcopy(baseline[(index + 1) % 2]) for index in range(4)]
            self._write_rig(baseline_path, baseline)
            self._write_rig(candidate_path, candidate)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertIn(
                "stale_geometry_affine_cycle_reuse", report["reason_codes"]
            )
            self.assertEqual(
                report["comparison"]["full_sequence"]["cycle_phase"], 1
            )

    def test_constant_axis_affine_reuse_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            baseline = [
                {"sockets": {"a": [1, 5], "b": [3, 5], "c": [8, 5]}},
                {"sockets": {"a": [2, 5], "b": [5, 5], "c": [9, 5]}},
            ]
            candidate = [
                {
                    "sockets": {
                        socket_id: [2 * point[0] + 7, 11]
                        for socket_id, point in baseline[index % 2]["sockets"].items()
                    }
                }
                for index in range(4)
            ]
            self._write_rig(baseline_path, baseline)
            self._write_rig(candidate_path, candidate)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertIn(
                "stale_geometry_affine_cycle_reuse", report["reason_codes"]
            )

    def test_only_new_tail_reusing_old_frames_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            baseline = self._baseline_frames()
            fresh_prefix = [
                {"sockets": {"a": [30, 30], "b": [50, 31], "c": [80, 34]}},
                {"sockets": {"a": [31, 50], "b": [60, 53], "c": [91, 57]}},
            ]
            copied_tail = [copy.deepcopy(baseline[index % 2]) for index in range(3)]
            self._write_rig(baseline_path, baseline)
            self._write_rig(candidate_path, fresh_prefix + copied_tail)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertIn("stale_geometry_affine_tail_reuse", report["reason_codes"])

    def test_underdetermined_topology_fails_as_insufficient_not_stale(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            frames = [{"sockets": {"only": [1, 2]}}, {"sockets": {"only": [5, 8]}}]
            self._write_rig(baseline_path, frames)
            self._write_rig(candidate_path, frames)
            report = self._check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertEqual(report["reason_codes"], ["insufficient_geometry_evidence"])

    def test_public_gate_defaults_to_trusted_baseline_authority(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            self._write_rig(baseline_path, self._baseline_frames())
            self._write_rig(candidate_path, self._affine_cycle(4))
            report = STALE.check_stale_geometry(
                baseline_path, candidate_path, "walk_down"
            )
            self.assertEqual(report["verdict"], "hard_fail")
            self.assertEqual(report["reason_codes"], ["baseline_not_trusted"])

    def test_cli_output_cannot_overwrite_source_rig(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            baseline_path = root / "baseline.json"
            candidate_path = root / "candidate.json"
            self._write_rig(baseline_path, self._baseline_frames())
            self._write_rig(candidate_path, self._affine_cycle(4))
            before = baseline_path.read_bytes()
            with contextlib.redirect_stdout(io.StringIO()):
                exit_code = STALE.main(
                    [
                        "--baseline-rig",
                        str(baseline_path),
                        "--candidate-rig",
                        str(candidate_path),
                        "--animation",
                        "walk_down",
                        "--out",
                        str(baseline_path),
                    ]
                )
            self.assertEqual(exit_code, 2)
            self.assertEqual(baseline_path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
