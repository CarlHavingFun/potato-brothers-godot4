"""Build the deterministic Smoke-Shell Helmet review candidate 002."""

from __future__ import annotations

import argparse
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


def _source_hashes(inputs: BuildInputs, candidate_001_hashes: dict[str, str]) -> dict[str, object]:
    return {
        "appearance_source": _sha256(inputs.appearance_source),
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


def _assert_reusable_output(output_root: Path, source_hashes: dict[str, object]) -> None:
    if not output_root.exists() or not any(output_root.iterdir()):
        return
    metadata_path = output_root / "candidate-metadata.json"
    if not metadata_path.is_file():
        raise ValueError("non_empty_output_missing_metadata")
    metadata = _read_object(metadata_path)
    if metadata.get("candidate_id") != CANDIDATE_ID:
        raise ValueError("candidate_id_mismatch")
    if metadata.get("source_sha256") != source_hashes:
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


def _font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = (
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    )
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


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
) -> Image.Image:
    card = Image.new("RGBA", (1800, 1200), (15, 19, 27, 255))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((48, 48, 1752, 1152), radius=28, fill=(25, 32, 44, 255), outline=(75, 94, 120, 255), width=3)
    title_font = _font(54, bold=True)
    heading_font = _font(30, bold=True)
    body_font = _font(25)
    small_font = _font(20)
    draw.text((92, 82), "Smoke-Shell Helmet / 封烟头盔", font=title_font, fill=(236, 242, 250, 255))
    draw.text((94, 154), f"{CANDIDATE_ID}  •  preliminary verdict: {report.verdict}", font=heading_font, fill=(113, 210, 182, 255))

    draw.rounded_rectangle((92, 220, 540, 668), radius=18, fill=(12, 16, 23, 255))
    icon_large = icon.resize((384, 384), Image.Resampling.NEAREST)
    card.alpha_composite(icon_large, dest=(124, 252))
    draw.text((92, 686), "Derived icon: exact NEAREST 2×", font=small_font, fill=(177, 190, 208, 255))

    draw.rounded_rectangle((588, 220, 1708, 668), radius=18, fill=(12, 16, 23, 255))
    contact = composite.resize((1024, 128), Image.Resampling.NEAREST)
    card.alpha_composite(contact, dest=(636, 320))
    appearance_preview = appearance.resize((256, 256), Image.Resampling.NEAREST)
    card.alpha_composite(appearance_preview, dest=(1015, 402))
    draw.text((628, 254), "8-frame Niko walk-down composite", font=heading_font, fill=(228, 235, 244, 255))
    draw.text((628, 610), "Appearance source copied unchanged; only integer anchor offsets vary.", font=small_font, fill=(177, 190, 208, 255))

    localization = unit.get("localization", {})
    zh = localization.get("zh_CN", {}) if isinstance(localization, dict) else {}
    en = localization.get("en", {}) if isinstance(localization, dict) else {}
    y = 748
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

    draw.text((1190, 748), "Structured effects", font=heading_font, fill=(228, 235, 244, 255))
    effect_y = 804
    for label in _effect_labels(unit.get("effects")):
        draw.text((1190, effect_y), label, font=body_font, fill=(246, 198, 94, 255))
        effect_y += 48
    metrics = report.metrics
    draw.text((1190, 930), f"Scale: {SHARED_SCALE}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 964), f"Outer ratio: {metrics['outer_width_ratio']:.6f}", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 998), f"Feature error: {metrics['max_feature_center_error_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text((1190, 1032), f"Residual jitter: {metrics['max_residual_jitter_px']:.4f}px", font=small_font, fill=(177, 190, 208, 255))
    draw.text((92, 1092), "REVIEW EVIDENCE ONLY — no curated, runtime, startup, or registry mutation", font=heading_font, fill=(239, 116, 116, 255))
    return card


def _default_visual_rubric() -> dict[str, object]:
    return {
        name: {"evidence": "", "score": 0}
        for name in ("identity", "function", "material", "hierarchy", "originality")
    }


def _load_visual_rubric(checker: object, path: Path) -> object:
    payload = _read_object(path)
    dimensions: list[tuple[int, str]] = []
    for name in ("identity", "function", "material", "hierarchy", "originality"):
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


def _publish(stage: Path, output_root: Path, *, preserve_rubric: bool) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    for relative in ARTIFACT_PATHS:
        if relative == "qa/visual-rubric.json" and preserve_rubric:
            continue
        source = stage / relative
        target = output_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        source.replace(target)
    metadata_source = stage / "candidate-metadata.json"
    metadata_target = output_root / "candidate-metadata.json"
    metadata_source.replace(metadata_target)


def build_candidate_002(
    inputs: BuildInputs, visual_rubric: Path | None = None
) -> CandidateMetadata:
    checker = _load_checker()
    candidate_001 = _validate_inputs(inputs)
    candidate_001_before = _tree_hashes(candidate_001)
    source_hashes = _source_hashes(inputs, candidate_001_before)
    _assert_reusable_output(inputs.output_root, source_hashes)
    registry_before = _sha256(inputs.registry)
    niko_before = _sha256(inputs.niko_atlas)
    rubric_bytes = visual_rubric.read_bytes() if visual_rubric else None
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
        card = _approval_card(icon, appearance, composite, unit, report)
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
            "harmony_verdict": report.verdict,
            "reason_codes": list(report.reason_codes),
            "registry_snapshot": {
                "effects": unit.get("effects", []),
                "localization": unit.get("localization", {}),
            },
            "source_sha256": source_hashes,
            "visual_rubric_sha256": rubric_hash,
        }
        _write_json(stage / "candidate-metadata.json", metadata_payload)

        source_unchanged = (
            _tree_hashes(candidate_001) == candidate_001_before
            and _sha256(inputs.niko_atlas) == niko_before == LOCKED_NIKO_HASH
            and _sha256(inputs.registry) == registry_before
        )
        if not source_unchanged:
            raise RuntimeError("source_changed")
        if rubric_bytes is not None and visual_rubric.read_bytes() != rubric_bytes:
            raise RuntimeError("visual_rubric_changed")
        _publish(
            stage,
            inputs.output_root,
            preserve_rubric=(inputs.output_root / "qa/visual-rubric.json").is_file(),
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
        ),
        visual_rubric=arguments.visual_rubric,
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
