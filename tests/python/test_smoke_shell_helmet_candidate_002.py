from __future__ import annotations

import copy
import hashlib
import json
import shutil
import threading
from dataclasses import replace
from pathlib import Path

import pytest
from PIL import Image, ImageDraw, ImageFont

import tools.assets.build_smoke_shell_helmet_candidate_002 as builder

from tools.assets.build_smoke_shell_helmet_candidate_002 import (
    BuildInputs,
    _load_checker,
    build_candidate_002,
)


REPO_ROOT = Path(__file__).resolve().parents[2]
CANDIDATE_001 = Path(
    "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
    "smoke_shell_helmet/candidate-001"
)
APPEARANCE_SOURCE = (
    CANDIDATE_001 / "cleaned/smoke-shell-helmet-appearance-128.png"
)
NIKO_ATLAS = (
    REPO_ROOT
    / "game/content/packs/characters/niko/animations/walk_down/sprite-sheet-alpha.png"
)
RIG_PROFILE = REPO_ROOT / "tools/assets/rig_profiles/niko_walk_down_v1.json"
REGISTRY = REPO_ROOT / "game/content/assets/gogobro_static_assets_v1.json"
LOCKED_NIKO_HASH = "fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d"
EXPECTED_ARTIFACTS = {
    "appearance/anchors-walk-down.json",
    "derived/appearance-128.png",
    "derived/icon-256.png",
    "qa/approval-card.png",
    "qa/composite-atlas-8x128.png",
    "qa/composite-frame-001.png",
    "qa/harmony-actual-size.png",
    "qa/harmony-overlay.png",
    "qa/harmony-report.json",
    "qa/pixel-qa-report.json",
    "qa/runtime-size-1920x1080.png",
    "qa/visual-rubric.json",
}
EXPECTED_REVIEW_FOOTER = (
    "REVIEW EVIDENCE ONLY — no curated, runtime, or startup integration"
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def review_registry_payload() -> dict[str, object]:
    registry = json.loads(REGISTRY.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["approval_status"] = "review"
    helmet.pop("approval_history", None)
    return registry


def write_review_registry(path: Path) -> None:
    path.write_text(
        json.dumps(
            review_registry_payload(),
            ensure_ascii=False,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )


def inputs(output_root: Path) -> BuildInputs:
    registry = output_root.parent / f".{output_root.name}-review-registry.json"
    if not registry.exists():
        write_review_registry(registry)
    return BuildInputs(
        appearance_source=APPEARANCE_SOURCE,
        niko_atlas=NIKO_ATLAS,
        rig_profile=RIG_PROFILE,
        registry=registry,
        output_root=output_root,
    )


def rgba(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return opened.convert("RGBA")


def assert_pixel_contract(image: Image.Image) -> None:
    pixels = list(image.get_flattened_data())
    assert {pixel[3] for pixel in pixels} <= {0, 255}
    assert all(pixel[:3] == (0, 0, 0) for pixel in pixels if pixel[3] == 0)


def assert_opaque_pixels_equal(actual: Image.Image, expected: Image.Image) -> None:
    assert actual.size == expected.size
    assert all(
        actual_pixel == expected_pixel
        for actual_pixel, expected_pixel in zip(
            actual.get_flattened_data(), expected.get_flattened_data(), strict=True
        )
        if expected_pixel[3] == 255
    )


def assert_manifest_matches(root: Path) -> None:
    metadata = json.loads((root / "candidate-metadata.json").read_text("utf-8"))
    for artifact in metadata["artifacts"]:
        path = root / artifact["path"]
        assert path.stat().st_size == artifact["bytes"]
        assert sha256(path) == artifact["sha256"]


def write_passing_rubric(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                name: {
                    "score": 2,
                    "evidence": f"Concrete reviewed {name} evidence.",
                }
                for name in (
                    "identity",
                    "function",
                    "material",
                    "hierarchy",
                    "originality",
                )
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def register_candidate_metadata(registry_path: Path, candidate_root: Path) -> None:
    """Mirror one generated review candidate into a test-only registry copy."""
    registry = json.loads(registry_path.read_text("utf-8"))
    metadata = json.loads((candidate_root / "candidate-metadata.json").read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    prefix = (
        "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002/"
    )
    active.update(
        {
            "artifacts": [
                {**artifact, "path": prefix + artifact["path"]}
                for artifact in metadata["artifacts"]
            ],
            "decision": "review",
            "font_provenance": metadata["card_rendering"]["fonts"],
            "harmony_verdict": metadata["harmony_verdict"],
            "metrics": metadata["metrics"],
            "reasons": [],
            "report_verdicts": {
                "harmony": metadata["harmony_verdict"],
                "pixel_qa_passed": json.loads(
                    (candidate_root / "qa/pixel-qa-report.json").read_text("utf-8")
                )["passed"],
            },
            "source_sha256": metadata["source_sha256"],
            "transform": metadata["transform"],
            "visual_rubric_sha256": metadata["visual_rubric_sha256"],
        }
    )
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def approval_event(timestamp: str = "2026-08-24T12:04:47Z") -> dict[str, str]:
    return {
        "candidate_id": "candidate-002",
        "decision": "approved",
        "authority": "explicit_user_approval_in_current_task",
        "approved_at_utc": timestamp,
    }


def approve_registered_candidate(registry_path: Path) -> None:
    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["approval_status"] = "approved"
    helmet["approval_history"] = [approval_event()]
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def prepare_registered_candidate(
    tmp_path: Path,
    *,
    with_passing_rubric: bool,
) -> tuple[BuildInputs, Path, Path]:
    registry_path = tmp_path / "registry.json"
    write_review_registry(registry_path)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_path)
    build_candidate_002(build_inputs)
    if with_passing_rubric:
        rubric = tmp_path / "passing-rubric.json"
        write_passing_rubric(rubric)
        build_candidate_002(build_inputs, visual_rubric=rubric)
    register_candidate_metadata(registry_path, output_root)
    return build_inputs, registry_path, output_root


def generated_candidate_binding(
    output_root: Path,
    registry_path: Path,
) -> dict[str, object]:
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit
        for unit in registry["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    return {
        "approval_event": approval_event(),
        "artifacts": [
            {
                "bytes": artifact["bytes"],
                "path": artifact["path"],
                "role": artifact["role"],
                "sha256": artifact["sha256"],
            }
            for artifact in metadata["artifacts"]
        ],
        "asset_id": "smoke_shell_helmet",
        "candidate_id": "candidate-002",
        "review_registry_normalized_sha256": (
            builder._approved_review_registry_digest(registry)
        ),
        "review_source_registry_sha256": active["source_sha256"]["registry"],
    }


def pin_generated_candidate_binding(
    monkeypatch: pytest.MonkeyPatch,
    output_root: Path,
    registry_path: Path,
) -> dict[str, object]:
    """Simulate the package binding being explicitly updated at approval time."""
    binding = generated_candidate_binding(output_root, registry_path)
    monkeypatch.setattr(
        builder,
        "_load_approved_binding",
        lambda: copy.deepcopy(binding),
    )
    return binding


def test_anchor_builder_binds_the_frozen_candidate_pixel_contract() -> None:
    checker = _load_checker()
    profile = json.loads(RIG_PROFILE.read_text(encoding="utf-8"))
    anchors = builder._build_anchors(checker, rgba(APPEARANCE_SOURCE), profile)

    assert anchors["schema_version"] == "gogobro-item-anchors-v1"
    assert anchors["pixel_contract"] == {
        "appearance_grid_scale": 2,
        "icon_grid_scale": 4,
        "logical_canvas": [64, 64],
        "outline_colors_rgb": [
            [8, 5, 3],
            [9, 0, 0],
            [21, 13, 6],
            [29, 27, 24],
            [34, 34, 31],
        ],
        "resampling": "nearest",
    }
    assert [frame["offset"] for frame in anchors["frames"]] == (
        [[26, 23]] * 4 + [[28, 23]] * 2 + [[26, 23]] * 2
    )
    assert anchors["algorithm"]["offset"] == (
        "round(face_center - nearest-resized aperture_center)"
    )


def test_builder_preserves_sources_and_derives_exact_review_candidate(tmp_path: Path) -> None:
    """Catches source mutation, resampling drift, invalid placement, and accidental curation."""
    before_hashes = tree_hashes(CANDIDATE_001)
    before_registry = sha256(REGISTRY)
    output_root = tmp_path / "candidate-002"

    result = build_candidate_002(inputs(output_root))

    assert tree_hashes(CANDIDATE_001) == before_hashes
    assert sha256(NIKO_ATLAS) == LOCKED_NIKO_HASH
    assert sha256(REGISTRY) == before_registry
    assert result.candidate_id == "candidate-002"
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    assert metadata["registry_snapshot"]["approval_status"] == "review"
    assert metadata["registry_snapshot"]["approval_history"] == []
    anchors = json.loads(
        (output_root / "appearance/anchors-walk-down.json").read_text("utf-8")
    )
    report = json.loads((output_root / "qa/harmony-report.json").read_text("utf-8"))

    source = rgba(APPEARANCE_SOURCE)
    appearance = rgba(output_root / "derived/appearance-128.png")
    icon = rgba(output_root / "derived/icon-256.png")
    assert appearance.size == (128, 128)
    assert icon.size == (256, 256)
    assert (output_root / "derived/appearance-128.png").read_bytes() == APPEARANCE_SOURCE.read_bytes()
    assert icon.tobytes() == source.resize((256, 256), Image.Resampling.NEAREST).tobytes()
    assert_pixel_contract(appearance)
    assert_pixel_contract(icon)
    profile = json.loads(RIG_PROFILE.read_text("utf-8"))
    appearance_palette_size = len(
        {pixel[:3] for pixel in appearance.get_flattened_data() if pixel[3]}
    )
    assert appearance_palette_size == 18
    assert profile["slot_profiles"]["head"]["max_palette_colors"] == appearance_palette_size

    assert metadata["transform"]["shared_scale"] == 0.625
    assert metadata["metrics"]["rendered_alpha_box"] == [9, 6, 71, 74]
    assert metadata["metrics"]["frame_boxes"] == [
        [35, 29, 97, 97],
        [35, 29, 97, 97],
        [35, 29, 97, 97],
        [35, 29, 97, 97],
        [37, 29, 99, 97],
        [37, 29, 99, 97],
        [35, 29, 97, 97],
        [35, 29, 97, 97],
    ]
    assert metadata["metrics"]["outer_width_ratio"] == pytest.approx(62 / 58)
    assert metadata["metrics"]["max_feature_center_error_px"] == 0
    assert metadata["metrics"]["max_residual_jitter_px"] == 0
    assert metadata["metrics"]["max_protected_occlusion_ratio"] == 0
    assert metadata["metrics"]["source_outline_boundary_pixels"] == {
        "matched": 563,
        "total": 563,
    }
    assert metadata["metrics"]["rendered_outline_boundary_pixels"] == [
        {"matched": 329, "total": 329}
    ] * 8
    assert report["verdict"] == "review"
    assert report["reason_codes"] == []

    assert len(anchors["frames"]) == 8
    assert all(frame["scale"] == 0.625 for frame in anchors["frames"])
    assert all(frame["depth"] == 40 for frame in anchors["frames"])
    assert all(
        isinstance(component, int)
        for frame in anchors["frames"]
        for component in frame["offset"]
    )
    assert all(
        0 <= left < right <= 128 and 0 <= top < bottom <= 128
        for left, top, right, bottom in metadata["metrics"]["frame_boxes"]
    )
    assert rgba(output_root / "qa/composite-frame-001.png").size == (128, 128)
    assert rgba(output_root / "qa/composite-atlas-8x128.png").size == (1024, 128)
    assert rgba(output_root / "qa/runtime-size-1920x1080.png").size == (1920, 1080)
    composite = rgba(output_root / "qa/composite-atlas-8x128.png")
    overlay = rgba(output_root / "qa/harmony-overlay.png")
    actual_size = rgba(output_root / "qa/harmony-actual-size.png")
    assert overlay.size == (1024, 128)
    assert actual_size.size == (1920, 1080)
    assert any(
        pixel[3] and pixel[:3] != (255, 0, 255)
        for pixel in overlay.get_flattened_data()
    )
    overlay_colors = {
        pixel[:3] for pixel in overlay.get_flattened_data() if pixel[3]
    }
    assert {
        (255, 0, 255),
        (0, 210, 255),
        (0, 255, 96),
        (255, 220, 0),
        (255, 64, 64),
    } <= overlay_colors
    actual_crop = actual_size.crop((448, 476, 1472, 604))
    assert all(
        actual_pixel == composite_pixel
        for actual_pixel, composite_pixel in zip(
            actual_crop.get_flattened_data(),
            composite.get_flattened_data(),
            strict=True,
        )
        if composite_pixel[3] == 255
    )
    assert rgba(output_root / "qa/approval-card.png").size == (1800, 1200)
    assert not (output_root / "curated").exists()
    assert {artifact["path"] for artifact in metadata["artifacts"]} == EXPECTED_ARTIFACTS
    artifacts_by_role = {artifact["role"]: artifact for artifact in metadata["artifacts"]}
    assert set(artifacts_by_role) == {
        "anchors",
        "appearance",
        "approval_card",
        "composite_atlas",
        "composite_frame",
        "harmony_actual_size",
        "harmony_overlay",
        "harmony_report",
        "icon",
        "pixel_qa_report",
        "runtime_preview",
        "visual_rubric",
    }
    assert all(artifact["bytes"] > 0 for artifact in metadata["artifacts"])
    assert all(len(artifact["sha256"]) == 64 for artifact in metadata["artifacts"])
    assert all("format" in artifact["output_spec"] for artifact in metadata["artifacts"])


def test_builder_is_deterministic_and_never_clears_output_root(tmp_path: Path) -> None:
    """Catches nondeterministic output and recursive cleanup of unrelated evidence."""
    first = tmp_path / "first"
    second = tmp_path / "second"
    build_candidate_002(inputs(first))
    build_candidate_002(inputs(second))

    first_hashes = tree_hashes(first)
    second_hashes = tree_hashes(second)
    assert first_hashes == second_hashes

    sentinel = first / "reviewer-note.txt"
    sentinel.write_text("preserve me\n", encoding="utf-8")
    rubric_before = (first / "qa/visual-rubric.json").read_bytes()
    build_candidate_002(inputs(first))
    assert sentinel.read_text(encoding="utf-8") == "preserve me\n"
    assert (first / "qa/visual-rubric.json").read_bytes() == rubric_before
    assert not (first / "curated").exists()


def test_no_rubric_placeholder_rebuild_is_byte_idempotent(tmp_path: Path) -> None:
    """Catches a blank rubric being promoted to reviewed provenance on rebuild."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    before = tree_hashes(output_root)

    build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    report = json.loads((output_root / "qa/harmony-report.json").read_text("utf-8"))
    assert metadata["visual_rubric_sha256"] is None
    assert "visual_rubric_sha256" not in metadata["metrics"]
    assert "visual_rubric" not in report["input_sha256"]
    assert "visual_rubric_sha256" not in report["metrics"]
    assert_manifest_matches(output_root)


def test_completed_preserved_rubric_is_reapplied_on_no_arg_rebuild(
    tmp_path: Path,
) -> None:
    """Catches a no-arg rebuild dropping an already reviewed rubric verdict."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)
    rubric_path = output_root / "qa/visual-rubric.json"
    before = tree_hashes(output_root)
    expected_hash = sha256(rubric_path)

    build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before
    report = json.loads((output_root / "qa/harmony-report.json").read_text("utf-8"))
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    rubric_artifact = next(
        artifact
        for artifact in metadata["artifacts"]
        if artifact["path"] == "qa/visual-rubric.json"
    )
    assert report["verdict"] == "harmony_pass"
    assert report["metrics"]["visual_rubric_total"] == 10
    assert report["metrics"]["visual_rubric_sha256"] == expected_hash
    assert report["input_sha256"]["visual_rubric"] == expected_hash
    assert metadata["visual_rubric_sha256"] == expected_hash
    assert rubric_artifact["sha256"] == expected_hash == sha256(rubric_path)
    assert_manifest_matches(output_root)


def test_tampered_completed_rubric_aborts_no_arg_rebuild_before_publish(
    tmp_path: Path,
) -> None:
    """A mutable output rubric cannot replace the last committed review authority."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)
    rubric_path = output_root / "qa/visual-rubric.json"
    committed_metadata = (output_root / "candidate-metadata.json").read_bytes()
    payload = json.loads(rubric_path.read_text(encoding="utf-8"))
    payload["identity"]["score"] = 0
    rubric_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    tampered_tree = tree_hashes(output_root)

    with pytest.raises(ValueError, match="visual_rubric_committed_state_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == tampered_tree
    assert (output_root / "candidate-metadata.json").read_bytes() == committed_metadata
    assert not (output_root / ".candidate-transaction.json").exists()


@pytest.mark.parametrize(
    "mutation",
    ["metadata_top", "artifact_entry", "report_input"],
)
def test_completed_rubric_requires_all_committed_hash_authorities(
    tmp_path: Path,
    mutation: str,
) -> None:
    """Metadata, artifact manifest, and report input must name one rubric digest."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)

    metadata_path = output_root / "candidate-metadata.json"
    report_path = output_root / "qa/harmony-report.json"
    if mutation in {"metadata_top", "artifact_entry"}:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if mutation == "metadata_top":
            metadata["visual_rubric_sha256"] = "0" * 64
        else:
            rubric_artifact = next(
                artifact
                for artifact in metadata["artifacts"]
                if artifact["path"] == "qa/visual-rubric.json"
            )
            rubric_artifact["sha256"] = "0" * 64
        metadata_path.write_text(
            json.dumps(metadata, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    else:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["input_sha256"]["visual_rubric"] = "0" * 64
        report_path.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    tampered_tree = tree_hashes(output_root)

    with pytest.raises(ValueError, match="visual_rubric_committed_state_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == tampered_tree
    assert not (output_root / ".candidate-transaction.json").exists()


def test_explicit_output_rubric_alias_is_rejected_before_writes(
    tmp_path: Path,
) -> None:
    """Explicit evidence must come from an immutable input path, not its output alias."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)
    before = tree_hashes(output_root)

    with pytest.raises(ValueError, match="visual_rubric_aliases_output"):
        build_candidate_002(
            build_inputs,
            visual_rubric=output_root / "qa/visual-rubric.json",
            revise_rubric_evidence=True,
        )

    assert tree_hashes(output_root) == before


def test_malformed_preserved_rubric_aborts_a_no_arg_rebuild(tmp_path: Path) -> None:
    """Catches unchecked target rubric bytes surviving as reviewed provenance."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_path = output_root / "qa/visual-rubric.json"
    rubric_path.write_text('{"identity": {"score": "2"}}\n', encoding="utf-8")
    metadata_before = (output_root / "candidate-metadata.json").read_bytes()

    with pytest.raises(ValueError, match="visual_rubric_committed_state_mismatch"):
        build_candidate_002(build_inputs)

    assert (output_root / "candidate-metadata.json").read_bytes() == metadata_before
    assert not (output_root / ".candidate-transaction.json").exists()


def test_preserved_rubric_change_after_capture_aborts_before_publish(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Catches publishing metadata for preserved rubric bytes that changed in flight."""
    output_root = tmp_path / "candidate-002"
    build_inputs = inputs(output_root)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)
    rubric_path = output_root / "qa/visual-rubric.json"
    metadata_before = (output_root / "candidate-metadata.json").read_bytes()
    real_approval_card = builder._approval_card

    def mutate_preserved_rubric(*args: object, **kwargs: object) -> Image.Image:
        card = real_approval_card(*args, **kwargs)
        payload = json.loads(rubric_path.read_text(encoding="utf-8"))
        payload["identity"]["evidence"] = "Concurrent reviewed identity evidence."
        rubric_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return card

    monkeypatch.setattr(builder, "_approval_card", mutate_preserved_rubric)

    with pytest.raises(RuntimeError, match="visual_rubric_changed"):
        build_candidate_002(build_inputs)

    assert (output_root / "candidate-metadata.json").read_bytes() == metadata_before
    assert not (output_root / ".candidate-transaction.json").exists()


def test_fresh_output_cannot_inherit_registry_approval(
    tmp_path: Path,
) -> None:
    """Approval is bound to existing reviewed bytes, never a newly generated output."""
    registry_copy = tmp_path / "registry.json"
    shutil.copyfile(REGISTRY, registry_copy)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    registry_before = registry_copy.read_bytes()

    with pytest.raises(
        ValueError,
        match="approved_registry_requires_existing_candidate",
    ):
        build_candidate_002(build_inputs)

    assert not output_root.exists()
    assert registry_copy.read_bytes() == registry_before


def test_package_owned_binding_matches_the_user_approved_candidate() -> None:
    binding = builder._load_approved_binding()
    candidate_root = Path(
        "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002"
    )
    metadata = json.loads(
        (candidate_root / "candidate-metadata.json").read_text("utf-8")
    )
    registry = json.loads(REGISTRY.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    approval_snapshot = builder._registry_approval_snapshot(helmet)

    assert binding["approval_event"] == approval_event()
    assert len(binding["artifacts"]) == 12
    assert builder._approved_binding_matches(
        registry,
        candidate_root,
        metadata,
        approval_snapshot,
    )
    assert binding["review_registry_normalized_sha256"] == (
        builder._approved_review_registry_digest(registry)
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    assert binding["review_source_registry_sha256"] == active["source_sha256"][
        "registry"
    ]


def test_real_package_binding_requires_code_reviewed_approval_migration(
    tmp_path: Path,
) -> None:
    """Runtime code never promotes review metadata, even with the real binding."""
    approved_root = Path(
        "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002"
    )
    output_root = tmp_path / "candidate-002"
    shutil.copytree(approved_root, output_root)
    registry_path = tmp_path / "registry.json"
    shutil.copyfile(REGISTRY, registry_path)

    metadata_path = output_root / "candidate-metadata.json"
    metadata = json.loads(metadata_path.read_text("utf-8"))
    metadata["registry_snapshot"]["approval_status"] = "review"
    metadata["registry_snapshot"]["approval_history"] = []
    prior_registry = json.loads(registry_path.read_text("utf-8"))
    prior_helmet = next(
        unit
        for unit in prior_registry["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    prior_helmet["approval_status"] = "review"
    prior_helmet.pop("approval_history")
    metadata["registry_snapshot"]["refresh_guard"] = builder._registry_refresh_guard(
        prior_registry,
        metadata,
    )
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)
    build_inputs = BuildInputs(
        appearance_source=APPEARANCE_SOURCE,
        niko_atlas=NIKO_ATLAS,
        rig_profile=RIG_PROFILE,
        registry=registry_path,
        output_root=output_root,
    )

    with pytest.raises(
        ValueError,
        match="approved_candidate_requires_explicit_package_migration",
    ):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


@pytest.mark.parametrize("mutation", ["armor", "top_level", "source_registry"])
def test_package_binding_rejects_coordinated_registry_semantic_rewrite(
    tmp_path: Path,
    mutation: str,
) -> None:
    """A recomputed metadata guard is not approval authority."""
    approved_root = Path(
        "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002"
    )
    output_root = tmp_path / "candidate-002"
    shutil.copytree(approved_root, output_root)
    registry_path = tmp_path / "registry.json"
    shutil.copyfile(REGISTRY, registry_path)
    metadata_path = output_root / "candidate-metadata.json"
    metadata = json.loads(metadata_path.read_text("utf-8"))
    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit
        for unit in registry["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    if mutation == "armor":
        helmet["effects"][0]["value"] = 999
        metadata["registry_snapshot"]["effects"] = copy.deepcopy(helmet["effects"])
    elif mutation == "top_level":
        registry["forged_transition_field"] = True
    else:
        active = next(
            candidate
            for candidate in helmet["candidate_history"]
            if candidate["candidate_id"] == "candidate-002"
        )
        active["source_sha256"]["registry"] = "0" * 64
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    metadata["source_sha256"]["registry"] = sha256(registry_path)
    metadata["registry_snapshot"]["refresh_guard"] = builder._registry_refresh_guard(
        registry,
        metadata,
    )
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    approval = builder._registry_approval_snapshot(helmet)
    assert builder._registered_candidate_matches_metadata(
        registry_path,
        output_root,
        metadata,
    )
    assert not builder._approved_binding_matches(
        registry,
        output_root,
        metadata,
        approval,
    )
    before = tree_hashes(output_root)
    build_inputs = BuildInputs(
        appearance_source=APPEARANCE_SOURCE,
        niko_atlas=NIKO_ATLAS,
        rig_profile=RIG_PROFILE,
        registry=registry_path,
        output_root=output_root,
    )

    with pytest.raises(ValueError, match="approved_candidate_provenance_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


@pytest.mark.parametrize("status", ["review", "approved"])
def test_active_candidate_mismatch_fails_before_generation(
    tmp_path: Path,
    status: str,
) -> None:
    registry = (
        review_registry_payload()
        if status == "review"
        else json.loads(REGISTRY.read_text("utf-8"))
    )
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["active_candidate_id"] = "candidate-001"
    registry_path = tmp_path / "registry.json"
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_path)

    with pytest.raises(ValueError, match="active_candidate_id_mismatch"):
        build_candidate_002(build_inputs)

    assert not output_root.exists()


def test_registered_review_candidate_cannot_auto_advance_to_user_approval(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Approval is a code-reviewed package update, never a runtime write."""
    registry_copy = tmp_path / "registry.json"
    registry = json.loads(REGISTRY.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["approval_status"] = "review"
    helmet.pop("approval_history")
    registry_copy.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    build_candidate_002(build_inputs)
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(build_inputs, visual_rubric=rubric_input)
    register_candidate_metadata(registry_copy, output_root)
    pin_generated_candidate_binding(monkeypatch, output_root, registry_copy)
    approved_registry = json.loads(registry_copy.read_text("utf-8"))
    approved_helmet = next(
        unit
        for unit in approved_registry["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    approved_helmet["approval_status"] = "approved"
    approved_helmet["approval_history"] = [
        {
            "candidate_id": "candidate-002",
            "decision": "approved",
            "authority": "explicit_user_approval_in_current_task",
            "approved_at_utc": "2026-08-24T12:04:47Z",
        }
    ]
    registry_copy.write_text(
        json.dumps(approved_registry, ensure_ascii=False, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)
    approved_registry_bytes = registry_copy.read_bytes()

    with pytest.raises(
        ValueError,
        match="approved_candidate_requires_explicit_package_migration",
    ):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before
    assert registry_copy.read_bytes() == approved_registry_bytes


def test_review_writer_lock_blocks_concurrent_approval_verification(
    tmp_path: Path,
) -> None:
    build_inputs, registry_path, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=True,
    )
    approve_registered_candidate(registry_path)
    before = tree_hashes(output_root)

    with builder._exclusive_approval_update_lock(output_root):
        with pytest.raises(RuntimeError, match="approval_update_locked"):
            build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before
    assert not (output_root / builder.APPROVAL_UPDATE_LOCK).exists()


def test_review_publish_lock_is_acquired_before_recovery_and_registry_read(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A paused review build cannot be recovered or overwritten by approval work."""
    review_inputs, review_registry, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=True,
    )
    approved_registry = tmp_path / "approved-registry.json"
    shutil.copyfile(review_registry, approved_registry)
    approve_registered_candidate(approved_registry)
    approval_inputs = replace(review_inputs, registry=approved_registry)
    entered_locked_build = threading.Event()
    release_locked_build = threading.Event()
    original_locked_build = builder._build_candidate_002_locked
    worker_errors: list[BaseException] = []

    def pause_review_build(*args: object, **kwargs: object) -> object:
        entered_locked_build.set()
        if not release_locked_build.wait(timeout=5):
            raise RuntimeError("review_build_release_timeout")
        return original_locked_build(*args, **kwargs)

    monkeypatch.setattr(builder, "_build_candidate_002_locked", pause_review_build)

    def run_review_build() -> None:
        try:
            build_candidate_002(review_inputs)
        except BaseException as error:
            worker_errors.append(error)

    worker = threading.Thread(target=run_review_build, daemon=True)
    worker.start()
    assert entered_locked_build.wait(timeout=5)
    try:
        with pytest.raises(RuntimeError, match="approval_update_locked"):
            build_candidate_002(approval_inputs)
    finally:
        release_locked_build.set()
        worker.join(timeout=10)

    assert not worker.is_alive()
    assert worker_errors == []
    metadata = json.loads(
        (output_root / "candidate-metadata.json").read_text("utf-8")
    )
    assert metadata["registry_snapshot"]["approval_status"] == "review"
    assert not (output_root / builder.APPROVAL_UPDATE_LOCK).exists()
    assert not (output_root / builder.TRANSACTION_MARKER).exists()


def test_approval_transition_requires_completed_harmony_and_visual_rubric(
    tmp_path: Path,
) -> None:
    build_inputs, registry_path, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=False,
    )
    approve_registered_candidate(registry_path)
    before = tree_hashes(output_root)

    with pytest.raises(
        ValueError,
        match="approved_candidate_requires_explicit_package_migration",
    ):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


def test_legacy_metadata_without_explicit_review_snapshot_cannot_be_approved(
    tmp_path: Path,
) -> None:
    build_inputs, registry_path, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=True,
    )
    approve_registered_candidate(registry_path)
    metadata_path = output_root / "candidate-metadata.json"
    metadata = json.loads(metadata_path.read_text("utf-8"))
    metadata["registry_snapshot"].pop("approval_status")
    metadata["registry_snapshot"].pop("approval_history")
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)

    with pytest.raises(ValueError, match="approved_candidate_provenance_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


@pytest.mark.parametrize(
    "mutation",
    [
        "candidate_id",
        "decision",
        "authority",
        "timestamp",
        "extra_field",
        "duplicate_event",
    ],
)
def test_forged_approval_event_never_mutates_existing_candidate(
    tmp_path: Path,
    mutation: str,
) -> None:
    build_inputs, registry_path, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=True,
    )
    approve_registered_candidate(registry_path)
    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    event = helmet["approval_history"][0]
    if mutation == "candidate_id":
        event["candidate_id"] = "candidate-001"
    elif mutation == "decision":
        event["decision"] = "review"
    elif mutation == "authority":
        event["authority"] = "forged_approval"
    elif mutation == "timestamp":
        event["approved_at_utc"] = "not-a-timeZ"
    elif mutation == "extra_field":
        event["forged"] = True
    else:
        helmet["approval_history"].append(copy.deepcopy(event))
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)

    with pytest.raises(ValueError, match="invalid_approval_history"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


def test_valid_approval_history_rewrite_and_rollback_are_rejected(
    tmp_path: Path,
) -> None:
    approved_root = Path(
        "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002"
    )
    output_root = tmp_path / "candidate-002"
    shutil.copytree(approved_root, output_root)
    registry_path = tmp_path / "registry.json"
    shutil.copyfile(REGISTRY, registry_path)
    build_inputs = BuildInputs(
        appearance_source=APPEARANCE_SOURCE,
        niko_atlas=NIKO_ATLAS,
        rig_profile=RIG_PROFILE,
        registry=registry_path,
        output_root=output_root,
    )

    rewritten = json.loads(registry_path.read_text("utf-8"))
    rewritten_helmet = next(
        unit
        for unit in rewritten["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    rewritten_helmet["approval_history"][0]["approved_at_utc"] = (
        "2026-08-24T12:05:47Z"
    )
    registry_path.write_text(
        json.dumps(rewritten, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    metadata_path = output_root / "candidate-metadata.json"
    rewritten_metadata = json.loads(metadata_path.read_text("utf-8"))
    rewritten_metadata["registry_snapshot"]["approval_history"][0][
        "approved_at_utc"
    ] = "2026-08-24T12:05:47Z"
    rewritten_metadata["source_sha256"]["registry"] = sha256(registry_path)
    normalized = builder._normalized_registered_registry(rewritten)
    rewritten_metadata["registry_snapshot"]["refresh_guard"] = {
        "excluded_fields": list(builder.REGISTRY_REFRESH_EXCLUDED_FIELDS),
        "normalized_sha256": hashlib.sha256(
            builder._canonical_json_bytes(normalized)
        ).hexdigest(),
        "schema_version": builder.REGISTRY_REFRESH_GUARD_SCHEMA,
    }
    metadata_path.write_text(
        json.dumps(rewritten_metadata, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )
    coordinated_rewrite = tree_hashes(output_root)

    with pytest.raises(ValueError, match="invalid_approval_history"):
        build_candidate_002(build_inputs)
    assert tree_hashes(output_root) == coordinated_rewrite

    rollback = copy.deepcopy(rewritten)
    rollback_helmet = next(
        unit for unit in rollback["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    rollback_helmet["approval_status"] = "review"
    rollback_helmet.pop("approval_history")
    registry_path.write_text(
        json.dumps(rollback, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="source_hash_mismatch"):
        build_candidate_002(build_inputs)
    assert tree_hashes(output_root) == coordinated_rewrite


@pytest.mark.parametrize("mutation", ["artifact_hash", "unrelated_registry_field"])
def test_approval_transition_rejects_candidate_or_registry_rewrite(
    tmp_path: Path,
    mutation: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    build_inputs, registry_path, output_root = prepare_registered_candidate(
        tmp_path,
        with_passing_rubric=True,
    )
    pin_generated_candidate_binding(monkeypatch, output_root, registry_path)
    approve_registered_candidate(registry_path)
    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    if mutation == "artifact_hash":
        active = next(
            candidate
            for candidate in helmet["candidate_history"]
            if candidate["candidate_id"] == "candidate-002"
        )
        active["artifacts"][0]["sha256"] = "0" * 64
    else:
        registry["forged_transition_field"] = True
    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)

    with pytest.raises(
        ValueError,
        match="approved_candidate_requires_explicit_package_migration",
    ):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


def test_package_binding_rejects_coordinated_icon_metadata_and_registry_swap(
    tmp_path: Path,
) -> None:
    approved_root = Path(
        "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/"
        "smoke_shell_helmet/candidate-002"
    )
    output_root = tmp_path / "candidate-002"
    shutil.copytree(approved_root, output_root)
    registry_path = tmp_path / "registry.json"
    shutil.copyfile(REGISTRY, registry_path)
    build_inputs = BuildInputs(
        appearance_source=APPEARANCE_SOURCE,
        niko_atlas=NIKO_ATLAS,
        rig_profile=RIG_PROFILE,
        registry=registry_path,
        output_root=output_root,
    )
    original_binding = builder._load_approved_binding()

    icon_path = output_root / "derived/icon-256.png"
    Image.new("RGBA", (256, 256), (255, 0, 255, 255)).save(icon_path)
    swapped_bytes = icon_path.stat().st_size
    swapped_sha256 = sha256(icon_path)

    metadata_path = output_root / "candidate-metadata.json"
    metadata = json.loads(metadata_path.read_text("utf-8"))
    metadata_icon = next(
        artifact
        for artifact in metadata["artifacts"]
        if artifact["path"] == "derived/icon-256.png"
    )
    metadata_icon["bytes"] = swapped_bytes
    metadata_icon["sha256"] = swapped_sha256

    registry = json.loads(registry_path.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    registry_icon = next(
        artifact
        for artifact in active["artifacts"]
        if artifact["path"].endswith("/derived/icon-256.png")
    )
    registry_icon["bytes"] = swapped_bytes
    registry_icon["sha256"] = swapped_sha256

    registry_path.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    metadata["source_sha256"]["registry"] = sha256(registry_path)
    metadata["registry_snapshot"]["refresh_guard"] = builder._registry_refresh_guard(
        registry,
        metadata,
    )
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    attacked_output = tree_hashes(output_root)

    with pytest.raises(ValueError, match="approved_candidate_provenance_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == attacked_output
    assert generated_candidate_binding(output_root, registry_path) != original_binding


@pytest.mark.parametrize(
    "timestamp",
    ["Z", "not-a-timeZ", "2026-99-99T99:99:99Z", "2026-02-31T12:00:00Z"],
)
def test_registry_approval_snapshot_rejects_malformed_timestamp(
    timestamp: str,
) -> None:
    registry = json.loads(REGISTRY.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    helmet["approval_history"][0]["approved_at_utc"] = timestamp

    with pytest.raises(ValueError, match="invalid_approval_history"):
        builder._registry_approval_snapshot(helmet)


def test_registered_refresh_rejects_registry_that_does_not_match_metadata(
    tmp_path: Path,
) -> None:
    """Catches the self-provenance exception accepting a tampered registry mirror."""
    registry_copy = tmp_path / "registry.json"
    write_review_registry(registry_copy)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    build_candidate_002(build_inputs)
    register_candidate_metadata(registry_copy, output_root)
    registry = json.loads(registry_copy.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    active["artifacts"][0]["sha256"] = "0" * 64
    registry_copy.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)

    with pytest.raises(ValueError, match="source_hash_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


@pytest.mark.parametrize(
    "malformed_bytes",
    [3030.0, True],
    ids=["equal_valued_float", "bool"],
)
def test_registered_refresh_rejects_non_exact_artifact_byte_types_without_mutation(
    tmp_path: Path,
    malformed_bytes: object,
) -> None:
    """Catches Python numeric equality authorizing a malformed registered refresh."""
    registry_copy = tmp_path / "registry.json"
    write_review_registry(registry_copy)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    build_candidate_002(build_inputs)
    register_candidate_metadata(registry_copy, output_root)

    registry = json.loads(registry_copy.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    assert active["artifacts"][0]["bytes"] == 3030
    active["artifacts"][0]["bytes"] = malformed_bytes
    registry_copy.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

    output_before = tree_hashes(output_root)
    metadata_before = (output_root / "candidate-metadata.json").read_bytes()
    registry_before = registry_copy.read_bytes()
    candidate_001_before = tree_hashes(CANDIDATE_001)
    source_hashes_before = {
        path: sha256(path)
        for path in (
            build_inputs.appearance_source,
            build_inputs.niko_atlas,
            build_inputs.rig_profile,
            build_inputs.card_font_regular,
            build_inputs.card_font_bold,
        )
    }

    with pytest.raises(ValueError, match="source_hash_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == output_before
    assert (output_root / "candidate-metadata.json").read_bytes() == metadata_before
    assert registry_copy.read_bytes() == registry_before
    assert tree_hashes(CANDIDATE_001) == candidate_001_before
    assert {path: sha256(path) for path in source_hashes_before} == source_hashes_before


@pytest.mark.parametrize(
    ("mutation", "error"),
    [
        ("artifact_bytes_float", "invalid_candidate_artifacts"),
        ("artifact_bytes_bool", "invalid_candidate_artifacts"),
        ("artifact_sha256_bool", "invalid_candidate_artifacts"),
        ("source_registry_bool", "invalid_candidate_source_sha256"),
        ("source_not_object", "invalid_candidate_source_sha256"),
        ("visual_rubric_missing", "invalid_candidate_visual_rubric_sha256"),
        ("visual_rubric_bool", "invalid_candidate_visual_rubric_sha256"),
        ("metrics_visual_rubric_bool", "invalid_candidate_metrics"),
        ("metrics_not_object", "invalid_candidate_metrics"),
    ],
)
def test_registry_normalization_rejects_malformed_excluded_field_types(
    mutation: str,
    error: str,
) -> None:
    """Catches normalization erasing malformed types before they are validated."""
    registry = json.loads(REGISTRY.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    active = next(
        candidate
        for candidate in helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )
    malformed = copy.deepcopy(registry)
    malformed_helmet = next(
        unit
        for unit in malformed["units"]
        if unit["asset_id"] == "smoke_shell_helmet"
    )
    malformed_active = next(
        candidate
        for candidate in malformed_helmet["candidate_history"]
        if candidate["candidate_id"] == "candidate-002"
    )

    if mutation == "artifact_bytes_float":
        malformed_active["artifacts"][0]["bytes"] = float(
            active["artifacts"][0]["bytes"]
        )
    elif mutation == "artifact_bytes_bool":
        malformed_active["artifacts"][0]["bytes"] = True
    elif mutation == "artifact_sha256_bool":
        malformed_active["artifacts"][0]["sha256"] = True
    elif mutation == "source_registry_bool":
        malformed_active["source_sha256"]["registry"] = True
    elif mutation == "source_not_object":
        malformed_active["source_sha256"] = []
    elif mutation == "visual_rubric_missing":
        malformed_active.pop("visual_rubric_sha256")
        malformed_active["metrics"].pop("visual_rubric_sha256")
    elif mutation == "visual_rubric_bool":
        malformed_active["visual_rubric_sha256"] = True
    elif mutation == "metrics_visual_rubric_bool":
        malformed_active["metrics"]["visual_rubric_sha256"] = True
    else:
        malformed_active["metrics"] = []

    with pytest.raises(ValueError, match=error):
        builder._normalized_registered_registry(malformed)


@pytest.mark.parametrize(
    "mutation",
    [
        "top_level_category_count",
        "unrelated_unit",
        "candidate_001_reasons",
        "helmet_unit_non_history",
    ],
)
def test_registered_refresh_rejects_every_non_self_registry_mutation(
    tmp_path: Path,
    mutation: str,
) -> None:
    """Catches refresh authorization that fingerprints only the active helmet record."""
    registry_copy = tmp_path / "registry.json"
    write_review_registry(registry_copy)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    build_candidate_002(build_inputs)
    register_candidate_metadata(registry_copy, output_root)

    registry = json.loads(registry_copy.read_text("utf-8"))
    helmet = next(
        unit for unit in registry["units"] if unit["asset_id"] == "smoke_shell_helmet"
    )
    if mutation == "top_level_category_count":
        registry["category_counts"]["weapon"] += 1
    elif mutation == "unrelated_unit":
        unrelated = next(
            unit for unit in registry["units"] if unit["asset_id"] != "smoke_shell_helmet"
        )
        unrelated["prompt_version"] = "tampered-unrelated-unit"
    elif mutation == "candidate_001_reasons":
        candidate_001 = next(
            candidate
            for candidate in helmet["candidate_history"]
            if candidate["candidate_id"] == "candidate-001"
        )
        candidate_001["reasons"] = [*candidate_001["reasons"], "tampered_reason"]
    else:
        helmet["prompt_version"] = "tampered-helmet-unit"
    registry_copy.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    before = tree_hashes(output_root)

    with pytest.raises(ValueError, match="source_hash_mismatch"):
        build_candidate_002(build_inputs)

    assert tree_hashes(output_root) == before


def test_registry_refresh_guard_is_stable_across_repeated_exact_refreshes(
    tmp_path: Path,
) -> None:
    """Catches a self-referential guard that cannot authorize its next exact generation."""
    registry_copy = tmp_path / "registry.json"
    write_review_registry(registry_copy)
    output_root = tmp_path / "candidate-002"
    build_inputs = replace(inputs(output_root), registry=registry_copy)
    build_candidate_002(build_inputs)
    initial_metadata = json.loads(
        (output_root / "candidate-metadata.json").read_text("utf-8")
    )
    initial_guard = initial_metadata["registry_snapshot"]["refresh_guard"]

    for _ in range(2):
        register_candidate_metadata(registry_copy, output_root)
        registry_before = registry_copy.read_bytes()
        build_candidate_002(build_inputs)
        refreshed = json.loads(
            (output_root / "candidate-metadata.json").read_text("utf-8")
        )
        assert refreshed["registry_snapshot"]["refresh_guard"] == initial_guard
        assert registry_copy.read_bytes() == registry_before


def test_candidate_001_existing_scale_and_offsets_fail_harmony(tmp_path: Path) -> None:
    """Catches a checker regression that would accept the oversized, misaligned candidate 001."""
    legacy = json.loads(
        (CANDIDATE_001 / "appearance/anchors-walk-down.json").read_text("utf-8")
    )
    checker_anchors = {
        "candidate_id": "candidate-001",
        "flip_behavior": "none",
        "frames": [
            {
                "depth": 40,
                "frame_index": frame["frame_index"],
                "offset": frame["placement"]["image_offset"],
                "scale": frame["placement"]["scale"],
            }
            for frame in legacy["frames"]
        ],
        "occupied_slots": [],
        "schema_version": legacy["schema_version"],
        "slot": "head",
    }
    anchors_path = tmp_path / "candidate-001-anchors.json"
    anchors_path.write_text(
        json.dumps(checker_anchors, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    checker = _load_checker()
    report = checker.analyze_harmony(
        checker.HarmonyInputs(
            character_atlas=NIKO_ATLAS,
            appearance=APPEARANCE_SOURCE,
            icon=CANDIDATE_001 / "icon/run/frames/icon/frame-0.png",
            anchors=anchors_path,
            rig_profile=RIG_PROFILE,
            slot="head",
            out_dir=tmp_path / "qa",
        )
    )

    assert {frame["scale"] for frame in checker_anchors["frames"]} == {0.75}
    assert report.verdict == "hard_fail"
    assert {
        "feature_center_offset",
        "formal_pixel_contract_required",
        "scale_ratio_high",
    } <= set(report.reason_codes)
    assert report.metrics["outer_width_ratio"] == pytest.approx(76 / 58)
    assert report.metrics["max_feature_center_error_px"] > 1


def test_finalization_applies_rubric_and_preserves_its_bytes(tmp_path: Path) -> None:
    """Catches rubric replacement, missing rubric provenance, and false finalization."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    rubric_input = tmp_path / "reviewed-rubric.json"
    rubric = {
        "identity": {"score": 2, "evidence": "The smoke-shell silhouette remains immediately identifiable."},
        "function": {"score": 2, "evidence": "The aperture follows the face in all eight frames."},
        "material": {"score": 2, "evidence": "Hard shell panels and smoke accents remain readable."},
        "hierarchy": {"score": 1, "evidence": "The face remains primary at actual size."},
        "originality": {"score": 1, "evidence": "The tactical shell motif remains distinct."},
    }
    rubric_input.write_text(
        json.dumps(rubric, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    before = rubric_input.read_bytes()

    build_candidate_002(inputs(output_root), visual_rubric=rubric_input)

    rubric_path = output_root / "qa/visual-rubric.json"
    assert rubric_path.read_bytes() == before
    rubric_hash = hashlib.sha256(before).hexdigest()
    report = json.loads((output_root / "qa/harmony-report.json").read_text("utf-8"))
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    assert report["verdict"] == "harmony_pass"
    assert report["metrics"]["visual_rubric_sha256"] == rubric_hash
    assert report["input_sha256"]["visual_rubric"] == rubric_hash
    assert report["source_integrity"]["before"]["visual_rubric"] == rubric_hash
    assert report["source_integrity"]["after"]["visual_rubric"] == rubric_hash
    assert metadata["visual_rubric_sha256"] == rubric_hash
    assert not (output_root / "curated").exists()


def test_explicit_rubric_revision_changes_evidence_only_and_preserves_art(
    tmp_path: Path,
) -> None:
    """Catches unsafe score changes or art drift during a reviewed evidence correction."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    initial_rubric_path = tmp_path / "initial-rubric.json"
    initial_rubric = {
        name: {"score": 2, "evidence": f"Initial concrete {name} evidence."}
        for name in ("identity", "function", "material", "hierarchy", "originality")
    }
    initial_rubric_path.write_text(
        json.dumps(initial_rubric, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    build_candidate_002(inputs(output_root), visual_rubric=initial_rubric_path)
    rubric_path = output_root / "qa/visual-rubric.json"
    immutable_art = {
        relative: sha256(output_root / relative)
        for relative in EXPECTED_ARTIFACTS
        if relative not in {"qa/harmony-report.json", "qa/visual-rubric.json"}
    }
    revised_rubric = {
        **initial_rubric,
        "identity": {
            "score": 2,
            "evidence": "Niko's face, brows, beard, and shirt remain readable in all eight frames.",
        },
        "function": {
            "score": 2,
            "evidence": "The shell, aperture, vent, and smoke canister read as protective smoke headgear.",
        },
    }
    revision_path = tmp_path / "revised-rubric.json"
    revision_path.write_text(
        json.dumps(revised_rubric, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    build_candidate_002(
        inputs(output_root),
        visual_rubric=revision_path,
        revise_rubric_evidence=True,
    )

    assert rubric_path.read_bytes() == revision_path.read_bytes()
    assert {
        name: value["score"] for name, value in revised_rubric.items()
    } == {name: value["score"] for name, value in initial_rubric.items()}
    metadata = json.loads((output_root / "candidate-metadata.json").read_text("utf-8"))
    assert metadata["visual_rubric_sha256"] == sha256(revision_path)
    assert metadata["harmony_verdict"] == "harmony_pass"
    assert {
        relative: sha256(output_root / relative) for relative in immutable_art
    } == immutable_art
    assert not (output_root / ".candidate-transaction.json").exists()


def test_failed_explicit_rubric_revision_rolls_back_every_candidate_file(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches an interrupted evidence revision leaving rubric and metadata mixed."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    initial_rubric_path = tmp_path / "initial-rubric.json"
    initial_rubric = {
        name: {"score": 2, "evidence": f"Initial concrete {name} evidence."}
        for name in ("identity", "function", "material", "hierarchy", "originality")
    }
    initial_rubric_path.write_text(
        json.dumps(initial_rubric, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    build_candidate_002(inputs(output_root), visual_rubric=initial_rubric_path)
    before = tree_hashes(output_root)
    revised_rubric = {
        name: {**value, "evidence": f"Revised concrete {name} evidence."}
        for name, value in initial_rubric.items()
    }
    revision_path = tmp_path / "revised-rubric.json"
    revision_path.write_text(
        json.dumps(revised_rubric, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    real_replace = builder._replace_file
    calls = 0

    def fail_during_revision(source: Path, target: Path) -> Path:
        nonlocal calls
        calls += 1
        if calls == 4:
            raise OSError("injected rubric revision failure")
        return real_replace(source, target)

    monkeypatch.setattr(builder, "_replace_file", fail_during_revision)
    with pytest.raises(OSError, match="injected rubric revision failure"):
        build_candidate_002(
            inputs(output_root),
            visual_rubric=revision_path,
            revise_rubric_evidence=True,
        )

    assert tree_hashes(output_root) == before
    assert not (output_root / ".candidate-transaction.json").exists()


def test_explicit_rubric_revision_rejects_score_changes_before_writes(
    tmp_path: Path,
) -> None:
    """Catches an evidence-only correction silently changing reviewed scores."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    initial_rubric_path = tmp_path / "initial-rubric.json"
    initial_rubric = {
        name: {"score": 2, "evidence": f"Initial concrete {name} evidence."}
        for name in ("identity", "function", "material", "hierarchy", "originality")
    }
    initial_rubric_path.write_text(
        json.dumps(initial_rubric, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    build_candidate_002(inputs(output_root), visual_rubric=initial_rubric_path)
    before = tree_hashes(output_root)
    score_change = {
        **initial_rubric,
        "identity": {
            "score": 1,
            "evidence": "Changed identity evidence and score.",
        },
    }
    revision_path = tmp_path / "score-change-rubric.json"
    revision_path.write_text(
        json.dumps(score_change, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="visual_rubric_scores_changed"):
        build_candidate_002(
            inputs(output_root),
            visual_rubric=revision_path,
            revise_rubric_evidence=True,
        )

    assert tree_hashes(output_root) == before


def test_approval_card_contains_exact_1x_icon_and_runtime_evidence(tmp_path: Path) -> None:
    """Catches resampled icon evidence, missing runtime evidence, and ambiguous status."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    pixel_qa = json.loads((output_root / "qa/pixel-qa-report.json").read_text("utf-8"))
    evidence = pixel_qa["approval_card_evidence"]
    card = rgba(output_root / "qa/approval-card.png")
    icon = rgba(output_root / "derived/icon-256.png")
    appearance = rgba(output_root / "derived/appearance-128.png")
    frame = rgba(output_root / "qa/composite-frame-001.png")
    composite = rgba(output_root / "qa/composite-atlas-8x128.png")

    assert evidence["status_text"] == "Harmony gate: review | Unit approval status: review"
    assert evidence["icon"] == {
        "box": [164, 310, 420, 566],
        "display_scale": 1,
        "resampling": "none",
        "source": "derived/icon-256.png",
    }
    assert evidence["appearance"]["display_scale"] == 1
    assert evidence["runtime_actual_size"] == {
        "box": [930, 500, 1058, 628],
        "display_scale": 1,
        "resampling": "none",
        "source": "qa/composite-frame-001.png",
    }
    assert evidence["caption_boxes"] == {
        "appearance": [600, 450, 850, 496],
        "runtime_actual_size": [930, 450, 1140, 496],
    }
    appearance_caption = evidence["caption_boxes"]["appearance"]
    runtime_caption = evidence["caption_boxes"]["runtime_actual_size"]
    assert appearance_caption[2] < runtime_caption[0]
    assert_opaque_pixels_equal(card.crop((164, 310, 420, 566)), icon)
    assert_opaque_pixels_equal(card.crop((600, 500, 728, 628)), appearance)
    assert_opaque_pixels_equal(card.crop((930, 500, 1058, 628)), frame)
    assert_opaque_pixels_equal(card.crop((600, 300, 1624, 428)), composite)


def test_approval_card_uses_truthful_state_invariant_review_footer(
    tmp_path: Path,
) -> None:
    """Catches review evidence falsely claiming that no registry record changed."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    pixel_qa = json.loads(
        (output_root / "qa/pixel-qa-report.json").read_text("utf-8")
    )
    evidence = pixel_qa["approval_card_evidence"]

    assert evidence["footer_text"] == EXPECTED_REVIEW_FOOTER
    assert "registry mutation" not in evidence["footer_text"]

    card = rgba(output_root / "qa/approval-card.png")
    actual_footer = card.crop((92, 1088, 1708, 1144))
    expected_footer = Image.new("RGBA", actual_footer.size, (25, 32, 44, 255))
    ImageDraw.Draw(expected_footer).text(
        (0, 4),
        EXPECTED_REVIEW_FOOTER,
        font=ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 30),
        fill=(239, 116, 116, 255),
    )
    assert actual_footer.tobytes() == expected_footer.tobytes()


def test_finalization_refuses_a_different_existing_rubric_before_writes(tmp_path: Path) -> None:
    """Catches report/metadata provenance that disagrees with retained rubric bytes."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(inputs(output_root), visual_rubric=rubric_input)
    before = tree_hashes(output_root)
    different_rubric = tmp_path / "different-rubric.json"
    different_rubric.write_text(
        json.dumps(
            {
                name: {"score": 2, "evidence": f"Different reviewed evidence for {name}."}
                for name in ("identity", "function", "material", "hierarchy", "originality")
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="visual_rubric_mismatch"):
        build_candidate_002(inputs(output_root), visual_rubric=different_rubric)

    assert tree_hashes(output_root) == before


def test_publication_failure_rolls_back_the_old_valid_generation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches a recoverable write failure leaving metadata and artifacts mixed."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(inputs(output_root), visual_rubric=rubric_input)
    before = tree_hashes(output_root)
    real_replace = getattr(builder, "_replace_file", lambda source, target: source.replace(target))
    calls = 0

    def fail_during_publication(source: Path, target: Path) -> Path:
        nonlocal calls
        calls += 1
        if calls == 4:
            raise OSError("injected publication failure")
        return real_replace(source, target)

    monkeypatch.setattr(builder, "_replace_file", fail_during_publication, raising=False)
    with pytest.raises(OSError, match="injected publication failure"):
        build_candidate_002(inputs(output_root))

    assert tree_hashes(output_root) == before
    assert not (output_root / ".candidate-transaction.json").exists()
    assert_manifest_matches(output_root)


def test_interrupted_publication_is_marked_and_recovered_on_next_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches an interrupted multi-file publish being mistaken for a valid candidate."""
    output_root = tmp_path / "candidate-002"
    build_candidate_002(inputs(output_root))
    rubric_input = tmp_path / "passing-rubric.json"
    write_passing_rubric(rubric_input)
    build_candidate_002(inputs(output_root), visual_rubric=rubric_input)
    real_replace = getattr(builder, "_replace_file", lambda source, target: source.replace(target))
    calls = 0

    def interrupt_publication(source: Path, target: Path) -> Path:
        nonlocal calls
        calls += 1
        if calls == 4:
            raise KeyboardInterrupt("injected crash")
        return real_replace(source, target)

    monkeypatch.setattr(builder, "_replace_file", interrupt_publication, raising=False)
    with pytest.raises(KeyboardInterrupt, match="injected crash"):
        build_candidate_002(inputs(output_root))
    assert (output_root / ".candidate-transaction.json").is_file()

    monkeypatch.setattr(builder, "_replace_file", real_replace, raising=False)
    build_candidate_002(inputs(output_root))

    assert not (output_root / ".candidate-transaction.json").exists()
    assert_manifest_matches(output_root)


def test_failed_initial_publication_can_retry_without_clearing_output_root(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches empty transaction-created directories blocking a safe first-build retry."""
    output_root = tmp_path / "candidate-002"
    real_replace = getattr(builder, "_replace_file", lambda source, target: source.replace(target))
    calls = 0

    def fail_first_publication(source: Path, target: Path) -> Path:
        nonlocal calls
        calls += 1
        if calls == 4:
            raise OSError("injected first publication failure")
        return real_replace(source, target)

    monkeypatch.setattr(builder, "_replace_file", fail_first_publication)
    with pytest.raises(OSError, match="injected first publication failure"):
        build_candidate_002(inputs(output_root))
    assert not (output_root / ".candidate-transaction.json").exists()
    assert not (output_root / "candidate-metadata.json").exists()

    monkeypatch.setattr(builder, "_replace_file", real_replace)
    build_candidate_002(inputs(output_root))

    assert_manifest_matches(output_root)


def test_card_fonts_are_explicit_hashed_inputs(tmp_path: Path) -> None:
    """Catches unprovenanced host-font selection changing approval-card bytes."""
    build_inputs = inputs(tmp_path / "candidate-002")
    build_candidate_002(build_inputs)
    metadata = json.loads(
        (build_inputs.output_root / "candidate-metadata.json").read_text("utf-8")
    )

    assert metadata["source_sha256"]["card_font_regular"] == sha256(
        build_inputs.card_font_regular
    )
    assert metadata["source_sha256"]["card_font_bold"] == sha256(
        build_inputs.card_font_bold
    )
    assert metadata["card_rendering"]["fonts"] == {
        "bold": {
            "path": str(build_inputs.card_font_bold.resolve()),
            "sha256": sha256(build_inputs.card_font_bold),
        },
        "regular": {
            "path": str(build_inputs.card_font_regular.resolve()),
            "sha256": sha256(build_inputs.card_font_regular),
        },
    }


def test_builder_fails_before_output_when_a_card_font_is_missing(tmp_path: Path) -> None:
    """Catches silent font fallback and unrepeatable host-dependent rendering."""
    build_inputs = replace(
        inputs(tmp_path / "candidate-002"),
        card_font_regular=tmp_path / "missing-font.ttc",
    )

    with pytest.raises(FileNotFoundError, match="missing-font.ttc"):
        build_candidate_002(build_inputs)

    assert not build_inputs.output_root.exists()


def test_builder_detects_a_card_font_changed_during_build(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches font bytes changing after provenance is captured but before publication."""
    regular = tmp_path / "regular.ttc"
    bold = tmp_path / "bold.ttc"
    shutil.copyfile("C:/Windows/Fonts/msyh.ttc", regular)
    shutil.copyfile("C:/Windows/Fonts/msyhbd.ttc", bold)
    build_inputs = replace(
        inputs(tmp_path / "candidate-002"),
        card_font_regular=regular,
        card_font_bold=bold,
    )
    real_approval_card = builder._approval_card

    def mutate_font_after_render(*args: object, **kwargs: object) -> Image.Image:
        card = real_approval_card(*args, **kwargs)
        regular.write_bytes(regular.read_bytes() + b"changed")
        return card

    monkeypatch.setattr(builder, "_approval_card", mutate_font_after_render)
    with pytest.raises(RuntimeError, match="card_font_changed"):
        build_candidate_002(build_inputs)

    assert not (build_inputs.output_root / "candidate-metadata.json").exists()


def test_builder_detects_registry_change_after_source_provenance_capture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Catches metadata recording a registry hash older than the registry it rendered."""
    registry_copy = tmp_path / "registry.json"
    write_review_registry(registry_copy)
    build_inputs = replace(
        inputs(tmp_path / "candidate-002"),
        registry=registry_copy,
    )
    real_assert_reusable = builder._assert_reusable_output

    def mutate_registry_after_source_capture(*args: object, **kwargs: object) -> None:
        real_assert_reusable(*args, **kwargs)
        registry = json.loads(registry_copy.read_text("utf-8"))
        registry["test_mutation_after_source_capture"] = True
        registry_copy.write_text(
            json.dumps(registry, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

    monkeypatch.setattr(
        builder,
        "_assert_reusable_output",
        mutate_registry_after_source_capture,
    )

    with pytest.raises(RuntimeError, match="source_changed"):
        build_candidate_002(build_inputs)

    assert not (build_inputs.output_root / "candidate-metadata.json").exists()


def test_builder_reuses_the_checker_strict_visual_rubric_loader(
    tmp_path: Path,
) -> None:
    """Catches builder-side coercion bypassing the public checker contract."""
    output_root = tmp_path / "candidate-002"
    malformed_rubric = tmp_path / "malformed-rubric.json"
    malformed_rubric.write_text(
        json.dumps(
            {
                name: {"score": "2", "evidence": "Concrete visual evidence."}
                for name in (
                    "identity",
                    "function",
                    "material",
                    "hierarchy",
                    "originality",
                )
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="malformed_visual_rubric"):
        build_candidate_002(inputs(output_root), visual_rubric=malformed_rubric)

    assert not (output_root / "candidate-metadata.json").exists()


def test_builder_detects_rig_change_after_checker_analysis_before_publish(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Catches publication with a stale recorded rig-profile hash."""
    rig_copy = tmp_path / "rig.json"
    shutil.copyfile(RIG_PROFILE, rig_copy)
    build_inputs = replace(inputs(tmp_path / "candidate-002"), rig_profile=rig_copy)
    real_approval_card = builder._approval_card

    def mutate_rig_after_analysis(*args: object, **kwargs: object) -> Image.Image:
        card = real_approval_card(*args, **kwargs)
        profile = json.loads(rig_copy.read_text(encoding="utf-8"))
        profile["test_mutation_after_analysis"] = True
        rig_copy.write_text(
            json.dumps(profile, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return card

    monkeypatch.setattr(builder, "_approval_card", mutate_rig_after_analysis)

    with pytest.raises(RuntimeError, match="source_changed"):
        build_candidate_002(build_inputs)

    assert not (build_inputs.output_root / "candidate-metadata.json").exists()
