from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw


REPO_ROOT = Path(__file__).parents[4]
SCRIPT = (
    REPO_ROOT
    / "tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_socket_harmony_v2.py"
)
RIG = REPO_ROOT / "game/content/packs/characters/niko/rig/niko_attachment_rig_v2.json"
REGISTRY = REPO_ROOT / "game/content/assets/gogobro_static_assets_v1.json"
ATLAS = (
    REPO_ROOT
    / "game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png"
)
SOURCE_PROFILE = REPO_ROOT / "tools/assets/rig_profiles/niko_walk_down_v1.json"

SPEC = importlib.util.spec_from_file_location("check_item_socket_harmony_v2", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECKER
SPEC.loader.exec_module(CHECKER)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def make_rigid_appearance(path: Path) -> None:
    image = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rectangle((32, 16, 95, 95), fill=(72, 54, 43, 255))
    draw.rectangle((44, 28, 83, 83), fill=(196, 112, 61, 255))
    image.save(path)


def make_overlay_appearance(path: Path, frame_count: int = 8) -> None:
    image = Image.new("RGBA", (128 * frame_count, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for frame_index in range(frame_count):
        x = frame_index * 128
        draw.rectangle((x + 52, 88, x + 75, 103), fill=(43, 95, 83, 255))
    image.save(path)


def contract_payload(
    *,
    asset_id: str,
    appearance_path: Path,
    rig_path: Path = RIG,
    registry_path: Path = REGISTRY,
    atlas_path: Path = ATLAS,
    mode: str = "RIGID",
) -> dict[str, object]:
    if mode == "RIGID":
        slot, socket, source_size = "head", "head_shell", [128, 128]
        scale, pivot, source_pivot = [0.625, 0.625], [36, 48], [58, 77]
        layout = {"columns": 1, "rows": 1, "frame_count": 1, "frame_order": "single"}
    else:
        slot, socket, source_size = "torso", "chest_center", [1024, 128]
        scale, pivot, source_pivot = [1.0, 1.0], [0, 0], [0, 0]
        layout = {
            "columns": 8,
            "rows": 1,
            "frame_count": 8,
            "frame_order": "animation_sequence",
        }
    return {
        "schema_version": "gogobro-item-appearance-contract-v2",
        "asset_id": asset_id,
        "character_id": "character.niko:character/niko",
        "animation_id": "walk_down",
        "appearance": {
            "slot": slot,
            "socket": socket,
            "mode": mode,
            "depth": 40,
            "render_scale": scale,
            "rendered_pivot_px": pivot,
            "local_offset_px": [0, 0],
        },
        "pixel_contract": {
            "frame_size_px": [128, 128],
            "source_size_px": source_size,
            "frame_layout": layout,
            "logical_pixel_scale": 2,
            "resampling": "nearest",
            "alpha": "binary",
            "transparent_rgb": "zero",
            "source_pivot_px": source_pivot,
        },
        "source_sha256": {
            "character_rig": sha256(rig_path),
            "asset_registry": sha256(registry_path),
            "character_atlas": sha256(atlas_path),
            "appearance": sha256(appearance_path),
        },
    }


def checker_inputs(
    tmp_path: Path,
    contract_path: Path,
    appearance_path: Path,
    *,
    asset_id: str = "smoke_shell_helmet",
    rig_path: Path = RIG,
    registry_path: Path = REGISTRY,
    atlas_path: Path = ATLAS,
    visual_rubric: Path | None = None,
):
    return CHECKER.Inputs(
        rig=rig_path,
        registry=registry_path,
        asset_id=asset_id,
        contract=contract_path,
        atlas=atlas_path,
        appearance=appearance_path,
        out_dir=tmp_path / "qa",
        visual_rubric=visual_rubric,
    )


def passing_rubric(path: Path) -> None:
    write_json(
        path,
        {
            name: {"score": 2, "evidence": f"reviewed {name}"}
            for name in CHECKER.RUBRIC_DIMENSIONS
        },
    )


def test_rigid_contract_resolves_every_frame_and_cli_writes_all_outputs(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    rubric = tmp_path / "rubric.json"
    out_dir = tmp_path / "qa"
    make_rigid_appearance(appearance)
    write_json(contract, contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance))
    passing_rubric(rubric)

    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--rig",
            str(RIG),
            "--registry",
            str(REGISTRY),
            "--asset-id",
            "smoke_shell_helmet",
            "--contract",
            str(contract),
            "--atlas",
            str(ATLAS),
            "--appearance",
            str(appearance),
            "--visual-rubric",
            str(rubric),
            "--out-dir",
            str(out_dir),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    report = json.loads((out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    assert report["verdict"] == "harmony_pass"
    assert report["rig_gate"]["verdict"] == "rig_pass"
    assert report["rig_gate"]["summary"]["atlas_columns"] == 8
    assert report["rig_gate"]["summary"]["trusted_opaque_contact_coverage"] == 72
    assert report["rig_gate"]["summary"]["trusted_opaque_contact_expected"] == 72
    assert report["rig_gate"]["source_profile"]["verdict"] == "rig_pass"
    assert report["measurements"]["resolved_frame_count"] == 8
    assert [frame["rendered_top_left_px"] for frame in report["measurements"]["frames"]] == [
        [26, 23],
        [26, 23],
        [26, 23],
        [26, 23],
        [28, 23],
        [28, 23],
        [26, 23],
        [26, 23],
    ]
    assert Image.open(out_dir / "harmony-overlay.png").size == (1024, 128)
    assert Image.open(out_dir / "harmony-actual-size.png").size == (1920, 1080)


def test_geometry_pass_stays_review_without_visual_rubric(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(contract, contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance))
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "review"
    assert report["reason_codes"] == ["visual_rubric_required"]


def test_wrong_registry_socket_cannot_be_bypassed(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["socket"] = "forehead"
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert "registry_appearance_mismatch" in report["reason_codes"]


def test_contract_and_registry_cannot_be_changed_to_another_compatible_socket(
    tmp_path: Path,
) -> None:
    registry_path = tmp_path / "registry.json"
    registry_payload = json.loads(REGISTRY.read_text(encoding="utf-8"))
    helmet = next(
        unit for unit in registry_payload["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["appearance"]["socket"] = "forehead"
    write_json(registry_path, registry_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(
        asset_id="smoke_shell_helmet",
        appearance_path=appearance,
        registry_path=registry_path,
    )
    payload["appearance"]["socket"] = "forehead"
    write_json(contract, payload)
    report, _, _ = CHECKER.check(
        checker_inputs(
            tmp_path,
            contract,
            appearance,
            registry_path=registry_path,
        )
    )
    assert report["verdict"] == "hard_fail"
    assert "registry_appearance_mismatch" not in report["reason_codes"]
    assert "trusted_registry_mapping_mismatch" in report["reason_codes"]


def test_self_consistent_socket_shift_cannot_bypass_trusted_rig_hash(tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    profile_path = source_root / "tools/assets/rig_profiles/niko_walk_down_v1.json"
    profile_path.parent.mkdir(parents=True)
    profile_path.write_bytes(SOURCE_PROFILE.read_bytes())
    rig_path = source_root / "game/content/packs/characters/niko/rig/shifted-rig.json"
    rig_path.parent.mkdir(parents=True)
    rig_payload = json.loads(RIG.read_text(encoding="utf-8"))
    for frame in rig_payload["animations"]["walk_down"]["frames"]:
        frame["sockets"]["head_shell"][0] += 1
    write_json(rig_path, rig_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet",
            appearance_path=appearance,
            rig_path=rig_path,
        ),
    )
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, rig_path=rig_path)
    )
    assert report["verdict"] == "hard_fail"
    assert "trusted_rig_hash_mismatch" in report["reason_codes"]


def test_wrong_rendered_pivot_cannot_be_bypassed(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["rendered_pivot_px"] = [37, 48]
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert "pivot_scale_mismatch" in report["reason_codes"]


def test_wrong_mode_cannot_be_bypassed(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["mode"] = "FRAME_OVERLAY"
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert "registry_appearance_mismatch" in report["reason_codes"]
    assert "rig_mode_not_allowed" in report["reason_codes"]


def test_missing_final_rig_socket_cannot_be_hidden_by_valid_hash(tmp_path: Path) -> None:
    rig_path = tmp_path / "rig.json"
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    rig_payload = json.loads(RIG.read_text(encoding="utf-8"))
    del rig_payload["animations"]["walk_down"]["frames"][-1]["sockets"]["head_shell"]
    write_json(rig_path, rig_payload)
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet", appearance_path=appearance, rig_path=rig_path
        ),
    )
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, rig_path=rig_path)
    )
    assert report["verdict"] == "hard_fail"
    assert "rig_frame_coverage_incomplete" in report["reason_codes"]


def test_full_1024_overlay_is_frame_synchronous_and_not_rejected_as_non_128(tmp_path: Path) -> None:
    appearance = tmp_path / "overlay.png"
    contract = tmp_path / "contract.json"
    make_overlay_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="ballistic_liner", appearance_path=appearance, mode="FRAME_OVERLAY"
        ),
    )
    report, overlay, _ = CHECKER.check(
        checker_inputs(
            tmp_path,
            contract,
            appearance,
            asset_id="ballistic_liner",
        )
    )
    assert report["verdict"] == "review"
    assert report["measurements"]["resolved_frame_count"] == 8
    assert [frame["overlay_source_frame_index"] for frame in report["measurements"]["frames"]] == list(
        range(8)
    )
    assert overlay is not None and overlay.size == (1024, 128)


def test_overlay_wrong_size_cannot_be_bypassed(tmp_path: Path) -> None:
    appearance = tmp_path / "wrong-overlay.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(
        asset_id="ballistic_liner", appearance_path=appearance, mode="FRAME_OVERLAY"
    )
    write_json(contract, payload)
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, asset_id="ballistic_liner")
    )
    assert report["verdict"] == "hard_fail"
    assert "appearance_size_mismatch" in report["reason_codes"]
    assert "overlay_layout_mismatch" in report["reason_codes"]


