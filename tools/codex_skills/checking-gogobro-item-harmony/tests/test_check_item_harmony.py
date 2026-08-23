from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import replace
from pathlib import Path

import pytest
from PIL import Image

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from check_item_harmony import (  # noqa: E402
    Box,
    HarmonyInputs,
    HarmonyReport,
    VisualRubric,
    analyze_harmony,
    apply_visual_rubric,
    check_source_integrity,
    derive_nearest_2x_icon,
    find_largest_enclosed_transparent_region,
    main,
    write_harmony_outputs,
)


TOOLS_ROOT = Path(__file__).parents[3]
NIKO_ATLAS = (
    TOOLS_ROOT.parent
    / "game"
    / "content"
    / "packs"
    / "characters"
    / "niko"
    / "animations"
    / "walk_down"
    / "sprite-sheet-alpha.png"
)
NIKO_RIG_PROFILE = TOOLS_ROOT / "assets" / "rig_profiles" / "niko_walk_down_v1.json"
NIKO_SLOTS = {
    "head",
    "face",
    "torso",
    "back",
    "wrist",
    "feet",
    "side_left",
    "side_right",
    "trinket_left",
    "trinket_right",
}


def _write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _appearance(
    path: Path,
    *,
    outer_width: int = 64,
    aperture_center: tuple[int, int] = (62, 71),
    alpha: int = 255,
    transparent_rgb: tuple[int, int, int] = (0, 0, 0),
    chroma: bool = False,
    palette_count: int = 1,
) -> None:
    image = Image.new("RGBA", (128, 128), (*transparent_rgb, 0))
    left = 62 - outer_width // 2
    image.paste((0, 0, 0, alpha), (left, 50, left + outer_width, 91))
    aperture_left = aperture_center[0] - 4
    aperture_top = aperture_center[1] - 4
    image.paste((0, 0, 0, 0), (aperture_left, aperture_top, aperture_left + 9, aperture_top + 9))
    if chroma:
        image.putpixel((left, 50), (0, 255, 0, alpha))
    for index in range(palette_count):
        image.putpixel((left + index, 51), (index * 17, index * 13, index * 11, alpha))
    image.save(path)


class HeadFixture:
    def __init__(self, root: Path, frame_count: int = 8) -> None:
        self.root = root
        self.frame_count = frame_count
        self.character_atlas = root / "character.png"
        self.appearance = root / "appearance.png"
        self.icon = root / "icon.png"
        self.anchors = root / "anchors.json"
        self.rig_profile = root / "rig.json"
        self.out_dir = root / "out"
        Image.new("RGBA", (128 * frame_count, 128), (0, 0, 0, 0)).save(self.character_atlas)
        self._write_assets()

    def _write_assets(
        self,
        *,
        outer_width: int = 64,
        head_width: int = 58,
        aperture_center: tuple[int, int] = (62, 71),
        face_center: tuple[int, int] = (62, 71),
        alpha: int = 255,
        transparent_rgb: tuple[int, int, int] = (0, 0, 0),
        chroma: bool = False,
        palette_count: int = 1,
    ) -> None:
        _appearance(
            self.appearance,
            outer_width=outer_width,
            aperture_center=aperture_center,
            alpha=alpha,
            transparent_rgb=transparent_rgb,
            chroma=chroma,
            palette_count=palette_count,
        )
        with Image.open(self.appearance) as image:
            derive_nearest_2x_icon(image).save(self.icon)
        faces = [[face_center[0] + index, face_center[1]] for index in range(self.frame_count)]
        _write_json(
            self.rig_profile,
            {
                "frame_size": [128, 128],
                "atlas_size": [128 * self.frame_count, 128],
                "frames": [
                    {
                        "head_width": head_width,
                        "face_center": face,
                        "protected_regions": {"eyes": [58 + index, 68, 67 + index, 73]},
                        "depths": {"head": 40},
                    }
                    for index, face in enumerate(faces)
                ],
                "slot_profiles": {
                    "head": {
                        "outer_width_ratio": [1.05, 1.15],
                        "feature_center_max_px": 1,
                        "residual_jitter_max_px": 1,
                        "expected_depth": 40,
                        "max_palette_colors": 8,
                        "direct_icon_reuse": True,
                    }
                },
            },
        )
        _write_json(
            self.anchors,
            {
                "slot": "head",
                "frames": [
                    {"scale": 1, "offset": [index, 0], "depth": 40}
                    for index in range(self.frame_count)
                ],
            },
        )

    def inputs(self) -> HarmonyInputs:
        return HarmonyInputs(
            character_atlas=self.character_atlas,
            appearance=self.appearance,
            icon=self.icon,
            anchors=self.anchors,
            rig_profile=self.rig_profile,
            slot="head",
            out_dir=self.out_dir,
        )

    def _rewrite(self, **changes: object) -> HarmonyInputs:
        self._write_assets(**changes)
        return self.inputs()

    def with_outer_width(self, value: int) -> HarmonyInputs:
        return self._rewrite(outer_width=value)

    def with_head_width(self, value: int) -> HarmonyInputs:
        return self._rewrite(head_width=value)

    def with_aperture_center(self, value: tuple[int, int]) -> HarmonyInputs:
        return self._rewrite(aperture_center=value)

    def with_face_center(self, value: tuple[int, int]) -> HarmonyInputs:
        return self._rewrite(face_center=value)


