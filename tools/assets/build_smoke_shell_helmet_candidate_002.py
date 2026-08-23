"""Build the deterministic Smoke-Shell Helmet review candidate 002."""

from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import asdict, dataclass, replace
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


CANDIDATE_ID = "candidate-002"
ASSET_ID = "smoke_shell_helmet"
SHARED_SCALE = 0.625
FRAME_SIZE = (128, 128)
ICON_SIZE = (256, 256)
ATLAS_SIZE = (1024, 128)
LOCKED_NIKO_HASH = "fbc10108d9a665b14dcc376da54bbbf66d89b931ae1189e69fe1c45b31fe579d"
DEFAULT_CARD_FONT_REGULAR = Path("C:/Windows/Fonts/msyh.ttc")
DEFAULT_CARD_FONT_BOLD = Path("C:/Windows/Fonts/msyhbd.ttc")
TRANSACTION_MARKER = ".candidate-transaction.json"
REVIEW_FOOTER_TEXT = (
    "REVIEW EVIDENCE ONLY — no curated, runtime, or startup integration"
)
REGISTRY_ARTIFACT_PREFIX = (
    "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/"
    "smoke_shell_helmet/candidate-002/"
)
RUBRIC_DIMENSIONS = (
    "identity",
    "function",
    "material",
    "hierarchy",
    "originality",
)
REGISTRY_REFRESH_GUARD_SCHEMA = "gogobro-registry-refresh-guard-v1"
REGISTRY_REFRESH_EXCLUDED_FIELDS = (
    "units[smoke_shell_helmet].candidate_history[candidate-002].artifacts[*].bytes",
    "units[smoke_shell_helmet].candidate_history[candidate-002].artifacts[*].sha256",
    "units[smoke_shell_helmet].candidate_history[candidate-002].metrics.visual_rubric_sha256",
    "units[smoke_shell_helmet].candidate_history[candidate-002].source_sha256.registry",
    "units[smoke_shell_helmet].candidate_history[candidate-002].visual_rubric_sha256",
)
ARTIFACT_PATHS = (
    "derived/icon-256.png",
    "derived/appearance-128.png",
    "appearance/anchors-walk-down.json",
    "qa/composite-frame-001.png",
    "qa/composite-atlas-8x128.png",
    "qa/runtime-size-1920x1080.png",
    "qa/harmony-overlay.png",
    "qa/harmony-actual-size.png",
    "qa/harmony-report.json",
    "qa/visual-rubric.json",
    "qa/pixel-qa-report.json",
    "qa/approval-card.png",
)
ARTIFACT_ROLES = {
    "derived/icon-256.png": "icon",
    "derived/appearance-128.png": "appearance",
    "appearance/anchors-walk-down.json": "anchors",
    "qa/composite-frame-001.png": "composite_frame",
    "qa/composite-atlas-8x128.png": "composite_atlas",
    "qa/runtime-size-1920x1080.png": "runtime_preview",
    "qa/harmony-overlay.png": "harmony_overlay",
    "qa/harmony-actual-size.png": "harmony_actual_size",
    "qa/harmony-report.json": "harmony_report",
    "qa/visual-rubric.json": "visual_rubric",
    "qa/pixel-qa-report.json": "pixel_qa_report",
    "qa/approval-card.png": "approval_card",
}


@dataclass(frozen=True)
class BuildInputs:
    appearance_source: Path
    niko_atlas: Path
    rig_profile: Path
    registry: Path
    output_root: Path
    card_font_regular: Path = DEFAULT_CARD_FONT_REGULAR
    card_font_bold: Path = DEFAULT_CARD_FONT_BOLD


@dataclass(frozen=True)
class CandidateMetadata:
    candidate_id: str
    transform: dict[str, object]
    artifacts: Sequence[dict[str, object]]
    metrics: dict[str, object]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _load_checker() -> object:
    checker_path = (
        _repo_root()
        / "tools/codex_skills/checking-gogobro-item-harmony/scripts/check_item_harmony.py"
    )
    spec = importlib.util.spec_from_file_location("gogobro_item_harmony_checker", checker_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("checker_import_failed")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): _sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode(
            "utf-8"
        )
    )