def test_rig_atlas_contract_and_profile_cannot_be_shrunk_together(tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    profile_path = source_root / "tools/assets/rig_profiles/niko_walk_down_v1.json"
    profile_path.parent.mkdir(parents=True)
    profile_path.write_bytes(SOURCE_PROFILE.read_bytes())
    atlas_path = source_root / "seven-frame-atlas.png"
    with Image.open(ATLAS) as source_atlas:
        source_atlas.crop((0, 0, 128 * 7, 128)).save(atlas_path)
    malicious_profile = json.loads(profile_path.read_text(encoding="utf-8"))
    malicious_profile["atlas_size"] = [128 * 7, 128]
    malicious_profile["character_atlas_sha256"] = sha256(atlas_path)
    malicious_profile["frames"].pop()
    write_json(profile_path, malicious_profile)
    rig_path = source_root / "game/content/packs/characters/niko/rig/seven-frame-rig.json"
    rig_path.parent.mkdir(parents=True)
    rig_payload = json.loads(RIG.read_text(encoding="utf-8"))
    rig_payload["atlas"]["atlas_size"] = [128 * 7, 128]
    rig_payload["atlas"]["sha256"] = sha256(atlas_path)
    rig_payload["animations"]["walk_down"]["frame_count"] = 7
    rig_payload["animations"]["walk_down"]["frames"].pop()
    write_json(rig_path, rig_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet",
            appearance_path=appearance,
            rig_path=rig_path,
            atlas_path=atlas_path,
        ),
    )
    report, _, _ = CHECKER.check(
        checker_inputs(
            tmp_path,
            contract,
            appearance,
            rig_path=rig_path,
            atlas_path=atlas_path,
        )
    )
    assert report["verdict"] == "hard_fail"
    assert "source_profile_hash_mismatch" in report["reason_codes"]
    assert "trusted_frame_count_mismatch" in report["reason_codes"]
    assert "trusted_atlas_size_mismatch" in report["reason_codes"]
    assert "trusted_atlas_hash_mismatch" in report["reason_codes"]
    assert report["rig_gate"]["verdict"] == "hard_fail"
    assert set(report["rig_gate"]["source_profile"]["reason_codes"]) <= set(
        report["rig_gate"]["reason_codes"]
    )