class NikoSlotFixture:
    _APPEARANCE_BOXES = {
        "torso": [52, 83, 72, 108],
        "side_left": [31, 78, 43, 106],
    }

    def __init__(self, root: Path, slot: str) -> None:
        self.root = root
        self.slot = slot
        self.character_atlas = NIKO_ATLAS
        self.appearance = root / "appearance.png"
        self.icon = root / "icon.png"
        self.anchors = root / "anchors.json"
        self.rig_profile = root / "rig.json"
        self.out_dir = root / "out"

        profile = json.loads(NIKO_RIG_PROFILE.read_text(encoding="utf-8"))
        left, top, right, bottom = self._APPEARANCE_BOXES[slot]
        image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        image.putpixel((left, top), (40, 30, 20, 255))
        image.paste((40, 30, 20, 255), (left, 92, right, bottom))
        image.save(self.appearance)
        derive_nearest_2x_icon(image).save(self.icon)

        shifts = [0, 0, 0, 0, 2, 2, 0, 0]
        for frame, shift in zip(profile["frames"], shifts, strict=True):
            frame["protected_regions"]["eyes"] = [
                left + shift,
                top,
                right + shift,
                bottom,
            ]
        _write_json(self.rig_profile, profile)
        _write_json(
            self.anchors,
            {
                "slot": slot,
                "flip_behavior": profile["slot_profiles"][slot]["flip_behavior"],
                "frames": [
                    {"scale": 1, "offset": [shift, 0], "depth": 40}
                    for shift in shifts
                ],
            },
        )

    def inputs(self) -> HarmonyInputs:
        return HarmonyInputs(
            character_atlas=self.character_atlas,
            appearance=self.appearance,
            icon=self.icon,
            anchors=self.anchors,
            rig_profile=self.rig_profile,
            slot=self.slot,
            out_dir=self.out_dir,
        )

    def rewrite_contract(self, field: str, value: object) -> HarmonyInputs:
        profile = json.loads(self.rig_profile.read_text(encoding="utf-8"))
        profile["slot_profiles"][self.slot][field] = value
        _write_json(self.rig_profile, profile)
        return self.inputs()

    def rewrite_anchors(self, **changes: object) -> HarmonyInputs:
        anchors = json.loads(self.anchors.read_text(encoding="utf-8"))
        anchors.update(changes)
        _write_json(self.anchors, anchors)
        return self.inputs()


@pytest.fixture
def head_fixture(tmp_path: Path) -> HeadFixture:
    return HeadFixture(tmp_path)


@pytest.fixture
def appearance_image(tmp_path: Path) -> Image.Image:
    path = tmp_path / "appearance.png"
    _appearance(path)
    with Image.open(path) as image:
        return image.copy()


