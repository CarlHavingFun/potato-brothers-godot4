from __future__ import annotations

import importlib.util
import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


SKILL_ROOT = Path(__file__).parents[1]
REPO_ROOT = Path(__file__).parents[4]
SCRIPT_PATH = SKILL_ROOT / "scripts" / "check_character_socket_rig.py"
RIG_PATH = (
    REPO_ROOT
    / "game"
    / "content"
    / "packs"
    / "characters"
    / "niko"
    / "rig"
    / "niko_attachment_rig_v2.json"
)
ATLAS_PATH = (
    REPO_ROOT
    / "game"
    / "content"
    / "packs"
    / "characters"
    / "niko"
    / "animations"
    / "walk_down"
    / "sprite-sheet-alpha.png"
)
REGISTRY_PATH = REPO_ROOT / "game" / "content" / "assets" / "gogobro_static_assets_v1.json"

spec = importlib.util.spec_from_file_location("check_character_socket_rig", SCRIPT_PATH)
assert spec and spec.loader
checker = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = checker
spec.loader.exec_module(checker)


def _mutated_rig(tmp_path: Path, mutate) -> Path:
    payload = json.loads(RIG_PATH.read_text(encoding="utf-8"))
    mutate(payload)
    path = tmp_path / "rig.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def _check(path: Path = RIG_PATH, atlas: Path = ATLAS_PATH):
    return checker.check_character_socket_rig(path, atlas, REGISTRY_PATH)


def _two_row_atlas(tmp_path: Path) -> Path:
    with Image.open(ATLAS_PATH) as opened:
        source = opened.convert("RGBA")
    atlas = Image.new("RGBA", (source.width, source.height * 2), (0, 0, 0, 0))
    atlas.alpha_composite(source, (0, 0))
    atlas.alpha_composite(source, (0, source.height))
    path = tmp_path / "two-row-atlas.png"
    atlas.save(path)
    return path


def _bind_atlas(payload: dict, atlas: Path) -> None:
    with Image.open(atlas) as opened:
        payload["atlas"]["atlas_size"] = list(opened.size)
    payload["atlas"]["sha256"] = hashlib.sha256(atlas.read_bytes()).hexdigest()


def _duplicate_animation(payload: dict, animation_id: str, row: int) -> dict:
    duplicate = json.loads(json.dumps(payload["animations"]["walk_down"]))
    duplicate["row"] = row
    for frame_index, frame in enumerate(duplicate["frames"]):
        frame["frame_name"] = f"{animation_id}_{frame_index + 1:02d}"
    return duplicate


def test_canonical_niko_rig_covers_every_socket_in_all_eight_frames(tmp_path: Path) -> None:
    result = _check()

    assert result.verdict == "rig_pass"
    assert result.reason_codes == ()
    assert result.report["metrics"]["animation_count"] == 1
    assert result.report["metrics"]["frame_count"] == 8
    assert result.report["metrics"]["socket_count"] == 24
    assert result.report["metrics"]["socket_coverage"] == 192
    assert result.report["metrics"]["trusted_opaque_contact_coverage"] == 72
    assert result.report["metrics"]["trusted_opaque_contact_expected"] == 72
    assert result.report["metrics"]["trusted_rig_sha256"] == hashlib.sha256(
        RIG_PATH.read_bytes()
    ).hexdigest()
    assert result.report["metrics"]["trusted_rig_id"] == "niko_walk_down_attachment_v2"
    assert result.report["metrics"]["trusted_rig_animation_ids"] == ["walk_down"]
    assert result.report["metrics"]["atlas_columns"] == 8
    assert result.report["metrics"]["atlas_rows"] == 1
    assert result.report["metrics"]["registry_item_count"] == 30
    assert result.report["metrics"]["registry_required_socket_count"] == 15
    assert result.report["issues"] == []
    assert result.report["metrics"]["socket_positions"]["head_shell"] == [
        [62, 71],
        [62, 71],
        [62, 71],
        [62, 71],
        [64, 71],
        [64, 71],
        [62, 71],
        [62, 71],
    ]

    checker.write_outputs(result, tmp_path)
    report = json.loads((tmp_path / "socket-rig-report.json").read_text(encoding="utf-8"))
    assert report["verdict"] == "rig_pass"
    with Image.open(tmp_path / "socket-rig-overview.png") as overview:
        assert overview.size == (1024, 128)
    with Image.open(tmp_path / "socket-rig-walk_down-contact-sheet.png") as contact_sheet:
        assert contact_sheet.size == (1174, 3072)


def test_missing_socket_in_final_frame_is_a_hard_failure(tmp_path: Path) -> None:
    path = _mutated_rig(
        tmp_path,
        lambda payload: payload["animations"]["walk_down"]["frames"][7]["sockets"].pop(
            "head_shell"
        ),
    )

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "missing_socket" in result.reason_codes
    assert {
        "animation": "walk_down",
        "frame": 7,
        "socket": "head_shell",
        "code": "missing_socket",
    } in result.report["issues"]


