from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import types
from pathlib import Path

from PIL import Image, ImageDraw


SKILL_ROOT = Path(__file__).parents[1]
TRUST_CATALOG = "references/trusted-character-animation-bindings-v1.json"
CHARACTER_ID = "character.synthetic:character/aria"
TOPOLOGY = {
    "clothes_body": ("clothes", ["FRAME_OVERLAY"], 20),
    "shoulder_left": ("arm_left", ["RIGID", "FRAME_OVERLAY"], 50),
    "upper_arm_left": ("arm_left", ["RIGID", "FRAME_OVERLAY"], 50),
    "forearm_left": ("arm_left", ["RIGID", "FRAME_OVERLAY"], 50),
    "hand_left": ("arm_left", ["RIGID", "FRAME_OVERLAY"], 50),
    "shoulder_right": ("arm_right", ["RIGID", "FRAME_OVERLAY"], 50),
    "upper_arm_right": ("arm_right", ["RIGID", "FRAME_OVERLAY"], 50),
    "forearm_right": ("arm_right", ["RIGID", "FRAME_OVERLAY"], 50),
    "hand_right": ("arm_right", ["RIGID", "FRAME_OVERLAY"], 50),
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _registry_digest(registry: dict[str, object]) -> tuple[str, int]:
    rows = []
    for unit in registry["units"]:
        if unit["category"] != "item":
            continue
        if "appearance" not in unit:
            continue
        rows.append(
            {
                "asset_id": unit["asset_id"],
                "appearance": {
                    name: unit["appearance"][name]
                    for name in ("slot", "socket", "mode", "depth")
                },
            }
        )
    canonical = json.dumps(
        sorted(rows, key=lambda row: row["asset_id"]),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest(), len(rows)


def _make_atlas(path: Path, frame_count: int) -> None:
    image = Image.new("RGBA", (64 * frame_count, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for index in range(frame_count):
        x = index * 64
        draw.rectangle((x + 16, 8, x + 47, 55), fill=(117, 72, 49, 255))
        draw.rectangle((x + 24, 16, x + 39, 39), fill=(226, 158, 111, 255))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def _make_appearance(path: Path, mode: str, frame_count: int) -> None:
    width = 64 if mode == "RIGID" else 64 * frame_count
    image = Image.new("RGBA", (width, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    source_frames = 1 if mode == "RIGID" else frame_count
    for index in range(source_frames):
        x = index * 64
        draw.rectangle((x + 8, 8, x + 23, 23), fill=(48, 92, 84, 255))
    image.save(path)


def _registry() -> dict[str, object]:
    return {
        "schema_version": "synthetic-static-assets-v1",
        "units": [
            {
                "asset_id": "synthetic_glove",
                "category": "item",
                "appearance": {
                    "slot": "arm_right",
                    "socket": "hand_right",
                    "mode": "RIGID",
                    "depth": 50,
                },
            },
            {
                "asset_id": "synthetic_clothes",
                "category": "item",
                "appearance": {
                    "slot": "clothes",
                    "socket": "clothes_body",
                    "mode": "FRAME_OVERLAY",
                    "depth": 20,
                },
            },
            {
                "asset_id": "synthetic_passive_without_visual",
                "category": "item",
            },
        ],
    }


def _build_animation(project: Path, animation_id: str, frame_count: int) -> dict[str, object]:
    atlas_path = project / f"assets/{animation_id}.png"
    profile_relative = f"tools/assets/rig_profiles/aria_{animation_id}.json"
    profile_path = project / profile_relative
    rig_path = project / f"game/characters/aria/{animation_id}-rig.json"
    _make_atlas(atlas_path, frame_count)
    _write_json(
        profile_path,
        {
            "schema_version": "gogobro-rig-profile-v1",
            "character_atlas_sha256": _sha256(atlas_path),
            "frame_size": [64, 64],
            "atlas_size": [64 * frame_count, 64],
            "frames": [
                {
                    "frame_index": index,
                    "attachment_regions": {"body": [0, 0, 64, 64]},
                    "face_roi": [16, 8, 48, 32],
                    "protected_regions": {"face": [16, 8, 48, 32]},
                }
                for index in range(frame_count)
            ],
        },
    )
    socket_catalog = {
        socket: {
            "slot_id": slot,
            "allowed_modes": modes,
            "default_depth": depth,
            "reference_region": "body",
            "flip_h": False,
            "max_residual_jitter_px": 0,
        }
        for socket, (slot, modes, depth) in TOPOLOGY.items()
    }
    frames = [
        {
            "frame_index": index,
            "frame_name": f"{animation_id}_{index + 1:02d}",
            "regions": {
                "body": [0, 0, 64, 64],
                "face": [16, 8, 48, 32],
            },
            "protected_regions": {"face": [16, 8, 48, 32]},
            "sockets": {socket: [32, 32] for socket in TOPOLOGY},
        }
        for index in range(frame_count)
    ]
    rig = {
        "schema_version": "gogobro-character-attachment-rig-v2",
        "rig_id": f"aria_{animation_id}_attachment_v2",
        "character_id": CHARACTER_ID,
        "source_profile": profile_relative,
        "atlas": {
            "path": f"res://assets/{animation_id}.png",
            "sha256": _sha256(atlas_path),
            "frame_size": [64, 64],
            "atlas_size": [64 * frame_count, 64],
        },
        "socket_catalog": socket_catalog,
        "animations": {
            animation_id: {
                "row": 0,
                "frame_count": frame_count,
                "fps": 8,
                "frames": frames,
            }
        },
    }
    _write_json(rig_path, rig)
    return {
        "animation_id": animation_id,
        "frame_count": frame_count,
        "atlas": atlas_path,
        "profile": profile_path,
        "rig": rig_path,
        "binding": {
            "rig_id": rig["rig_id"],
            "rig_sha256": _sha256(rig_path),
            "source_profile": {
                "relative_path": profile_relative,
                "schema_version": "gogobro-rig-profile-v1",
                "sha256": _sha256(profile_path),
            },
            "atlas": {
                "sha256": _sha256(atlas_path),
                "frame_size": [64, 64],
                "atlas_size": [64 * frame_count, 64],
                "grid": {"columns": frame_count, "rows": 1, "row": 0},
            },
            "frame_count": frame_count,
            "fps": 8,
        },
    }


def _fixture(tmp_path: Path) -> dict[str, object]:
    skill = tmp_path / "skill"
    shutil.copytree(SKILL_ROOT, skill)
    project = tmp_path / "project"
    registry_path = project / "registry.json"
    registry = _registry()
    _write_json(registry_path, registry)
    animations = {
        spec["animation_id"]: spec
        for spec in (
            _build_animation(project, "idle_down", 5),
            _build_animation(project, "wave_down", 3),
        )
    }
    digest, item_count = _registry_digest(registry)
    catalog_path = skill / TRUST_CATALOG
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["characters"]["character.niko:character/niko"]["playable"] = False
    catalog["characters"][CHARACTER_ID] = {
        "playable": True,
        "profile_kind": "humanoid_v1",
        "registry": {
            "schema_version": registry["schema_version"],
            "item_count": item_count,
            "mapping_sha256": digest,
        },
        "animations": {
            animation_id: spec["binding"] for animation_id, spec in animations.items()
        },
    }
    _write_json(catalog_path, catalog)
    return {
        "skill": skill,
        "project": project,
        "registry": registry_path,
        "animations": animations,
    }


def _contract(
    fixture: dict[str, object],
    animation_id: str,
    asset_id: str,
    appearance_path: Path,
) -> dict[str, object]:
    spec = fixture["animations"][animation_id]
    frame_count = spec["frame_count"]
    mode = "RIGID" if asset_id == "synthetic_glove" else "FRAME_OVERLAY"
    if mode == "RIGID":
        slot, socket, depth = "arm_right", "hand_right", 50
        scale, pivot, source_pivot = [1, 1], [16, 16], [16, 16]
        layout = {"columns": 1, "rows": 1, "frame_count": 1, "frame_order": "single"}
        source_size = [64, 64]
    else:
        slot, socket, depth = "clothes", "clothes_body", 20
        scale, pivot, source_pivot = [1, 1], [0, 0], [0, 0]
        layout = {
            "columns": frame_count,
            "rows": 1,
            "frame_count": frame_count,
            "frame_order": "animation_sequence",
        }
        source_size = [64 * frame_count, 64]
    return {
        "schema_version": "gogobro-item-appearance-contract-v2",
        "asset_id": asset_id,
        "character_id": CHARACTER_ID,
        "animation_id": animation_id,
        "appearance": {
            "slot": slot,
            "socket": socket,
            "mode": mode,
            "depth": depth,
            "render_scale": scale,
            "rendered_pivot_px": pivot,
            "local_offset_px": [0, 0],
        },
        "pixel_contract": {
            "frame_size_px": [64, 64],
            "source_size_px": source_size,
            "frame_layout": layout,
            "logical_pixel_scale": 2,
            "resampling": "nearest",
            "alpha": "binary",
            "transparent_rgb": "zero",
            "source_pivot_px": source_pivot,
        },
        "source_sha256": {
            "character_rig": _sha256(spec["rig"]),
            "asset_registry": _sha256(fixture["registry"]),
            "character_atlas": _sha256(spec["atlas"]),
            "appearance": _sha256(appearance_path),
        },
    }


def _run_item_checker(
    fixture: dict[str, object],
    animation_id: str,
    asset_id: str,
    root: Path,
    *,
    rubric: bool = False,
) -> tuple[subprocess.CompletedProcess[str], dict[str, object], Path, Path]:
    spec = fixture["animations"][animation_id]
    mode = "RIGID" if asset_id == "synthetic_glove" else "FRAME_OVERLAY"
    appearance = root / "appearance.png"
    contract = root / "contract.json"
    out_dir = root / "qa"
    root.mkdir(parents=True, exist_ok=True)
    _make_appearance(appearance, mode, spec["frame_count"])
    _write_json(contract, _contract(fixture, animation_id, asset_id, appearance))
    command = [
        sys.executable,
        str(fixture["skill"] / "scripts/check_item_socket_harmony_v2.py"),
        "--rig",
        str(spec["rig"]),
        "--registry",
        str(fixture["registry"]),
        "--asset-id",
        asset_id,
        "--contract",
        str(contract),
        "--atlas",
        str(spec["atlas"]),
        "--appearance",
        str(appearance),
        "--out-dir",
        str(out_dir),
    ]
    if rubric:
        rubric_path = root / "rubric.json"
        _write_json(
            rubric_path,
            {
                name: {"score": 2, "evidence": f"synthetic {name} review"}
                for name in ("identity", "function", "material", "hierarchy", "originality")
            },
        )
        command.extend(["--visual-rubric", str(rubric_path)])
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    report = json.loads((out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    return result, report, contract, out_dir / "harmony-report.json"


def test_checker_supports_a_second_character_with_independent_animation_counts(
    tmp_path: Path,
) -> None:
    fixture = _fixture(tmp_path)
    for animation_id, expected_count in (("idle_down", 5), ("wave_down", 3)):
        result, report, _, _ = _run_item_checker(
            fixture,
            animation_id,
            "synthetic_glove",
            tmp_path / f"check-{animation_id}",
        )
        assert result.returncode == 0, result.stdout + result.stderr
        assert report["verdict"] == "review"
        assert report["rig_gate"]["verdict"] == "rig_pass"
        assert report["rig_gate"]["trusted_sources"]["profile_kind"] == "humanoid_v1"
        assert report["measurements"]["resolved_frame_count"] == expected_count


def test_synchronized_atlas_profile_and_rig_truncation_cannot_self_sign(
    tmp_path: Path,
) -> None:
    fixture = _fixture(tmp_path)
    spec = fixture["animations"]["idle_down"]
    with Image.open(spec["atlas"]) as opened:
        opened.crop((0, 0, 64 * 4, 64)).save(spec["atlas"])
    profile = json.loads(spec["profile"].read_text(encoding="utf-8"))
    profile["atlas_size"] = [64 * 4, 64]
    profile["character_atlas_sha256"] = _sha256(spec["atlas"])
    profile["frames"].pop()
    _write_json(spec["profile"], profile)
    rig = json.loads(spec["rig"].read_text(encoding="utf-8"))
    rig["atlas"]["atlas_size"] = [64 * 4, 64]
    rig["atlas"]["sha256"] = _sha256(spec["atlas"])
    rig["animations"]["idle_down"]["frame_count"] = 4
    rig["animations"]["idle_down"]["frames"].pop()
    _write_json(spec["rig"], rig)

    result, report, _, _ = _run_item_checker(
        fixture,
        "idle_down",
        "synthetic_glove",
        tmp_path / "truncated",
    )
    assert result.returncode == 2
    assert {
        "trusted_rig_hash_mismatch",
        "source_profile_hash_mismatch",
        "trusted_atlas_hash_mismatch",
        "trusted_frame_count_mismatch",
    } <= set(report["reason_codes"])


def test_registry_and_contract_socket_swap_cannot_self_sign(tmp_path: Path) -> None:
    fixture = _fixture(tmp_path)
    registry = json.loads(fixture["registry"].read_text(encoding="utf-8"))
    glove = next(unit for unit in registry["units"] if unit["asset_id"] == "synthetic_glove")
    glove["appearance"]["socket"] = "shoulder_right"
    _write_json(fixture["registry"], registry)
    root = tmp_path / "socket-swap"
    spec = fixture["animations"]["idle_down"]
    appearance = root / "appearance.png"
    contract_path = root / "contract.json"
    root.mkdir()
    _make_appearance(appearance, "RIGID", spec["frame_count"])
    contract = _contract(fixture, "idle_down", "synthetic_glove", appearance)
    contract["appearance"]["socket"] = "shoulder_right"
    _write_json(contract_path, contract)
    out_dir = root / "qa"
    result = subprocess.run(
        [
            sys.executable,
            str(fixture["skill"] / "scripts/check_item_socket_harmony_v2.py"),
            "--rig",
            str(spec["rig"]),
            "--registry",
            str(fixture["registry"]),
            "--asset-id",
            "synthetic_glove",
            "--contract",
            str(contract_path),
            "--atlas",
            str(spec["atlas"]),
            "--appearance",
            str(appearance),
            "--out-dir",
            str(out_dir),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    report = json.loads((out_dir / "harmony-report.json").read_text(encoding="utf-8"))
    assert result.returncode == 2
    assert "registry_appearance_mismatch" not in report["reason_codes"]
    assert "trusted_registry_mapping_mismatch" in report["reason_codes"]


def test_absent_appearance_is_nonwearable_but_present_malformed_appearance_fails(
    tmp_path: Path,
) -> None:
    fixture = _fixture(tmp_path)
    result, report, _, _ = _run_item_checker(
        fixture,
        "idle_down",
        "synthetic_glove",
        tmp_path / "nonwearable-passive",
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert report["rig_gate"]["summary"]["registry_item_count"] == 2

    registry = json.loads(fixture["registry"].read_text(encoding="utf-8"))
    passive = next(
        unit
        for unit in registry["units"]
        if unit["asset_id"] == "synthetic_passive_without_visual"
    )
    passive["appearance"] = None
    _write_json(fixture["registry"], registry)
    malformed, malformed_report, _, _ = _run_item_checker(
        fixture,
        "idle_down",
        "synthetic_glove",
        tmp_path / "malformed-visible-item",
    )
    assert malformed.returncode == 2
    assert "character_rig_gate_failed" in malformed_report["reason_codes"]
    assert "trusted_registry_mapping_mismatch" in malformed_report["reason_codes"]


def test_trusted_animation_ids_must_exactly_match_every_animation_in_the_rig(
    tmp_path: Path,
) -> None:
    fixture = _fixture(tmp_path)
    spec = fixture["animations"]["idle_down"]
    with Image.open(spec["atlas"]) as opened:
        source = opened.convert("RGBA")
    expanded = Image.new("RGBA", (source.width, source.height * 2), (0, 0, 0, 0))
    expanded.alpha_composite(source, (0, 0))
    expanded.alpha_composite(source, (0, source.height))
    expanded.save(spec["atlas"])

    profile = json.loads(spec["profile"].read_text(encoding="utf-8"))
    profile["atlas_size"] = [source.width, source.height * 2]
    profile["character_atlas_sha256"] = _sha256(spec["atlas"])
    _write_json(spec["profile"], profile)

    rig = json.loads(spec["rig"].read_text(encoding="utf-8"))
    rig["atlas"]["atlas_size"] = [source.width, source.height * 2]
    rig["atlas"]["sha256"] = _sha256(spec["atlas"])
    extra = json.loads(json.dumps(rig["animations"]["idle_down"]))
    extra["row"] = 1
    for index, frame in enumerate(extra["frames"]):
        frame["frame_name"] = f"untrusted_extra_{index + 1:02d}"
    rig["animations"]["untrusted_extra"] = extra
    _write_json(spec["rig"], rig)

    catalog_path = fixture["skill"] / TRUST_CATALOG
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    character = catalog["characters"][CHARACTER_ID]
    idle = character["animations"]["idle_down"]
    idle["rig_sha256"] = _sha256(spec["rig"])
    idle["source_profile"]["sha256"] = _sha256(spec["profile"])
    idle["atlas"]["sha256"] = _sha256(spec["atlas"])
    idle["atlas"]["atlas_size"] = [source.width, source.height * 2]
    idle["atlas"]["grid"] = {"columns": 5, "rows": 2, "row": 0}
    phantom = json.loads(json.dumps(idle))
    phantom["atlas"]["grid"]["row"] = 1
    character["animations"]["trusted_missing"] = phantom
    _write_json(catalog_path, catalog)

    result, report, _, _ = _run_item_checker(
        fixture,
        "idle_down",
        "synthetic_glove",
        tmp_path / "unregistered-animation",
    )
    assert result.returncode == 2
    assert report["rig_gate"]["summary"]["animation_count"] == 2
    assert "trusted_animation_set_mismatch" in report["rig_gate"]["reason_codes"]
    assert "trusted_animation_set_mismatch" in report["reason_codes"]


def test_caller_cannot_supply_a_replacement_trust_catalog(tmp_path: Path) -> None:
    fixture = _fixture(tmp_path)
    script = fixture["skill"] / "scripts/check_item_socket_harmony_v2.py"
    spec = fixture["animations"]["idle_down"]
    root = tmp_path / "replacement-catalog"
    root.mkdir()
    appearance = root / "appearance.png"
    contract = root / "contract.json"
    _make_appearance(appearance, "RIGID", spec["frame_count"])
    _write_json(contract, _contract(fixture, "idle_down", "synthetic_glove", appearance))
    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--rig",
            str(spec["rig"]),
            "--registry",
            str(fixture["registry"]),
            "--asset-id",
            "synthetic_glove",
            "--contract",
            str(contract),
            "--atlas",
            str(spec["atlas"]),
            "--appearance",
            str(appearance),
            "--out-dir",
            str(root / "qa"),
            "--trusted-catalog",
            str(tmp_path / "self-signed.json"),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 2
    assert "unrecognized arguments: --trusted-catalog" in result.stderr


def test_fixed_path_loader_overwrites_sys_modules_preinjection(tmp_path: Path) -> None:
    fixture = _fixture(tmp_path)
    checker_path = fixture["skill"] / "scripts/check_item_socket_harmony_v2.py"
    module_spec = importlib.util.spec_from_file_location(
        "synthetic_item_checker_for_injection_test", checker_path
    )
    assert module_spec is not None and module_spec.loader is not None
    checker = importlib.util.module_from_spec(module_spec)
    sys.modules[module_spec.name] = checker
    module_spec.loader.exec_module(checker)

    malicious = types.ModuleType("_gogobro_trusted_character_bindings")
    malicious.__file__ = str(
        fixture["skill"] / "scripts/trusted_character_bindings.py"
    )
    malicious.load_trusted_bindings = lambda: {"self_signed": True}
    sys.modules[malicious.__name__] = malicious

    loaded = checker._load_trust_module()

    assert loaded is not malicious
    assert not hasattr(loaded, "self_signed")
    assert loaded.load_trusted_bindings()["schema_version"] == (
        "gogobro-trusted-character-animation-bindings-v1"
    )


def test_release_matrix_requires_every_character_item_animation_tuple(
    tmp_path: Path,
) -> None:
    fixture = _fixture(tmp_path)
    matrix_root = tmp_path
    artifact_root = matrix_root / "matrix-artifacts"
    entries = []
    for animation_id in ("idle_down", "wave_down"):
        for asset_id in ("synthetic_glove", "synthetic_clothes"):
            root = artifact_root / f"{animation_id}-{asset_id}"
            result, report, contract, harmony_report = _run_item_checker(
                fixture, animation_id, asset_id, root, rubric=True
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert report["verdict"] == "harmony_pass"
            entries.append(
                {
                    "character_id": CHARACTER_ID,
                    "animation_id": animation_id,
                    "asset_id": asset_id,
                    "contract": contract.relative_to(matrix_root).as_posix(),
                    "harmony_report": harmony_report.relative_to(matrix_root).as_posix(),
                    "rig": fixture["animations"][animation_id]["rig"]
                    .relative_to(matrix_root)
                    .as_posix(),
                    "atlas": fixture["animations"][animation_id]["atlas"]
                    .relative_to(matrix_root)
                    .as_posix(),
                    "appearance": (root / "appearance.png")
                    .relative_to(matrix_root)
                    .as_posix(),
                    "visual_rubric": (root / "rubric.json")
                    .relative_to(matrix_root)
                    .as_posix(),
                }
            )
    matrix_path = matrix_root / "appearance-matrix.json"
    _write_json(
        matrix_path,
        {
            "schema_version": "gogobro-character-item-appearance-matrix-v1",
            "entries": entries,
        },
    )
    script = fixture["skill"] / "scripts/check_character_item_appearance_matrix.py"
    passed_out = matrix_root / "matrix-pass"
    passed = subprocess.run(
        [
            sys.executable,
            str(script),
            "--matrix",
            str(matrix_path),
            "--registry",
            str(fixture["registry"]),
            "--out-dir",
            str(passed_out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert passed.returncode == 0, passed.stdout + passed.stderr
    report = json.loads(
        (passed_out / "appearance-matrix-report.json").read_text(encoding="utf-8")
    )
    assert report["verdict"] == "matrix_pass"
    assert report["expected_count"] == 4
    assert report["rechecked_count"] == 4

    incomplete = json.loads(matrix_path.read_text(encoding="utf-8"))
    incomplete["entries"].pop()
    incomplete_path = matrix_root / "appearance-matrix-incomplete.json"
    _write_json(incomplete_path, incomplete)
    failed_out = matrix_root / "matrix-fail"
    failed = subprocess.run(
        [
            sys.executable,
            str(script),
            "--matrix",
            str(incomplete_path),
            "--registry",
            str(fixture["registry"]),
            "--out-dir",
            str(failed_out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    failed_report = json.loads(
        (failed_out / "appearance-matrix-report.json").read_text(encoding="utf-8")
    )
    assert failed.returncode == 2
    assert failed_report["verdict"] == "hard_fail"
    assert "appearance_matrix_incomplete" in failed_report["reason_codes"]

    forged = json.loads(matrix_path.read_text(encoding="utf-8"))
    forged_path = artifact_root / "forged-harmony-report.json"
    forged_report = {
        "schema_version": "gogobro-item-socket-harmony-report-v2",
        "verdict": "harmony_pass",
        "asset_id": forged["entries"][0]["asset_id"],
        "character_id": CHARACTER_ID,
        "animation_id": forged["entries"][0]["animation_id"],
        "trusted_catalog_sha256": report["trusted_catalog_sha256"],
        "input_sha256": {
            "appearance_contract": _sha256(
                matrix_root / forged["entries"][0]["contract"]
            )
        },
        "source_integrity": {"changed": []},
    }
    _write_json(forged_path, forged_report)
    forged["entries"][0]["harmony_report"] = forged_path.relative_to(
        matrix_root
    ).as_posix()
    forged_matrix = matrix_root / "appearance-matrix-forged.json"
    _write_json(forged_matrix, forged)
    forged_out = matrix_root / "matrix-forged"
    forged_result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--matrix",
            str(forged_matrix),
            "--registry",
            str(fixture["registry"]),
            "--out-dir",
            str(forged_out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    forged_gate = json.loads(
        (forged_out / "appearance-matrix-report.json").read_text(encoding="utf-8")
    )
    assert forged_result.returncode == 2
    assert "matrix_harmony_report_invalid" in forged_gate["reason_codes"]

    type_confused = json.loads(matrix_path.read_text(encoding="utf-8"))
    original_report_path = matrix_root / type_confused["entries"][0][
        "harmony_report"
    ]
    type_confused_report = json.loads(
        original_report_path.read_text(encoding="utf-8")
    )
    type_confused_report["rig_gate"]["summary"]["animation_count"] = True
    type_confused_report_path = artifact_root / "type-confused-report.json"
    _write_json(type_confused_report_path, type_confused_report)
    type_confused["entries"][0]["harmony_report"] = (
        type_confused_report_path.relative_to(matrix_root).as_posix()
    )
    type_confused_matrix = matrix_root / "appearance-matrix-type-confused.json"
    _write_json(type_confused_matrix, type_confused)
    type_confused_out = matrix_root / "matrix-type-confused"
    type_confused_result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--matrix",
            str(type_confused_matrix),
            "--registry",
            str(fixture["registry"]),
            "--out-dir",
            str(type_confused_out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    type_confused_gate = json.loads(
        (type_confused_out / "appearance-matrix-report.json").read_text(
            encoding="utf-8"
        )
    )
    assert type_confused_result.returncode == 2
    assert "matrix_harmony_report_invalid" in type_confused_gate["reason_codes"]

    stale_registry = matrix_root / "stale-registry.json"
    stale_payload = json.loads(fixture["registry"].read_text(encoding="utf-8"))
    stale_payload["units"][0]["non_appearance_metadata"] = "changed"
    _write_json(stale_registry, stale_payload)
    stale_out = matrix_root / "matrix-stale-registry"
    stale_result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--matrix",
            str(matrix_path),
            "--registry",
            str(stale_registry),
            "--out-dir",
            str(stale_out),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    stale_gate = json.loads(
        (stale_out / "appearance-matrix-report.json").read_text(encoding="utf-8")
    )
    assert stale_result.returncode == 2
    assert "matrix_harmony_recheck_failed" in stale_gate["reason_codes"]