@pytest.fixture
def valid_inputs(head_fixture: HeadFixture) -> HarmonyInputs:
    return head_fixture.inputs()


def rubric(scores: list[int]) -> VisualRubric:
    evidence = "reviewed against the actual-size deterministic preview"
    return VisualRubric(
        identity=(scores[0], evidence),
        function=(scores[1], evidence),
        material=(scores[2], evidence),
        hierarchy=(scores[3], evidence),
        originality=(scores[4], evidence),
    )


def test_niko_walk_down_profile_matches_canonical_atlas_and_shifted_regions() -> None:
    profile = json.loads(NIKO_RIG_PROFILE.read_text(encoding="utf-8"))
    atlas_sha256 = hashlib.sha256(NIKO_ATLAS.read_bytes()).hexdigest().upper()
    assert profile["schema_version"] == "gogobro-rig-profile-v1"
    assert profile["character_atlas_sha256"] == atlas_sha256
    assert atlas_sha256 == "FBC10108D9A665B14DCC376DA54BBBF66D89B931AE1189E69FE1C45B31FE579D"
    assert profile["frame_size"] == [128, 128]
    assert profile["atlas_size"] == [1024, 128]
    assert len(profile["frames"]) == 8
    assert [frame["face_center"][0] for frame in profile["frames"]] == [
        62,
        62,
        62,
        62,
        64,
        64,
        62,
        62,
    ]
    assert all(frame["face_center"][1] == 71 for frame in profile["frames"])
    assert [frame["face_roi"] for frame in profile["frames"]] == [
        [44, 50, 80, 92],
        [44, 50, 80, 92],
        [44, 50, 80, 92],
        [44, 50, 80, 92],
        [46, 50, 82, 92],
        [46, 50, 82, 92],
        [44, 50, 80, 92],
        [44, 50, 80, 92],
    ]
    assert [frame["protected_regions"]["eyes"] for frame in profile["frames"]] == [
        [48, 64, 78, 80],
        [48, 64, 78, 80],
        [48, 64, 78, 80],
        [48, 64, 78, 80],
        [50, 64, 80, 80],
        [50, 64, 80, 80],
        [48, 64, 78, 80],
        [48, 64, 78, 80],
    ]


def test_niko_profile_has_explicit_distinct_slot_contracts_and_attachment_boxes() -> None:
    profile = json.loads(NIKO_RIG_PROFILE.read_text(encoding="utf-8"))
    slots = profile["slot_profiles"]
    assert set(slots) == NIKO_SLOTS
    assert slots["head"]["outer_width_ratio"] == [1.05, 1.15]
    assert slots["head"]["max_feature_center_error_px"] == 1
    assert slots["head"]["max_residual_jitter_px"] == 1
    required_contract = {
        "feature_anchor",
        "outer_width_ratio",
        "protected_region",
        "max_occlusion_ratio",
        "depth_band",
        "flip_behavior",
        "expected_depth",
        "max_feature_center_error_px",
        "max_residual_jitter_px",
        "feature_center_max_px",
        "residual_jitter_max_px",
        "max_palette_colors",
    }
    assert all(required_contract <= set(contract) for contract in slots.values())
    assert all(contract["feature_anchor"] != "face_center" for name, contract in slots.items() if name != "head")
    assert slots["side_left"] != slots["side_right"]
    assert slots["trinket_left"] != slots["trinket_right"]
    assert slots["wrist"]["selected_side"] == "right"
    assert slots["wrist"]["feature_anchor"] == "attachment_regions.wrist_right"

    region_names = {
        "torso",
        "back",
        "wrist_left",
        "wrist_right",
        "feet",
        "side_left",
        "side_right",
        "trinket_left",
        "trinket_right",
    }
    for frame in profile["frames"]:
        regions = frame["attachment_regions"]
        assert set(regions) == region_names
        assert all(
            len(box) == 4 and all(isinstance(coordinate, int) for coordinate in box)
            for box in regions.values()
        )