def test_output_path_cannot_overwrite_an_input_source(tmp_path: Path) -> None:
    out_dir = tmp_path / "qa"
    out_dir.mkdir()
    appearance = out_dir / "harmony-overlay.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(contract, contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance))
    inputs = checker_inputs(tmp_path, contract, appearance)
    report, overlay, preview = CHECKER.check(inputs)
    assert report["verdict"] == "hard_fail"
    assert report["reason_codes"] == ["output_source_collision"]
    assert overlay is None and preview is None
    original_hash = contract_payload(
        asset_id="smoke_shell_helmet", appearance_path=appearance
    )["source_sha256"]["appearance"]
    assert sha256(appearance) == original_hash

    result = subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--rig",
            str(RIG),
            "--registry",
            str(REGISTRY),
            "--asset-id",
            "smoke_shell_helmet",
            "--contract",
            str(contract),
            "--atlas",
            str(ATLAS),
            "--appearance",
            str(appearance),
            "--out-dir",
            str(out_dir),
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 2
    assert "output_source_collision" in result.stdout
    assert sha256(appearance) == original_hash
    assert not (out_dir / "harmony-report.json").exists()


def test_output_path_cannot_overwrite_rig_source_profile(tmp_path: Path) -> None:
    source_root = tmp_path / "source-root"
    out_dir = source_root / "qa"
    out_dir.mkdir(parents=True)
    profile_path = out_dir / "harmony-report.json"
    profile_path.write_bytes(SOURCE_PROFILE.read_bytes())
    original_profile_hash = sha256(profile_path)
    rig_path = source_root / "game/content/packs/characters/niko/rig/redirected-rig.json"
    rig_path.parent.mkdir(parents=True)
    rig_payload = json.loads(RIG.read_text(encoding="utf-8"))
    rig_payload["source_profile"] = "qa/harmony-report.json"
    write_json(rig_path, rig_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet",
            appearance_path=appearance,
            rig_path=rig_path,
        ),
    )
    inputs = checker_inputs(tmp_path, contract, appearance, rig_path=rig_path)
    report, _, _ = CHECKER.check(
        CHECKER.Inputs(
            rig=inputs.rig,
            registry=inputs.registry,
            asset_id=inputs.asset_id,
            contract=inputs.contract,
            atlas=inputs.atlas,
            appearance=inputs.appearance,
            out_dir=out_dir,
        )
    )
    assert report["verdict"] == "hard_fail"
    assert report["reason_codes"] == ["output_source_collision"]
    assert sha256(profile_path) == original_profile_hash