def _read_object(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def _canonical_json_bytes(payload: object) -> bytes:
    return json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def _is_lower_sha256(value: object) -> bool:
    return (
        type(value) is str
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _source_hashes(inputs: BuildInputs, candidate_001_hashes: dict[str, str]) -> dict[str, object]:
    return {
        "appearance_source": _sha256(inputs.appearance_source),
        "card_font_bold": _sha256(inputs.card_font_bold),
        "card_font_regular": _sha256(inputs.card_font_regular),
        "niko_atlas": _sha256(inputs.niko_atlas),
        "rig_profile": _sha256(inputs.rig_profile),
        "registry": _sha256(inputs.registry),
        "candidate_001_tree": candidate_001_hashes,
    }


def _validate_inputs(inputs: BuildInputs) -> Path:
    for path in (
        inputs.appearance_source,
        inputs.niko_atlas,
        inputs.rig_profile,
        inputs.registry,
        inputs.card_font_regular,
        inputs.card_font_bold,
    ):
        if not path.is_file():
            raise FileNotFoundError(path)
    candidate_001 = inputs.appearance_source.resolve().parents[1]
    output = inputs.output_root.resolve()
    if output == candidate_001 or candidate_001 in output.parents:
        raise ValueError("output_root_overlaps_candidate_001")
    if _sha256(inputs.niko_atlas) != LOCKED_NIKO_HASH:
        raise ValueError("niko_atlas_hash_mismatch")
    return candidate_001


def _registry_artifacts_from_metadata(
    metadata: dict[str, object],
) -> list[dict[str, object]]:
    artifacts = metadata.get("artifacts")
    if not isinstance(artifacts, list) or len(artifacts) != len(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_metadata")
    expected_artifacts: list[dict[str, object]] = []
    seen_paths: set[str] = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ValueError("invalid_candidate_metadata")
        relative = artifact.get("path")
        if (
            not isinstance(relative, str)
            or relative not in ARTIFACT_PATHS
            or relative in seen_paths
            or artifact.get("role") != ARTIFACT_ROLES[relative]
        ):
            raise ValueError("invalid_candidate_metadata")
        seen_paths.add(relative)
        expected_artifacts.append(
            {**artifact, "path": REGISTRY_ARTIFACT_PREFIX + relative}
        )
    if seen_paths != set(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_metadata")
    return expected_artifacts


def _expected_registered_candidate(
    metadata: dict[str, object],
) -> dict[str, object]:
    card_rendering = metadata.get("card_rendering")
    if not isinstance(card_rendering, dict):
        raise ValueError("invalid_candidate_metadata")
    return {
        "artifacts": _registry_artifacts_from_metadata(metadata),
        "candidate_id": CANDIDATE_ID,
        "decision": "review",
        "font_provenance": card_rendering.get("fonts"),
        "harmony_verdict": metadata.get("harmony_verdict"),
        "metrics": metadata.get("metrics"),
        "reasons": [],
        "report_verdicts": {
            "harmony": metadata.get("harmony_verdict"),
            "pixel_qa_passed": True,
        },
        "source_sha256": metadata.get("source_sha256"),
        "transform": metadata.get("transform"),
        "visual_rubric_sha256": metadata.get("visual_rubric_sha256"),
    }


def _project_registered_registry(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> dict[str, object]:
    projected = copy.deepcopy(registry)
    unit = _registry_unit(projected)
    history = unit.get("candidate_history")
    if not isinstance(history, list):
        raise ValueError("invalid_registry_history")
    matches = [
        index
        for index, candidate in enumerate(history)
        if isinstance(candidate, dict) and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    expected = _expected_registered_candidate(metadata)
    if not matches:
        history.append(expected)
    elif len(matches) == 1:
        history[matches[0]] = expected
    else:
        raise ValueError("duplicate_candidate_id")
    unit["active_candidate_id"] = CANDIDATE_ID
    unit["approval_status"] = "review"
    return projected


def _normalized_registered_registry(
    registry: dict[str, object],
) -> dict[str, object]:
    normalized = copy.deepcopy(registry)
    unit = _registry_unit(normalized)
    history = unit.get("candidate_history")
    if type(history) is not list:
        raise ValueError("invalid_registry_history")
    matches = [
        candidate
        for candidate in history
        if type(candidate) is dict and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    if len(matches) != 1:
        raise ValueError("candidate_002_registry_count")
    active = matches[0]
    artifacts = active.get("artifacts")
    if type(artifacts) is not list or len(artifacts) != len(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_artifacts")
    seen_paths: set[str] = set()
    for artifact in artifacts:
        if type(artifact) is not dict:
            raise ValueError("invalid_candidate_artifacts")
        raw_path = artifact.get("path")
        if type(raw_path) is not str or not raw_path.startswith(REGISTRY_ARTIFACT_PREFIX):
            raise ValueError("invalid_candidate_artifacts")
        relative = raw_path[len(REGISTRY_ARTIFACT_PREFIX) :]
        byte_count = artifact.get("bytes")
        artifact_sha256 = artifact.get("sha256")
        if (
            relative not in ARTIFACT_PATHS
            or relative in seen_paths
            or artifact.get("role") != ARTIFACT_ROLES[relative]
            or type(byte_count) is not int
            or byte_count < 0
            or not _is_lower_sha256(artifact_sha256)
        ):
            raise ValueError("invalid_candidate_artifacts")
        seen_paths.add(relative)
        artifact["bytes"] = "<candidate-002-generated-bytes>"
        artifact["sha256"] = "<candidate-002-generated-sha256>"
    if seen_paths != set(ARTIFACT_PATHS):
        raise ValueError("invalid_candidate_artifacts")
    source_sha256 = active.get("source_sha256")
    if type(source_sha256) is not dict or not _is_lower_sha256(
        source_sha256.get("registry")
    ):
        raise ValueError("invalid_candidate_source_sha256")
    source_sha256["registry"] = "<candidate-002-source-registry-sha256>"
    if "visual_rubric_sha256" not in active:
        raise ValueError("invalid_candidate_visual_rubric_sha256")
    visual_rubric_sha256 = active.get("visual_rubric_sha256")
    metrics = active.get("metrics")
    if type(metrics) is not dict:
        raise ValueError("invalid_candidate_metrics")
    metrics_has_rubric = "visual_rubric_sha256" in metrics
    if visual_rubric_sha256 is not None and not _is_lower_sha256(
        visual_rubric_sha256
    ):
        raise ValueError("invalid_candidate_visual_rubric_sha256")
    if metrics_has_rubric and not _is_lower_sha256(
        metrics.get("visual_rubric_sha256")
    ):
        raise ValueError("invalid_candidate_metrics")
    if visual_rubric_sha256 is None and metrics_has_rubric:
        raise ValueError("invalid_candidate_metrics")
    active["visual_rubric_sha256"] = "<candidate-002-visual-rubric-sha256>"
    if metrics_has_rubric:
        metrics["visual_rubric_sha256"] = (
            "<candidate-002-metrics-visual-rubric-sha256>"
        )
    return normalized


def _registry_refresh_guard(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> dict[str, object]:
    normalized = _normalized_registered_registry(
        _project_registered_registry(registry, metadata)
    )
    return {
        "excluded_fields": list(REGISTRY_REFRESH_EXCLUDED_FIELDS),
        "normalized_sha256": hashlib.sha256(
            _canonical_json_bytes(normalized)
        ).hexdigest(),
        "schema_version": REGISTRY_REFRESH_GUARD_SCHEMA,
    }


def _registry_refresh_guard_matches(
    registry: dict[str, object],
    metadata: dict[str, object],
) -> bool:
    registry_snapshot = metadata.get("registry_snapshot")
    if not isinstance(registry_snapshot, dict):
        return False
    guard = registry_snapshot.get("refresh_guard")
    if not isinstance(guard, dict):
        return False
    expected_sha256 = guard.get("normalized_sha256")
    if (
        guard.get("schema_version") != REGISTRY_REFRESH_GUARD_SCHEMA
        or guard.get("excluded_fields") != list(REGISTRY_REFRESH_EXCLUDED_FIELDS)
        or not isinstance(expected_sha256, str)
        or len(expected_sha256) != 64
    ):
        return False
    try:
        current_normalized = _normalized_registered_registry(registry)
    except ValueError:
        return False
    return (
        hashlib.sha256(_canonical_json_bytes(current_normalized)).hexdigest()
        == expected_sha256
    )


def _registered_candidate_matches_metadata(
    registry_path: Path,
    output_root: Path,
    metadata: dict[str, object],
) -> bool:
    try:
        expected_active = _expected_registered_candidate(metadata)
    except ValueError:
        return False
    for artifact in metadata["artifacts"]:
        relative = artifact["path"]
        path = output_root / relative
        if (
            not path.is_file()
            or path.stat().st_size != artifact.get("bytes")
            or _sha256(path) != artifact.get("sha256")
        ):
            return False

    registry = _read_object(registry_path)
    unit = _registry_unit(registry)
    history = unit.get("candidate_history")
    if not isinstance(history, list):
        return False
    active_matches = [
        candidate
        for candidate in history
        if isinstance(candidate, dict) and candidate.get("candidate_id") == CANDIDATE_ID
    ]
    if len(active_matches) != 1:
        return False
    active = active_matches[0]
    registry_snapshot = metadata.get("registry_snapshot")
    if not isinstance(registry_snapshot, dict):
        return False
    return (
        unit.get("active_candidate_id") == CANDIDATE_ID
        and unit.get("approval_status") == "review"
        and unit.get("effects") == registry_snapshot.get("effects")
        and unit.get("localization") == registry_snapshot.get("localization")
        and _canonical_json_bytes(active) == _canonical_json_bytes(expected_active)
        and _registry_refresh_guard_matches(registry, metadata)
    )


def _assert_reusable_output(
    output_root: Path,
    source_hashes: dict[str, object],
    registry_path: Path,
) -> None:
    if not output_root.exists() or not any(
        path.is_file() for path in output_root.rglob("*")
    ):
        return
    metadata_path = output_root / "candidate-metadata.json"
    if not metadata_path.is_file():
        raise ValueError("non_empty_output_missing_metadata")
    metadata = _read_object(metadata_path)
    if metadata.get("candidate_id") != CANDIDATE_ID:
        raise ValueError("candidate_id_mismatch")
    recorded_hashes = metadata.get("source_sha256")
    legacy_hashes = {
        key: value
        for key, value in source_hashes.items()
        if key not in {"card_font_regular", "card_font_bold"}
    }
    legacy_font_upgrade = (
        recorded_hashes == legacy_hashes and "card_rendering" not in metadata
    )
    if recorded_hashes == source_hashes or legacy_font_upgrade:
        return
    if isinstance(recorded_hashes, dict):
        recorded_without_registry = {
            key: value for key, value in recorded_hashes.items() if key != "registry"
        }
        current_without_registry = {
            key: value for key, value in source_hashes.items() if key != "registry"
        }
        registered_refresh = (
            recorded_without_registry == current_without_registry
            and recorded_hashes.get("registry") != source_hashes.get("registry")
            and _registered_candidate_matches_metadata(
                registry_path,
                output_root,
                metadata,
            )
        )
        if registered_refresh:
            return
    raise ValueError("source_hash_mismatch")


def _load_images(inputs: BuildInputs) -> tuple[Image.Image, Image.Image]:
    with Image.open(inputs.appearance_source) as opened:
        appearance = opened.convert("RGBA")
    with Image.open(inputs.niko_atlas) as opened:
        atlas = opened.convert("RGBA")
    if appearance.size != FRAME_SIZE:
        raise ValueError("appearance_dimensions")
    if atlas.size != ATLAS_SIZE:
        raise ValueError("atlas_dimensions")
    return appearance, atlas


def _build_anchors(checker: object, appearance: Image.Image, profile: dict[str, object]) -> dict[str, object]:
    aperture = checker.find_largest_enclosed_transparent_region(appearance)
    aperture_center = (
        aperture.left + (aperture.right - aperture.left - 1) / 2,
        aperture.top + (aperture.bottom - aperture.top - 1) / 2,
    )
    frames = profile.get("frames")
    if not isinstance(frames, list) or len(frames) != 8:
        raise ValueError("rig_frame_count")
    anchor_frames: list[dict[str, object]] = []
    for index, frame in enumerate(frames):
        if not isinstance(frame, dict):
            raise ValueError("invalid_rig_frame")
        face_center = frame.get("face_center")
        if not isinstance(face_center, list) or len(face_center) != 2:
            raise ValueError("invalid_face_center")
        offset = [
            round(float(face_center[0]) - aperture_center[0] * SHARED_SCALE),
            round(float(face_center[1]) - aperture_center[1] * SHARED_SCALE),
        ]
        anchor_frames.append(
            {
                "depth": 40,
                "frame_index": index,
                "frame_name": f"walk_down_{index + 1:02d}",
                "offset": offset,
                "scale": SHARED_SCALE,
            }
        )
    return {
        "algorithm": {
            "feature": "largest four-connected enclosed transparent aperture",
            "offset": "round(face_center - aperture_center * shared_scale)",
            "resampling": "nearest for QA composite only; source appearance remains unchanged",
        },
        "asset_id": ASSET_ID,
        "candidate_id": CANDIDATE_ID,
        "flip_behavior": "none",
        "frame_count": 8,
        "frames": anchor_frames,
        "occupied_slots": [],
        "schema_version": "gogobro-item-anchors-v1",
        "shared_scale": SHARED_SCALE,
        "slot": "head",
    }


def _scaled_appearance(appearance: Image.Image) -> Image.Image:
    size = (round(appearance.width * SHARED_SCALE), round(appearance.height * SHARED_SCALE))
    return appearance.resize(size, Image.Resampling.NEAREST)


def _compose_atlas(atlas: Image.Image, appearance: Image.Image, anchors: dict[str, object]) -> Image.Image:
    composite = atlas.copy()
    scaled = _scaled_appearance(appearance)
    for frame in anchors["frames"]:
        index = int(frame["frame_index"])
        offset_x, offset_y = (int(value) for value in frame["offset"])
        frame_image = composite.crop((index * 128, 0, (index + 1) * 128, 128))
        frame_image.alpha_composite(scaled, dest=(offset_x, offset_y))
        composite.paste(frame_image, (index * 128, 0))
    return composite


def _save_runtime_preview(composite: Image.Image, path: Path) -> None:
    canvas = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((0, 760, 1919, 1079), fill=(33, 42, 52, 255))
    enlarged = composite.resize((1024 * 3, 128 * 3), Image.Resampling.NEAREST)
    frame = enlarged.crop((0, 0, 384, 384))
    canvas.alpha_composite(frame, dest=((1920 - 384) // 2, 520))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)


def _save_harmony_overlay(
    composite: Image.Image, frame_boxes: object, path: Path
) -> None:
    overlay = composite.copy()
    draw = ImageDraw.Draw(overlay)
    if isinstance(frame_boxes, list):
        for index, box in enumerate(frame_boxes):
            if isinstance(box, list) and len(box) == 4:
                left, top, right, bottom = (int(value) for value in box)
                x_offset = index * FRAME_SIZE[0]
                draw.rectangle(
                    (x_offset + left, top, x_offset + right - 1, bottom - 1),
                    outline=(255, 0, 255, 255),
                    width=1,
                )
    overlay.save(path)


def _save_harmony_actual_size(composite: Image.Image, path: Path) -> None:
    canvas = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    canvas.alpha_composite(
        composite,
        dest=((canvas.width - composite.width) // 2, (canvas.height - composite.height) // 2),
    )
    canvas.save(path)


def _image_checks(image: Image.Image) -> dict[str, object]:
    pixels = list(image.get_flattened_data())
    alpha_values = sorted({pixel[3] for pixel in pixels})
    opaque_colors = sorted({pixel[:3] for pixel in pixels if pixel[3]})
    return {
        "alpha_values": alpha_values,
        "binary_alpha": all(value in (0, 255) for value in alpha_values),
        "opaque_color_count": len(opaque_colors),
        "transparent_rgb_zero": all(
            pixel[:3] == (0, 0, 0) for pixel in pixels if pixel[3] == 0
        ),
    }


def _effect_labels(effects: object) -> list[str]:
    labels: list[str] = []
    operations = {
        "armor": ("护甲", "Armor", ""),
        "move_speed_pct": ("移速", "Move Speed", "%"),
    }
    if not isinstance(effects, list):
        return labels
    for effect in effects:
        if not isinstance(effect, dict):
            continue
        operation = str(effect.get("operation", ""))
        value = effect.get("value")
        if operation not in operations or not isinstance(value, int | float):
            labels.append(json.dumps(effect, ensure_ascii=False, sort_keys=True))
            continue
        zh_name, en_name, suffix = operations[operation]
        sign = "+" if value > 0 else "−" if value < 0 else ""
        magnitude = abs(value)
        rendered = str(int(magnitude)) if float(magnitude).is_integer() else str(magnitude)
        labels.append(f"{sign}{rendered}{suffix} {zh_name} / {sign}{rendered}{suffix} {en_name}")
    return labels


def _registry_unit(registry: dict[str, object]) -> dict[str, object]:
    units = registry.get("units")
    if not isinstance(units, list):
        raise ValueError("registry_units_missing")
    matches = [unit for unit in units if isinstance(unit, dict) and unit.get("asset_id") == ASSET_ID]
    if len(matches) != 1:
        raise ValueError("registry_asset_missing")
    return matches[0]


def _font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    if not path.is_file():
        raise FileNotFoundError(path)
    return ImageFont.truetype(str(path), size)


def _draw_wrapped(
    draw: ImageDraw.ImageDraw,
    text: str,
    xy: tuple[int, int],
    font: ImageFont.ImageFont,
    fill: tuple[int, int, int, int],
    max_width: int,
    line_gap: int = 8,
) -> int:
    words = text.split(" ")
    lines: list[str] = []
    current = ""
    for word in words:
        proposed = word if not current else f"{current} {word}"
        if current and draw.textbbox((0, 0), proposed, font=font)[2] > max_width:
            lines.append(current)
            current = word
        else:
            current = proposed
    if current:
        lines.append(current)
    x, y = xy
    height = draw.textbbox((0, 0), "Ag", font=font)[3] + line_gap
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        y += height
    return y


def _approval_card(
    icon: Image.Image,
    appearance: Image.Image,
    composite: Image.Image,
    unit: dict[str, object],
    report: object,
    font_regular: Path,
    font_bold: Path,
) -> Image.Image:
    card = Image.new("RGBA", (1800, 1200), (15, 19, 27, 255))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((48, 48, 1752, 1152), radius=28, fill=(25, 32, 44, 255), outline=(75, 94, 120, 255), width=3)
    title_font = _font(font_bold, 54)
    heading_font = _font(font_bold, 30)
    body_font = _font(font_regular, 25)
    small_font = _font(font_regular, 20)
    draw.text((92, 82), "Smoke-Shell Helmet / 封烟头盔", font=title_font, fill=(236, 242, 250, 255))
    unit_status = str(unit.get("approval_status", "review"))
    status_text = (
        f"Harmony gate: {report.verdict} | Unit approval status: {unit_status}"
    )
    draw.text((94, 154), f"{CANDIDATE_ID}  •  {status_text}", font=heading_font, fill=(113, 210, 182, 255))

    draw.rounded_rectangle((92, 220, 492, 680), radius=18, fill=(12, 16, 23, 255))
    draw.text((120, 248), "Canonical icon", font=heading_font, fill=(228, 235, 244, 255))
    card.alpha_composite(icon, dest=(164, 310))
    draw.text((120, 592), "256×256 at exact 1:1 — no resampling", font=small_font, fill=(177, 190, 208, 255))

    draw.rounded_rectangle((520, 220, 1708, 680), radius=18, fill=(12, 16, 23, 255))
    draw.text((552, 248), "8-frame Niko walk-down composite — exact 1:1", font=heading_font, fill=(228, 235, 244, 255))
    card.alpha_composite(composite, dest=(600, 300))
    draw.text((600, 450), "Appearance 128×128", font=small_font, fill=(177, 190, 208, 255))
    draw.text((600, 474), "exact 1:1 • unchanged", font=small_font, fill=(177, 190, 208, 255))
    card.alpha_composite(appearance, dest=(600, 500))
    draw.text((930, 450), "Runtime frame 001", font=small_font, fill=(177, 190, 208, 255))
    draw.text((930, 474), "128×128 actual 1:1", font=small_font, fill=(177, 190, 208, 255))
    card.alpha_composite(composite.crop((0, 0, 128, 128)), dest=(930, 500))
    draw.text((1110, 505), "True gameplay pixel size", font=heading_font, fill=(236, 198, 94, 255))
    draw.text((1110, 552), "Face aperture and shell hierarchy", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1110, 584), "are judged without display scaling.", font=small_font, fill=(177, 190, 208, 255))

    localization = unit.get("localization", {})
    zh = localization.get("zh_CN", {}) if isinstance(localization, dict) else {}
    en = localization.get("en", {}) if isinstance(localization, dict) else {}
    y = 726
    draw.text((92, y), "Approved copy", font=heading_font, fill=(228, 235, 244, 255))
    y += 48
    for text in (
        str(zh.get("description", "")),
        str(zh.get("flavor", "")),
        str(en.get("description", "")),
        str(en.get("flavor", "")),
    ):
        y = _draw_wrapped(draw, text, (92, y), body_font, (204, 214, 227, 255), 980)
        y += 4

    draw.text((1190, 726), "Structured effects", font=heading_font, fill=(228, 235, 244, 255))
    effect_y = 782
    for label in _effect_labels(unit.get("effects")):
        draw.text((1190, effect_y), label, font=body_font, fill=(246, 198, 94, 255))
        effect_y += 48
    metrics = report.metrics
    draw.text((1190, 914), f"Scale: {SHARED_SCALE}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 948), f"Outer ratio: {metrics['outer_width_ratio']:.6f}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 982), f"Feature error: {metrics['max_feature_center_error_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 1016), f"Residual jitter: {metrics['max_residual_jitter_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text(
        (92, 1092),
        REVIEW_FOOTER_TEXT,
        font=heading_font,
        fill=(239, 116, 116, 255),
    )
    return card


def _approval_card_evidence(unit: dict[str, object], report: object) -> dict[str, object]:
    unit_status = str(unit.get("approval_status", "review"))
    return {
        "appearance": {
            "box": [600, 500, 728, 628],
            "display_scale": 1,
            "resampling": "none",
            "source": "derived/appearance-128.png",
        },
        "composite": {
            "box": [600, 300, 1624, 428],
            "display_scale": 1,
            "resampling": "none",
            "source": "qa/composite-atlas-8x128.png",
        },
        "caption_boxes": {
            "appearance": [600, 450, 850, 496],
            "runtime_actual_size": [930, 450, 1140, 496],
        },
        "icon": {
            "box": [164, 310, 420, 566],
            "display_scale": 1,
            "resampling": "none",
            "source": "derived/icon-256.png",
        },
        "runtime_actual_size": {
            "box": [930, 500, 1058, 628],
            "display_scale": 1,
            "resampling": "none",
            "source": "qa/composite-frame-001.png",
        },
        "footer_text": REVIEW_FOOTER_TEXT,
        "status_text": (
            f"Harmony gate: {report.verdict} | Unit approval status: {unit_status}"
        ),
    }


def _default_visual_rubric() -> dict[str, object]:
    return {
        name: {"evidence": "", "score": 0}
        for name in RUBRIC_DIMENSIONS
    }


def _rubric_scores_for_evidence_revision(payload: bytes) -> dict[str, int]:
    rubric = json.loads(payload.decode("utf-8"))
    if not isinstance(rubric, dict) or set(rubric) != set(RUBRIC_DIMENSIONS):
        raise ValueError("visual_rubric_dimensions_changed")
    scores: dict[str, int] = {}
    for name in RUBRIC_DIMENSIONS:
        dimension = rubric.get(name)
        if not isinstance(dimension, dict) or set(dimension) != {"score", "evidence"}:
            raise ValueError("visual_rubric_dimensions_changed")
        score = dimension.get("score")
        evidence = dimension.get("evidence")
        if (
            not isinstance(score, int)
            or isinstance(score, bool)
            or score < 0
            or score > 2
            or not isinstance(evidence, str)
            or not evidence.strip()
        ):
            raise ValueError("visual_rubric_revision_invalid")
        scores[name] = score
    return scores


def _assert_evidence_only_rubric_revision(
    existing: bytes,
    supplied: bytes,
) -> None:
    if _rubric_scores_for_evidence_revision(existing) != _rubric_scores_for_evidence_revision(
        supplied
    ):
        raise ValueError("visual_rubric_scores_changed")


def _load_visual_rubric(checker: object, path: Path) -> object:
    payload = _read_object(path)
    dimensions: list[tuple[int, str]] = []
    for name in RUBRIC_DIMENSIONS:
        value = payload[name]
        if isinstance(value, dict):
            dimensions.append((int(value["score"]), str(value["evidence"])))
        else:
            dimensions.append((int(value[0]), str(value[1])))
    return checker.VisualRubric(*dimensions)


def _artifact_manifest(stage: Path) -> list[dict[str, object]]:
    artifacts: list[dict[str, object]] = []
    for relative in ARTIFACT_PATHS:
        path = stage / relative
        entry: dict[str, object] = {
            "bytes": path.stat().st_size,
            "path": relative,
            "role": ARTIFACT_ROLES[relative],
            "sha256": _sha256(path),
        }
        if path.suffix.lower() == ".png":
            with Image.open(path) as opened:
                entry["dimensions"] = list(opened.size)
                entry["output_spec"] = {
                    "alpha": "A" in opened.getbands(),
                    "format": "PNG",
                    "height": opened.height,
                    "width": opened.width,
                }
        else:
            entry["output_spec"] = {"format": "JSON"}
            if relative == "appearance/anchors-walk-down.json":
                entry["output_spec"].update({"anchor_count": 8, "state": "walk_down"})
        artifacts.append(entry)
    return artifacts


def _replace_file(source: Path, target: Path) -> Path:
    return source.replace(target)


def _transaction_paths(output_root: Path) -> tuple[Path, Path]:
    marker = output_root / TRANSACTION_MARKER
    return marker, marker.with_name(f"{marker.name}.tmp")


def _atomic_transaction_marker(path: Path, payload: dict[str, object]) -> None:
    temporary = path.with_name(f"{path.name}.tmp")
    _write_json(temporary, payload)
    _replace_file(temporary, path)


def _validated_transaction(
    output_root: Path, payload: dict[str, object]
) -> tuple[Path, list[dict[str, object]]]:
    if payload.get("candidate_id") != CANDIDATE_ID:
        raise RuntimeError("invalid_transaction_marker")
    backup_name = payload.get("backup_dir")
    entries = payload.get("entries")
    if (
        not isinstance(backup_name, str)
        or Path(backup_name).name != backup_name
        or not backup_name.startswith(".candidate-002-txn-")
        or not isinstance(entries, list)
    ):
        raise RuntimeError("invalid_transaction_marker")
    backup_dir = (output_root.parent / backup_name).resolve()
    if backup_dir.parent != output_root.parent.resolve():
        raise RuntimeError("invalid_transaction_marker")
    allowed = {*ARTIFACT_PATHS, "candidate-metadata.json"}
    normalized: list[dict[str, object]] = []
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("relative") not in allowed:
            raise RuntimeError("invalid_transaction_marker")
        relative = str(entry["relative"])
        backup = entry.get("backup")
        if backup is not None and (
            not isinstance(backup, str) or Path(backup).name != backup
        ):
            raise RuntimeError("invalid_transaction_marker")
        normalized.append({**entry, "relative": relative})
    return backup_dir, normalized


def _verify_transaction_targets(
    output_root: Path,
    entries: list[dict[str, object]],
    hash_field: str,
) -> None:
    for entry in entries:
        expected = entry.get(hash_field)
        target = output_root / str(entry["relative"])
        if expected is None:
            if target.exists():
                raise RuntimeError("transaction_target_mismatch")
        elif not target.is_file() or _sha256(target) != expected:
            raise RuntimeError("transaction_target_mismatch")


def _finish_transaction(output_root: Path, payload: dict[str, object]) -> None:
    backup_dir, entries = _validated_transaction(output_root, payload)
    phase = payload.get("phase")
    if phase == "committed":
        _verify_transaction_targets(output_root, entries, "new_sha256")
    elif phase == "rolled_back":
        _verify_transaction_targets(output_root, entries, "old_sha256")
    else:
        raise RuntimeError("invalid_transaction_phase")
    for entry in entries:
        backup = entry.get("backup")
        if isinstance(backup, str):
            (backup_dir / backup).unlink(missing_ok=True)
    if backup_dir.exists():
        backup_dir.rmdir()
    marker, marker_temporary = _transaction_paths(output_root)
    marker_temporary.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)


def _rollback_transaction(output_root: Path, payload: dict[str, object]) -> None:
    backup_dir, entries = _validated_transaction(output_root, payload)
    for entry in entries:
        target = output_root / str(entry["relative"])
        old_hash = entry.get("old_sha256")
        if old_hash is None:
            target.unlink(missing_ok=True)
            continue
        backup = entry.get("backup")
        if not isinstance(backup, str):
            raise RuntimeError("missing_transaction_backup")
        backup_path = backup_dir / backup
        if not backup_path.is_file() or _sha256(backup_path) != old_hash:
            raise RuntimeError("invalid_transaction_backup")
        target.parent.mkdir(parents=True, exist_ok=True)
        recovery = target.with_name(f"{target.name}.recovery.tmp")
        shutil.copyfile(backup_path, recovery)
        _replace_file(recovery, target)
    _verify_transaction_targets(output_root, entries, "old_sha256")
    rolled_back = {**payload, "phase": "rolled_back"}
    marker, _ = _transaction_paths(output_root)
    _atomic_transaction_marker(marker, rolled_back)
    _finish_transaction(output_root, rolled_back)


def _recover_transaction(output_root: Path) -> None:
    marker, marker_temporary = _transaction_paths(output_root)
    if not marker.is_file():
        marker_temporary.unlink(missing_ok=True)
        return
    payload = _read_object(marker)
    phase = payload.get("phase")
    if phase == "prepared":
        _rollback_transaction(output_root, payload)
    elif phase in {"committed", "rolled_back"}:
        _finish_transaction(output_root, payload)
    else:
        raise RuntimeError("invalid_transaction_phase")


def _publish(stage: Path, output_root: Path, *, preserve_rubric: bool) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    relatives = [
        relative
        for relative in ARTIFACT_PATHS
        if not (relative == "qa/visual-rubric.json" and preserve_rubric)
    ]
    relatives.append("candidate-metadata.json")
    backup_dir = Path(
        tempfile.mkdtemp(prefix=".candidate-002-txn-", dir=output_root.parent)
    )
    entries: list[dict[str, object]] = []
    for index, relative in enumerate(relatives):
        target = output_root / relative
        source = stage / relative
        had_original = target.is_file()
        backup_name = f"{index:02d}.backup" if had_original else None
        old_hash = _sha256(target) if had_original else None
        if backup_name is not None:
            shutil.copyfile(target, backup_dir / backup_name)
        entries.append(
            {
                "backup": backup_name,
                "new_sha256": _sha256(source),
                "old_sha256": old_hash,
                "relative": relative,
            }
        )
    marker, _ = _transaction_paths(output_root)
    transaction: dict[str, object] = {
        "backup_dir": backup_dir.name,
        "candidate_id": CANDIDATE_ID,
        "entries": entries,
        "phase": "prepared",
        "reader_contract": "candidate is invalid while this marker exists",
        "schema_version": "gogobro-candidate-transaction-v1",
    }
    try:
        _atomic_transaction_marker(marker, transaction)
        for relative in relatives:
            source = stage / relative
            target = output_root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            _replace_file(source, target)
        committed = {**transaction, "phase": "committed"}
        _atomic_transaction_marker(marker, committed)
        _finish_transaction(output_root, committed)
    except Exception:
        if marker.is_file():
            _recover_transaction(output_root)
        else:
            _, marker_temporary = _transaction_paths(output_root)
            marker_temporary.unlink(missing_ok=True)
            for entry in entries:
                backup = entry.get("backup")
                if isinstance(backup, str):
                    (backup_dir / backup).unlink(missing_ok=True)
            if backup_dir.exists():
                backup_dir.rmdir()
        raise


def build_candidate_002(
    inputs: BuildInputs,
    visual_rubric: Path | None = None,
    *,
    revise_rubric_evidence: bool = False,
) -> CandidateMetadata:
    checker = _load_checker()
    _recover_transaction(inputs.output_root)
    candidate_001 = _validate_inputs(inputs)
    candidate_001_before = _tree_hashes(candidate_001)
    source_hashes = _source_hashes(inputs, candidate_001_before)
    _assert_reusable_output(inputs.output_root, source_hashes, inputs.registry)
    registry_before = str(source_hashes["registry"])
    niko_before = _sha256(inputs.niko_atlas)
    font_regular_before = _sha256(inputs.card_font_regular)
    font_bold_before = _sha256(inputs.card_font_bold)
    existing_rubric_path = inputs.output_root / "qa/visual-rubric.json"
    existing_rubric_bytes = (
        existing_rubric_path.read_bytes() if existing_rubric_path.is_file() else None
    )
    supplied_rubric_bytes = visual_rubric.read_bytes() if visual_rubric else None
    rubric_revision = False
    if revise_rubric_evidence and (
        supplied_rubric_bytes is None or existing_rubric_bytes is None
    ):
        raise ValueError("visual_rubric_revision_requires_existing")
    if (
        supplied_rubric_bytes is not None
        and existing_rubric_bytes is not None
        and supplied_rubric_bytes != existing_rubric_bytes
    ):
        if not revise_rubric_evidence:
            raise ValueError("visual_rubric_mismatch")
        _assert_evidence_only_rubric_revision(
            existing_rubric_bytes,
            supplied_rubric_bytes,
        )
        rubric_revision = True
    rubric_bytes = (
        supplied_rubric_bytes
        if supplied_rubric_bytes is not None
        else existing_rubric_bytes
    )
    rubric_hash = hashlib.sha256(rubric_bytes).hexdigest() if rubric_bytes is not None else None

    appearance, atlas = _load_images(inputs)
    profile = _read_object(inputs.rig_profile)
    registry = _read_object(inputs.registry)
    unit = _registry_unit(registry)
    anchors = _build_anchors(checker, appearance, profile)

    inputs.output_root.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="candidate-002-stage-", dir=inputs.output_root.parent
    ) as temporary:
        stage = Path(temporary)
        derived_appearance = stage / "derived/appearance-128.png"
        derived_icon = stage / "derived/icon-256.png"
        derived_appearance.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(inputs.appearance_source, derived_appearance)
        icon = checker.derive_nearest_2x_icon(appearance)
        icon.save(derived_icon)
        _write_json(stage / "appearance/anchors-walk-down.json", anchors)

        harmony_inputs = checker.HarmonyInputs(
            character_atlas=inputs.niko_atlas,
            appearance=derived_appearance,
            icon=derived_icon,
            anchors=stage / "appearance/anchors-walk-down.json",
            rig_profile=inputs.rig_profile,
            slot="head",
            out_dir=stage / "qa",
        )
        report = checker.analyze_harmony(harmony_inputs)
        if visual_rubric:
            rubric = _load_visual_rubric(checker, visual_rubric)
            report = checker.apply_visual_rubric(report, rubric)
            report_metrics = dict(report.metrics)
            report_metrics["visual_rubric_sha256"] = rubric_hash
            report = replace(report, metrics=report_metrics)
        checker.write_harmony_outputs(report, harmony_inputs)

        composite = _compose_atlas(atlas, appearance, anchors)
        (stage / "qa").mkdir(parents=True, exist_ok=True)
        composite.crop((0, 0, 128, 128)).save(stage / "qa/composite-frame-001.png")
        composite.save(stage / "qa/composite-atlas-8x128.png")
        _save_runtime_preview(composite, stage / "qa/runtime-size-1920x1080.png")
        _save_harmony_overlay(
            composite, report.metrics.get("frame_boxes", []), stage / "qa/harmony-overlay.png"
        )
        _save_harmony_actual_size(composite, stage / "qa/harmony-actual-size.png")
        if rubric_bytes is None:
            _write_json(stage / "qa/visual-rubric.json", _default_visual_rubric())
        else:
            (stage / "qa/visual-rubric.json").write_bytes(rubric_bytes)

        appearance_checks = _image_checks(appearance)
        icon_checks = _image_checks(icon)
        pixel_qa = {
            "approval_card_evidence": _approval_card_evidence(unit, report),
            "candidate_id": CANDIDATE_ID,
            "checks": {
                "appearance_binary_alpha": appearance_checks["binary_alpha"],
                "appearance_bytes_unchanged": derived_appearance.read_bytes()
                == inputs.appearance_source.read_bytes(),
                "appearance_dimensions": list(appearance.size) == list(FRAME_SIZE),
                "appearance_transparent_rgb_zero": appearance_checks["transparent_rgb_zero"],
                "icon_binary_alpha": icon_checks["binary_alpha"],
                "icon_dimensions": list(icon.size) == list(ICON_SIZE),
                "icon_nearest_2x": icon.tobytes()
                == checker.derive_nearest_2x_icon(appearance).tobytes(),
                "icon_transparent_rgb_zero": icon_checks["transparent_rgb_zero"],
                "no_crop": all(
                    0 <= left < right <= 128 and 0 <= top < bottom <= 128
                    for left, top, right, bottom in report.metrics.get("frame_boxes", [])
                ),
                "protected_eye_occlusion_zero": report.metrics.get(
                    "max_protected_occlusion_ratio"
                )
                == 0,
            },
            "metrics": {
                "appearance_opaque_color_count": appearance_checks["opaque_color_count"],
                "icon_opaque_color_count": icon_checks["opaque_color_count"],
            },
            "passed": False,
        }
        pixel_qa["passed"] = all(pixel_qa["checks"].values())
        _write_json(stage / "qa/pixel-qa-report.json", pixel_qa)
        card = _approval_card(
            icon,
            appearance,
            composite,
            unit,
            report,
            inputs.card_font_regular,
            inputs.card_font_bold,
        )
        card.save(stage / "qa/approval-card.png")

        artifacts = _artifact_manifest(stage)
        metadata = CandidateMetadata(
            candidate_id=CANDIDATE_ID,
            transform={
                "aperture_box": report.metrics.get("aperture_box"),
                "integer_offsets": [frame["offset"] for frame in anchors["frames"]],
                "shared_scale": SHARED_SCALE,
            },
            artifacts=artifacts,
            metrics=dict(report.metrics),
        )
        metadata_payload = {
            **asdict(metadata),
            "asset_id": ASSET_ID,
            "card_rendering": {
                "evidence": pixel_qa["approval_card_evidence"],
                "fonts": {
                    "bold": {
                        "path": str(inputs.card_font_bold.resolve()),
                        "sha256": font_bold_before,
                    },
                    "regular": {
                        "path": str(inputs.card_font_regular.resolve()),
                        "sha256": font_regular_before,
                    },
                },
            },
            "harmony_verdict": report.verdict,
            "publication": {
                "transaction_marker": TRANSACTION_MARKER,
                "valid_when_marker_absent": True,
            },
            "reason_codes": list(report.reason_codes),
            "registry_snapshot": {
                "effects": unit.get("effects", []),
                "localization": unit.get("localization", {}),
            },
            "source_sha256": source_hashes,
            "visual_rubric_sha256": rubric_hash,
        }
        registry_snapshot = metadata_payload["registry_snapshot"]
        if not isinstance(registry_snapshot, dict):
            raise RuntimeError("invalid_registry_snapshot")
        registry_snapshot["refresh_guard"] = _registry_refresh_guard(
            registry,
            metadata_payload,
        )
        _write_json(stage / "candidate-metadata.json", metadata_payload)

        if (
            _sha256(inputs.card_font_regular) != font_regular_before
            or _sha256(inputs.card_font_bold) != font_bold_before
        ):
            raise RuntimeError("card_font_changed")
        source_unchanged = (
            _tree_hashes(candidate_001) == candidate_001_before
            and _sha256(inputs.niko_atlas) == niko_before == LOCKED_NIKO_HASH
            and _sha256(inputs.registry) == registry_before
        )
        if not source_unchanged:
            raise RuntimeError("source_changed")
        if (
            supplied_rubric_bytes is not None
            and visual_rubric is not None
            and visual_rubric.read_bytes() != supplied_rubric_bytes
        ):
            raise RuntimeError("visual_rubric_changed")
        _publish(
            stage,
            inputs.output_root,
            preserve_rubric=(
                existing_rubric_bytes is not None and not rubric_revision
            ),
        )
    return metadata


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appearance-source", type=Path, required=True)
    parser.add_argument("--niko-atlas", type=Path, required=True)
    parser.add_argument("--rig-profile", type=Path, required=True)
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--visual-rubric", type=Path)
    parser.add_argument("--revise-rubric-evidence", action="store_true")
    parser.add_argument("--card-font-regular", type=Path, default=DEFAULT_CARD_FONT_REGULAR)
    parser.add_argument("--card-font-bold", type=Path, default=DEFAULT_CARD_FONT_BOLD)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    metadata = build_candidate_002(
        BuildInputs(
            appearance_source=arguments.appearance_source,
            niko_atlas=arguments.niko_atlas,
            rig_profile=arguments.rig_profile,
            registry=arguments.registry,
            output_root=arguments.output_root,
            card_font_regular=arguments.card_font_regular,
            card_font_bold=arguments.card_font_bold,
        ),
        visual_rubric=arguments.visual_rubric,
        revise_rubric_evidence=arguments.revise_rubric_evidence,
    )
    verdict = json.loads(
        (arguments.output_root / "candidate-metadata.json").read_text(encoding="utf-8")
    )["harmony_verdict"]
    print(
        json.dumps(
            {
                "candidate_id": metadata.candidate_id,
                "metrics": metadata.metrics,
                "verdict": verdict,
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 2 if verdict == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