def test_torso_contract_consumes_non_head_anchor_ratio_and_allowed_roi_occlusion(
    tmp_path: Path,
) -> None:
    report = analyze_harmony(NikoSlotFixture(tmp_path, "torso").inputs())
    assert report.verdict == "review"
    assert report.metrics["outer_width_ratio"] == pytest.approx(20 / 34)
    assert report.metrics["max_feature_center_error_px"] == 0
    assert report.metrics["max_protected_occlusion_ratio"] == pytest.approx(1 / (36 * 42))
    assert report.metrics["aperture_box"] is None


def test_non_head_depth_band_is_enforced(tmp_path: Path) -> None:
    fixture = NikoSlotFixture(tmp_path, "torso")
    anchors = json.loads(fixture.anchors.read_text(encoding="utf-8"))
    for anchor in anchors["frames"]:
        anchor["depth"] = 100
    _write_json(fixture.anchors, anchors)
    report = analyze_harmony(fixture.inputs())
    assert "depth_band_mismatch" in report.reason_codes


def test_non_head_flip_behavior_is_enforced(tmp_path: Path) -> None:
    fixture = NikoSlotFixture(tmp_path, "side_left")
    report = analyze_harmony(fixture.rewrite_anchors(flip_behavior="none"))
    assert "flip_mismatch" in report.reason_codes


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("feature_anchor", "attachment_regions.troso"),
        ("protected_region", "protected_regions.faec"),
        ("max_occlusion_ratio", 1.1),
        ("depth_band", [99, 1]),
        ("flip_behavior", "miror_to_right"),
    ],
)
def test_invalid_non_head_contract_fields_hard_fail_actionably(
    tmp_path: Path, field: str, value: object
) -> None:
    fixture = NikoSlotFixture(tmp_path, "torso")
    report = analyze_harmony(fixture.rewrite_contract(field, value))
    assert report.verdict == "hard_fail"
    assert report.reason_codes == ("invalid_contract",)


def test_oversized_head_item_is_hard_fail(head_fixture: HeadFixture) -> None:
    report = analyze_harmony(head_fixture._rewrite(outer_width=76, head_width=58))
    assert report.verdict == "hard_fail"
    assert "scale_ratio_high" in report.reason_codes
    assert report.metrics["outer_width_ratio"] == pytest.approx(76 / 58)


def test_aperture_offset_is_reported_in_pixels(head_fixture: HeadFixture) -> None:
    report = analyze_harmony(head_fixture._rewrite(aperture_center=(58, 71), face_center=(62, 71)))
    assert "feature_center_offset" in report.reason_codes
    assert report.metrics["max_feature_center_error_px"] == 4


@pytest.mark.filterwarnings("ignore:Image.Image.getdata is deprecated:DeprecationWarning")
def test_direct_icon_contract_is_exact_nearest_2x(appearance_image: Image.Image) -> None:
    icon = derive_nearest_2x_icon(appearance_image)
    assert icon.size == (256, 256)
    assert list(icon.getdata()) == list(
        appearance_image.resize((256, 256), Image.Resampling.NEAREST).getdata()
    )


def test_non_nearest_icon_is_hard_fail(head_fixture: HeadFixture) -> None:
    with Image.open(head_fixture.icon) as image:
        changed = image.copy()
    changed.putpixel((0, 0), (255, 0, 0, 255))
    changed.save(head_fixture.icon)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "icon_not_nearest_2x" in report.reason_codes


@pytest.mark.parametrize(
    ("change", "reason"),
    [
        ("non_binary_alpha", "non_binary_alpha"),
        ("transparent_rgb", "transparent_rgb"),
        ("chroma", "chroma_residue"),
        ("palette", "palette_limit"),
    ],
)
def test_pixel_contract_failures_are_hard_fail(
    head_fixture: HeadFixture, change: str, reason: str
) -> None:
    if change == "non_binary_alpha":
        inputs = head_fixture._rewrite(alpha=128)
    elif change == "transparent_rgb":
        inputs = head_fixture._rewrite(transparent_rgb=(3, 2, 1))
    elif change == "chroma":
        inputs = head_fixture._rewrite(chroma=True)
    else:
        inputs = head_fixture._rewrite(palette_count=9)
    report = analyze_harmony(inputs)
    assert report.verdict == "hard_fail"
    assert reason in report.reason_codes