def test_existing_fixed_output_blocks_reuse_instead_of_leaving_stale_images(
    tmp_path: Path,
) -> None:
    out_dir = tmp_path / "qa"
    out_dir.mkdir()
    stale_overlay = out_dir / "harmony-overlay.png"
    stale_overlay.write_bytes(b"stale-pass-image")
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(contract, contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance))
    inputs = checker_inputs(tmp_path, contract, appearance)
    report, _, _ = CHECKER.check(inputs)
    assert report["verdict"] == "hard_fail"
    assert report["reason_codes"] == ["output_dir_not_clean"]
    assert stale_overlay.read_bytes() == b"stale-pass-image"


def test_frame_overlay_rejects_non_identity_scale(tmp_path: Path) -> None:
    appearance = tmp_path / "overlay.png"
    contract = tmp_path / "contract.json"
    make_overlay_appearance(appearance)
    payload = contract_payload(
        asset_id="ballistic_liner", appearance_path=appearance, mode="FRAME_OVERLAY"
    )
    payload["appearance"]["render_scale"] = [0.5, 1.0]
    write_json(contract, payload)
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, asset_id="ballistic_liner")
    )
    assert report["verdict"] == "hard_fail"
    assert "overlay_scale_must_be_one" in report["reason_codes"]