def test_one_pixel_final_frame_socket_drift_is_a_hard_failure(tmp_path: Path) -> None:
    def drift(payload: dict) -> None:
        payload["animations"]["walk_down"]["frames"][7]["sockets"]["head_shell"][1] += 1

    path = _mutated_rig(tmp_path, drift)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "socket_residual_jitter" in result.reason_codes


def test_back_socket_cannot_use_a_front_depth(tmp_path: Path) -> None:
    def front_depth(payload: dict) -> None:
        payload["socket_catalog"]["back_center"]["default_depth"] = 40

    path = _mutated_rig(tmp_path, front_depth)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "back_depth_mismatch" in result.reason_codes


def test_frame_identity_and_integer_socket_types_are_strict(tmp_path: Path) -> None:
    def malformed(payload: dict) -> None:
        frame = payload["animations"]["walk_down"]["frames"][6]
        frame["frame_index"] = 7
        frame["sockets"]["wrist_right"][0] = 83.0

    path = _mutated_rig(tmp_path, malformed)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "frame_identity_mismatch" in result.reason_codes
    assert "non_integer_socket" in result.reason_codes


def test_truncated_final_frame_cannot_shrink_declared_frame_count(tmp_path: Path) -> None:
    def truncate(payload: dict) -> None:
        animation = payload["animations"]["walk_down"]
        animation["frames"].pop()
        animation["frame_count"] = 7

    path = _mutated_rig(tmp_path, truncate)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "animation_column_coverage_mismatch" in result.reason_codes
    assert {
        "animation": "walk_down",
        "frame": None,
        "socket": None,
        "code": "animation_column_coverage_mismatch",
    } in result.report["issues"]


def test_animation_rows_are_unique_and_cover_the_entire_atlas(tmp_path: Path) -> None:
    atlas = _two_row_atlas(tmp_path)

    missing_row = json.loads(RIG_PATH.read_text(encoding="utf-8"))
    _bind_atlas(missing_row, atlas)
    missing_path = tmp_path / "missing-row.json"
    missing_path.write_text(json.dumps(missing_row), encoding="utf-8")
    missing_result = _check(missing_path, atlas)
    assert missing_result.verdict == "hard_fail"
    assert "animation_row_coverage_mismatch" in missing_result.reason_codes

    duplicate_row = json.loads(RIG_PATH.read_text(encoding="utf-8"))
    _bind_atlas(duplicate_row, atlas)
    duplicate_row["animations"]["idle_down"] = _duplicate_animation(
        duplicate_row, "idle_down", 0
    )
    duplicate_path = tmp_path / "duplicate-row.json"
    duplicate_path.write_text(json.dumps(duplicate_row), encoding="utf-8")
    duplicate_result = _check(duplicate_path, atlas)
    assert duplicate_result.verdict == "hard_fail"
    assert "animation_row_duplicate" in duplicate_result.reason_codes
    assert "animation_row_coverage_mismatch" in duplicate_result.reason_codes


def test_residual_jitter_is_independent_per_animation_and_key_order(
    tmp_path: Path,
) -> None:
    atlas = _two_row_atlas(tmp_path)
    payload = json.loads(RIG_PATH.read_text(encoding="utf-8"))
    _bind_atlas(payload, atlas)
    idle = _duplicate_animation(payload, "idle_down", 1)
    for frame in idle["frames"]:
        frame["sockets"]["head_shell"][0] += 2
    walk = payload["animations"]["walk_down"]

    results = []
    for index, animations in enumerate(
        (
            {"walk_down": walk, "idle_down": idle},
            {"idle_down": idle, "walk_down": walk},
        )
    ):
        ordered_payload = json.loads(json.dumps(payload))
        ordered_payload["animations"] = animations
        path = tmp_path / f"animation-order-{index}.json"
        path.write_text(json.dumps(ordered_payload), encoding="utf-8")
        results.append(_check(path, atlas))

    assert [result.verdict for result in results] == ["hard_fail", "hard_fail"]
    for result in results:
        assert result.reason_codes == ("trusted_rig_binding_missing",)
        jitter = result.report["metrics"]["socket_max_residual_jitter_by_animation"]
        assert jitter["idle_down"]["head_shell"] == 0
        assert jitter["walk_down"]["head_shell"] == 0