def test_cropped_appearance_is_hard_fail(head_fixture: HeadFixture) -> None:
    payload = json.loads(head_fixture.anchors.read_text(encoding="utf-8"))
    payload["frames"][0]["offset"] = [80, 0]
    _write_json(head_fixture.anchors, payload)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "crop" in report.reason_codes


def test_protected_eye_occlusion_is_hard_fail(head_fixture: HeadFixture) -> None:
    profile = json.loads(head_fixture.rig_profile.read_text(encoding="utf-8"))
    profile["frames"][0]["protected_regions"]["eyes"] = [32, 55, 36, 59]
    _write_json(head_fixture.rig_profile, profile)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "protected_region_occlusion" in report.reason_codes


def test_wrong_depth_is_hard_fail(head_fixture: HeadFixture) -> None:
    anchors = json.loads(head_fixture.anchors.read_text(encoding="utf-8"))
    anchors["frames"][0]["depth"] = 10
    _write_json(head_fixture.anchors, anchors)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "depth_mismatch" in report.reason_codes


def test_duplicate_slot_is_hard_fail(head_fixture: HeadFixture) -> None:
    anchors = json.loads(head_fixture.anchors.read_text(encoding="utf-8"))
    anchors["occupied_slots"] = ["head"]
    _write_json(head_fixture.anchors, anchors)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "duplicate_slot" in report.reason_codes