def test_source_and_rendered_pivots_must_be_inside_their_frames(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["pixel_contract"]["source_pivot_px"] = [128, 77]
    payload["appearance"]["rendered_pivot_px"] = [80, 48]
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert "source_pivot_out_of_bounds" in report["reason_codes"]
    assert "rendered_pivot_out_of_bounds" in report["reason_codes"]


def test_rendered_pivot_out_of_bounds_is_not_hidden_by_source_pivot(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["rendered_pivot_px"] = [80, 48]
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert "pivot_scale_mismatch" in report["reason_codes"]
    assert "rendered_pivot_out_of_bounds" in report["reason_codes"]


def test_unknown_or_extra_contract_fields_are_rejected(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["legacy_offsets"] = [[0, 0]] * 8
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert report["reason_codes"] == ["invalid_appearance_contract"]
    assert report["source_integrity"]["after"]
    assert report["source_integrity"]["changed"] == []


def test_malformed_animation_container_returns_report_instead_of_traceback(
    tmp_path: Path,
) -> None:
    rig_path = tmp_path / "rig.json"
    rig_payload = json.loads(RIG.read_text(encoding="utf-8"))
    rig_payload["animations"] = []
    write_json(rig_path, rig_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet",
            appearance_path=appearance,
            rig_path=rig_path,
        ),
    )
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, rig_path=rig_path)
    )
    assert report["verdict"] == "hard_fail"
    assert "trusted_rig_hash_mismatch" in report["reason_codes"]


def test_extreme_finite_render_scale_is_rejected_without_overflow(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    payload = contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance)
    payload["appearance"]["render_scale"] = [1e308, 1e308]
    write_json(contract, payload)
    report, _, _ = CHECKER.check(checker_inputs(tmp_path, contract, appearance))
    assert report["verdict"] == "hard_fail"
    assert report["reason_codes"] == ["invalid_appearance_contract"]


def test_registry_mapping_is_type_exact(tmp_path: Path) -> None:
    registry_path = tmp_path / "registry.json"
    registry_payload = json.loads(REGISTRY.read_text(encoding="utf-8"))
    unit = next(unit for unit in registry_payload["units"] if unit["asset_id"] == "smoke_shell_helmet")
    unit["appearance"]["depth"] = "40"
    write_json(registry_path, registry_payload)
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    make_rigid_appearance(appearance)
    write_json(
        contract,
        contract_payload(
            asset_id="smoke_shell_helmet",
            appearance_path=appearance,
            registry_path=registry_path,
        ),
    )
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, registry_path=registry_path)
    )
    assert report["verdict"] == "hard_fail"
    assert "registry_appearance_mismatch" in report["reason_codes"]


def test_malformed_visual_rubric_is_a_hard_failure(tmp_path: Path) -> None:
    appearance = tmp_path / "appearance.png"
    contract = tmp_path / "contract.json"
    rubric = tmp_path / "rubric.json"
    make_rigid_appearance(appearance)
    write_json(contract, contract_payload(asset_id="smoke_shell_helmet", appearance_path=appearance))
    passing_rubric(rubric)
    payload = json.loads(rubric.read_text(encoding="utf-8"))
    payload["identity"]["score"] = True
    write_json(rubric, payload)
    report, _, _ = CHECKER.check(
        checker_inputs(tmp_path, contract, appearance, visual_rubric=rubric)
    )
    assert report["verdict"] == "hard_fail"
    assert "malformed_visual_rubric" in report["reason_codes"]