def test_registry_required_socket_cannot_be_removed_from_catalog_and_frames(
    tmp_path: Path,
) -> None:
    def remove_forehead(payload: dict) -> None:
        payload["socket_catalog"].pop("forehead")
        for frame in payload["animations"]["walk_down"]["frames"]:
            frame["sockets"].pop("forehead")

    path = _mutated_rig(tmp_path, remove_forehead)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "required_socket_missing" in result.reason_codes
    assert {
        "animation": None,
        "frame": None,
        "socket": "forehead",
        "code": "required_socket_missing",
    } in result.report["issues"]


def test_humanoid_topology_socket_is_required_even_when_no_item_uses_it(
    tmp_path: Path,
) -> None:
    def remove_hand(payload: dict) -> None:
        payload["socket_catalog"].pop("hand_right")
        for frame in payload["animations"]["walk_down"]["frames"]:
            frame["sockets"].pop("hand_right")

    result = _check(_mutated_rig(tmp_path, remove_hand))

    assert result.verdict == "hard_fail"
    assert "trusted_topology_socket_missing" in result.reason_codes


def test_humanoid_topology_socket_is_required_on_every_frame(tmp_path: Path) -> None:
    def remove_final_hand(payload: dict) -> None:
        payload["animations"]["walk_down"]["frames"][-1]["sockets"].pop(
            "hand_left"
        )

    result = _check(_mutated_rig(tmp_path, remove_final_hand))

    assert result.verdict == "hard_fail"
    assert "trusted_topology_frame_coverage_mismatch" in result.reason_codes
    assert {
        "animation": "walk_down",
        "frame": 7,
        "socket": "hand_left",
        "code": "trusted_topology_frame_coverage_mismatch",
    } in result.report["issues"]


def test_humanoid_anatomy_socket_must_touch_an_opaque_character_pixel(
    tmp_path: Path,
) -> None:
    def move_to_transparency(payload: dict) -> None:
        payload["animations"]["walk_down"]["frames"][-1]["sockets"][
            "hand_left"
        ] = [0, 0]

    result = _check(_mutated_rig(tmp_path, move_to_transparency))

    assert result.verdict == "hard_fail"
    assert "trusted_topology_transparent_contact" in result.reason_codes
    assert {
        "animation": "walk_down",
        "frame": 7,
        "socket": "hand_left",
        "code": "trusted_topology_transparent_contact",
    } in result.report["issues"]


def test_truncated_registry_cannot_shrink_the_required_socket_set(tmp_path: Path) -> None:
    registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    registry["units"] = [
        unit for unit in registry["units"] if unit.get("asset_id") != "site_hold_bandana"
    ]
    registry_path = tmp_path / "registry.json"
    registry_path.write_text(json.dumps(registry), encoding="utf-8")

    result = checker.check_character_socket_rig(RIG_PATH, ATLAS_PATH, registry_path)

    assert result.verdict == "hard_fail"
    assert "asset_registry_item_count_mismatch" in result.reason_codes


def test_registry_required_socket_enforces_slot_mode_and_depth(tmp_path: Path) -> None:
    def mismatch_contract(payload: dict) -> None:
        profile = payload["socket_catalog"]["head_shell"]
        profile["slot_id"] = "face"
        profile["allowed_modes"] = ["FRAME_OVERLAY"]
        profile["default_depth"] = 41

    path = _mutated_rig(tmp_path, mismatch_contract)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert {
        "required_socket_slot_mismatch",
        "required_socket_mode_mismatch",
        "required_socket_depth_mismatch",
    } <= set(result.reason_codes)
    assert {
        issue["socket"]
        for issue in result.report["issues"]
        if issue["code"].startswith("required_socket_")
    } == {"head_shell"}


def test_every_frame_requires_nonempty_protected_regions(tmp_path: Path) -> None:
    def remove_protected_regions(payload: dict) -> None:
        for frame in payload["animations"]["walk_down"]["frames"]:
            frame.pop("protected_regions")

    path = _mutated_rig(tmp_path, remove_protected_regions)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "missing_protected_regions" in result.reason_codes
    affected_frames = {
        issue["frame"]
        for issue in result.report["issues"]
        if issue["code"] == "missing_protected_regions"
    }
    assert affected_frames == set(range(8))


def test_every_reference_and_protected_box_must_stay_inside_the_frame(
    tmp_path: Path,
) -> None:
    def enlarge_boxes(payload: dict) -> None:
        frame = payload["animations"]["walk_down"]["frames"][7]
        frame["regions"]["face"] = [0, 0, 999, 999]
        frame["protected_regions"]["eyes"] = [0, 0, 999, 999]

    path = _mutated_rig(tmp_path, enlarge_boxes)

    result = _check(path)

    assert result.verdict == "hard_fail"
    assert "region_out_of_bounds" in result.reason_codes
    assert "protected_region_out_of_bounds" in result.reason_codes
    assert {
        "animation": "walk_down",
        "frame": 7,
        "socket": None,
        "code": "region_out_of_bounds",
    } in result.report["issues"]