def test_anchor_count_is_hard_fail(head_fixture: HeadFixture) -> None:
    anchors = json.loads(head_fixture.anchors.read_text(encoding="utf-8"))
    anchors["frames"].pop()
    _write_json(head_fixture.anchors, anchors)
    report = analyze_harmony(head_fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "anchor_count" in report.reason_codes


@pytest.mark.parametrize("frame_count", [2, 8])
def test_residual_jitter_is_detected_for_two_and_eight_frame_rigs(
    tmp_path: Path, frame_count: int
) -> None:
    fixture = HeadFixture(tmp_path, frame_count=frame_count)
    anchors = json.loads(fixture.anchors.read_text(encoding="utf-8"))
    anchors["frames"][-1]["offset"][0] += 2
    _write_json(fixture.anchors, anchors)
    report = analyze_harmony(fixture.inputs())
    assert report.verdict == "hard_fail"
    assert "residual_jitter" in report.reason_codes
    assert report.metrics["max_residual_jitter_px"] == 2


def test_largest_enclosed_transparency_uses_four_connected_fill(tmp_path: Path) -> None:
    path = tmp_path / "regions.png"
    image = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    image.paste((0, 0, 0, 255), (1, 1, 11, 11))
    image.paste((0, 0, 0, 0), (3, 3, 8, 8))
    image.putpixel((1, 1), (0, 0, 0, 0))
    image.save(path)
    with Image.open(path) as loaded:
        assert find_largest_enclosed_transparent_region(loaded) == Box(3, 3, 8, 8)


def test_valid_geometry_stays_review_until_visual_rubric(valid_inputs: HarmonyInputs) -> None:
    assert analyze_harmony(valid_inputs).verdict == "review"


def test_complete_passing_visual_rubric_advances_to_harmony_pass(
    valid_inputs: HarmonyInputs,
) -> None:
    valid_report = analyze_harmony(valid_inputs)
    assert apply_visual_rubric(valid_report, rubric(scores=[2, 2, 2, 1, 1])).verdict == "harmony_pass"


@pytest.mark.parametrize("scores", [[2, 2, 1, 1, 1], [2, 2, 2, 2, 0]])
def test_incomplete_visual_rubric_stays_review(
    valid_inputs: HarmonyInputs, scores: list[int]
) -> None:
    valid_report = analyze_harmony(valid_inputs)
    assert apply_visual_rubric(valid_report, rubric(scores=scores)).verdict == "review"


def test_outputs_are_byte_identical_and_cli_uses_verdict_exit_codes(
    valid_inputs: HarmonyInputs,
) -> None:
    first = replace(valid_inputs, out_dir=valid_inputs.out_dir / "first")
    second = replace(valid_inputs, out_dir=valid_inputs.out_dir / "second")
    first_report = analyze_harmony(first)
    second_report = analyze_harmony(second)
    write_harmony_outputs(first_report, first)
    write_harmony_outputs(second_report, second)
    names = ["harmony-report.json", "harmony-overlay.png", "harmony-actual-size.png"]
    assert {name: _sha256(first.out_dir / name) for name in names} == {
        name: _sha256(second.out_dir / name) for name in names
    }
    arguments = [
        "--character-atlas", str(first.character_atlas), "--appearance", str(first.appearance),
        "--icon", str(first.icon), "--anchors", str(first.anchors),
        "--rig-profile", str(first.rig_profile), "--slot", first.slot, "--out-dir", str(first.out_dir),
    ]
    assert main(arguments) == 0


def test_cli_returns_two_for_hard_fail(head_fixture: HeadFixture) -> None:
    inputs = head_fixture.with_outer_width(76)
    assert main([
        "--character-atlas", str(inputs.character_atlas), "--appearance", str(inputs.appearance),
        "--icon", str(inputs.icon), "--anchors", str(inputs.anchors),
        "--rig-profile", str(inputs.rig_profile), "--slot", inputs.slot, "--out-dir", str(inputs.out_dir),
    ]) == 2


def _arguments(inputs: HarmonyInputs) -> list[str]:
    return [
        "--character-atlas", str(inputs.character_atlas), "--appearance", str(inputs.appearance),
        "--icon", str(inputs.icon), "--anchors", str(inputs.anchors),
        "--rig-profile", str(inputs.rig_profile), "--slot", inputs.slot, "--out-dir", str(inputs.out_dir),
    ]


def test_cli_rejects_output_source_collision_without_mutating_the_source(
    head_fixture: HeadFixture,
) -> None:
    collision = head_fixture.root / "harmony-overlay.png"
    head_fixture.character_atlas.replace(collision)
    inputs = replace(head_fixture.inputs(), character_atlas=collision, out_dir=head_fixture.root)
    original = _sha256(collision)
    assert main(_arguments(inputs)) == 2
    assert _sha256(collision) == original
    assert not (head_fixture.root / "harmony-report.json").exists()


def test_source_integrity_marks_a_report_hard_fail_after_a_source_changes(
    valid_inputs: HarmonyInputs,
) -> None:
    initial_hashes = {
        "character_atlas": _sha256(valid_inputs.character_atlas),
        "appearance": _sha256(valid_inputs.appearance),
        "icon": _sha256(valid_inputs.icon),
        "anchors": _sha256(valid_inputs.anchors),
        "rig_profile": _sha256(valid_inputs.rig_profile),
    }
    valid_inputs.anchors.write_text("{}", encoding="utf-8")
    report = check_source_integrity(
        HarmonyReport("review", (), {}, initial_hashes), valid_inputs, initial_hashes
    )
    assert report.verdict == "hard_fail"
    assert "source_changed" in report.reason_codes


@pytest.mark.parametrize(
    ("change", "reason"),
    [
        ("bad_json", "malformed_input"),
        ("bad_image", "malformed_input"),
        ("bad_coordinate", "invalid_frame_data"),
        ("bad_contract", "invalid_contract"),
        ("zero_scale", "invalid_scale"),
    ],
)
def test_malformed_required_input_returns_hard_fail_report_and_cli_two(
    head_fixture: HeadFixture, change: str, reason: str
) -> None:
    inputs = head_fixture.inputs()
    if change == "bad_json":
        inputs.anchors.write_text("{", encoding="utf-8")
    elif change == "bad_image":
        inputs.appearance.write_text("not a png", encoding="utf-8")
    elif change == "bad_coordinate":
        anchors = json.loads(inputs.anchors.read_text(encoding="utf-8"))
        anchors["frames"][0]["offset"] = [0]
        _write_json(inputs.anchors, anchors)
    elif change == "bad_contract":
        profile = json.loads(inputs.rig_profile.read_text(encoding="utf-8"))
        profile["slot_profiles"]["head"]["outer_width_ratio"] = ["low", 1.15]
        _write_json(inputs.rig_profile, profile)
    else:
        anchors = json.loads(inputs.anchors.read_text(encoding="utf-8"))
        anchors["frames"][0]["scale"] = 0
        _write_json(inputs.anchors, anchors)
    report = analyze_harmony(inputs)
    assert report.verdict == "hard_fail"
    assert reason in report.reason_codes
    assert main(_arguments(inputs)) == 2
    persisted = json.loads((inputs.out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    assert persisted["verdict"] == "hard_fail"


def test_malformed_visual_rubric_returns_hard_fail_and_exit_two(valid_inputs: HarmonyInputs) -> None:
    rubric_path = valid_inputs.out_dir.parent / "rubric.json"
    rubric_path.write_text("{", encoding="utf-8")
    assert main(_arguments(valid_inputs) + ["--visual-rubric", str(rubric_path)]) == 2
    report = json.loads((valid_inputs.out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    assert "malformed_visual_rubric" in report["reason_codes"]


def test_each_frame_uses_its_placed_alpha_width_and_own_head_width(
    head_fixture: HeadFixture,
) -> None:
    inputs = head_fixture.inputs()
    anchors = json.loads(inputs.anchors.read_text(encoding="utf-8"))
    for anchor in anchors["frames"]:
        anchor["scale"] = 0.51
    _write_json(inputs.anchors, anchors)
    profile = json.loads(inputs.rig_profile.read_text(encoding="utf-8"))
    profile["slot_profiles"]["head"]["outer_width_ratio"] = [0, 1.09]
    profile["frames"][0]["head_width"] = 100
    profile["frames"][-1]["head_width"] = 30
    _write_json(inputs.rig_profile, profile)
    report = analyze_harmony(inputs)
    assert report.verdict == "hard_fail"
    assert "scale_ratio_high" in report.reason_codes
    assert report.metrics["outer_width_ratios"][-1] == pytest.approx(33 / 30)
    assert report.metrics["outer_width_ratio"] == pytest.approx(33 / 30)


def test_output_bytes_are_canonical_and_diagnostics_have_fixed_content(
    valid_inputs: HarmonyInputs,
) -> None:
    report = analyze_harmony(valid_inputs)
    write_harmony_outputs(report, valid_inputs)
    raw_report = (valid_inputs.out_dir / "harmony-report.json").read_bytes()
    decoded = json.loads(raw_report)
    assert raw_report == (
        json.dumps(decoded, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    assert raw_report.endswith(b"\n")
    with Image.open(valid_inputs.out_dir / "harmony-overlay.png") as overlay:
        assert overlay.getpixel((30, 50)) == (255, 0, 255, 255)
        assert overlay.getbbox() is not None
    with Image.open(valid_inputs.out_dir / "harmony-actual-size.png") as preview:
        assert preview.size == (1920, 1080)
        assert preview.getpixel((0, 0)) == (18, 22, 30, 255)


def test_optional_visual_rubric_and_transform_suggestion_paths_are_written(
    valid_inputs: HarmonyInputs,
) -> None:
    rubric_path = valid_inputs.out_dir.parent / "rubric.json"
    _write_json(
        rubric_path,
        {
            name: {"score": 2, "evidence": "visible in deterministic preview"}
            for name in ("identity", "function", "material", "hierarchy", "originality")
        },
    )
    assert main(
        _arguments(valid_inputs)
        + ["--visual-rubric", str(rubric_path), "--suggest-transform"]
    ) == 0
    report = json.loads((valid_inputs.out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    assert report["verdict"] == "harmony_pass"
    raw_suggestion = (valid_inputs.out_dir / "transform-suggestion.json").read_bytes()
    assert raw_suggestion == b'{\n  "reason_codes": []\n}\n'
