"""Deterministic hard-gate checks for GOGOBRO item appearance layers."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import deque
from collections.abc import Sequence
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image, ImageDraw


@dataclass(frozen=True)
class Box:
    left: int
    top: int
    right: int
    bottom: int


@dataclass(frozen=True)
class HarmonyInputs:
    character_atlas: Path
    appearance: Path
    icon: Path
    anchors: Path
    rig_profile: Path
    slot: str
    out_dir: Path


@dataclass(frozen=True)
class HarmonyReport:
    verdict: str
    reason_codes: Sequence[str]
    metrics: dict[str, object]
    input_sha256: dict[str, str]


@dataclass(frozen=True)
class VisualRubric:
    identity: tuple[int, str]
    function: tuple[int, str]
    material: tuple[int, str]
    hierarchy: tuple[int, str]
    originality: tuple[int, str]


def derive_nearest_2x_icon(appearance: Image.Image) -> Image.Image:
    return appearance.resize((256, 256), Image.Resampling.NEAREST)


def placed_feature_center(
    source_center: tuple[float, float], scale: float, offset: tuple[int, int]
) -> tuple[float, float]:
    return (offset[0] + source_center[0] * scale, offset[1] + source_center[1] * scale)


def find_largest_enclosed_transparent_region(image: Image.Image) -> Box:
    """Return the largest four-connected transparent region not touching an edge."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = rgba.getchannel("A")
    transparent = {(x, y) for y in range(height) for x in range(width) if alpha.getpixel((x, y)) == 0}
    visited: set[tuple[int, int]] = set()
    largest: list[tuple[int, int]] = []
    for seed in sorted(transparent):
        if seed in visited:
            continue
        region: list[tuple[int, int]] = []
        queue: deque[tuple[int, int]] = deque([seed])
        visited.add(seed)
        touches_edge = False
        while queue:
            x, y = queue.popleft()
            region.append((x, y))
            touches_edge |= x in (0, width - 1) or y in (0, height - 1)
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in transparent and neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(neighbor)
        if not touches_edge and len(region) > len(largest):
            largest = region
    if not largest:
        raise ValueError("no_enclosed_transparent_region")
    xs, ys = zip(*largest, strict=True)
    return Box(min(xs), min(ys), max(xs) + 1, max(ys) + 1)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def _alpha_bounds(image: Image.Image) -> Box | None:
    alpha = image.convert("RGBA").getchannel("A")
    bbox = alpha.getbbox()
    return None if bbox is None else Box(*bbox)


def _add(reasons: set[str], condition: bool, code: str) -> None:
    if condition:
        reasons.add(code)


def _profile_frames(profile: dict[str, object]) -> list[dict[str, object]]:
    frames = profile.get("frames", [])
    return frames if isinstance(frames, list) else []


def _slot_profile(profile: dict[str, object], slot: str) -> dict[str, object]:
    profiles = profile.get("slot_profiles", {})
    if not isinstance(profiles, dict):
        return {}
    selected = profiles.get(slot, {})
    return selected if isinstance(selected, dict) else {}


def _as_pair(value: object) -> tuple[float, float]:
    if not isinstance(value, list | tuple) or len(value) != 2:
        raise ValueError("expected coordinate pair")
    return (float(value[0]), float(value[1]))


def _placed_box(bounds: Box, scale: float, offset: tuple[int, int]) -> Box:
    return Box(
        math.floor(offset[0] + bounds.left * scale),
        math.floor(offset[1] + bounds.top * scale),
        math.ceil(offset[0] + bounds.right * scale),
        math.ceil(offset[1] + bounds.bottom * scale),
    )


def _has_occlusion(
    appearance: Image.Image,
    protected: list[object],
    scale: float,
    offset: tuple[int, int],
) -> bool:
    if len(protected) != 4:
        return True
    alpha = appearance.convert("RGBA").getchannel("A")
    left, top, right, bottom = (int(value) for value in protected)
    for y in range(top, bottom):
        for x in range(left, right):
            source_x = math.floor((x - offset[0]) / scale)
            source_y = math.floor((y - offset[1]) / scale)
            if 0 <= source_x < appearance.width and 0 <= source_y < appearance.height:
                if alpha.getpixel((source_x, source_y)) != 0:
                    return True
    return False


def _pixel_reason_codes(appearance: Image.Image, palette_limit: int) -> set[str]:
    reasons: set[str] = set()
    rgba = appearance.convert("RGBA")
    opaque_colors: set[tuple[int, int, int]] = set()
    for red, green, blue, alpha in rgba.get_flattened_data():
        _add(reasons, alpha not in (0, 255), "non_binary_alpha")
        _add(reasons, alpha == 0 and (red != 0 or green != 0 or blue != 0), "transparent_rgb")
        if alpha:
            opaque_colors.add((red, green, blue))
            _add(reasons, green >= 200 and red <= 30 and blue <= 30, "chroma_residue")
            _add(reasons, red >= 200 and green <= 30 and blue >= 200, "chroma_residue")
    _add(reasons, len(opaque_colors) > palette_limit, "palette_limit")
    return reasons


def analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport:
    paths = {
        "character_atlas": inputs.character_atlas,
        "appearance": inputs.appearance,
        "icon": inputs.icon,
        "anchors": inputs.anchors,
        "rig_profile": inputs.rig_profile,
    }
    input_sha256 = {name: _sha256(path) for name, path in paths.items()}
    reasons: set[str] = set()
    anchors = _read_json(inputs.anchors)
    profile = _read_json(inputs.rig_profile)
    frames = _profile_frames(profile)
    contract = _slot_profile(profile, inputs.slot)
    with Image.open(inputs.character_atlas) as opened_atlas:
        atlas = opened_atlas.convert("RGBA")
    with Image.open(inputs.appearance) as opened_appearance:
        appearance = opened_appearance.convert("RGBA")
    with Image.open(inputs.icon) as opened_icon:
        icon = opened_icon.convert("RGBA")

    frame_size = profile.get("frame_size", [128, 128])
    atlas_size = profile.get("atlas_size", [128 * len(frames), 128])
    _add(reasons, tuple(frame_size) != appearance.size, "appearance_dimensions")
    _add(reasons, tuple(atlas_size) != atlas.size, "atlas_dimensions")
    _add(reasons, not contract, "unknown_slot")
    _add(reasons, inputs.slot != anchors.get("slot"), "slot_mismatch")
    _add(reasons, appearance.size != (128, 128), "appearance_dimensions")
    _add(reasons, icon.size != (256, 256), "icon_dimensions")
    if icon.size == (256, 256):
        _add(
            reasons,
            list(icon.get_flattened_data())
            != list(derive_nearest_2x_icon(appearance).get_flattened_data()),
            "icon_not_nearest_2x",
        )
    palette_limit = int(contract.get("max_palette_colors", 8))
    reasons.update(_pixel_reason_codes(appearance, palette_limit))

    bounds = _alpha_bounds(appearance)
    _add(reasons, bounds is None, "empty_appearance")
    try:
        aperture = find_largest_enclosed_transparent_region(appearance)
    except ValueError:
        aperture = None
        reasons.add("missing_feature_aperture")

    anchor_frames = anchors.get("frames", [])
    if not isinstance(anchor_frames, list):
        anchor_frames = []
    _add(reasons, len(anchor_frames) != len(frames), "anchor_count")
    occupied = anchors.get("occupied_slots", [])
    _add(reasons, isinstance(occupied, list) and inputs.slot in occupied, "duplicate_slot")

    ratio_bounds = bounds if bounds is not None else Box(0, 0, 0, 0)
    placed_widths: list[float] = []
    feature_errors: list[float] = []
    residuals: list[tuple[float, float]] = []
    frame_boxes: list[list[int]] = []
    expected_depth = contract.get("expected_depth")
    for index, (frame, anchor) in enumerate(zip(frames, anchor_frames, strict=False)):
        if not isinstance(frame, dict) or not isinstance(anchor, dict):
            reasons.add("invalid_frame_data")
            continue
        try:
            scale = float(anchor["scale"])
            offset_values = _as_pair(anchor["offset"])
            offset = (int(offset_values[0]), int(offset_values[1]))
            if offset != offset_values:
                reasons.add("non_integer_offset")
            face = _as_pair(frame["face_center"])
        except (KeyError, TypeError, ValueError):
            reasons.add("invalid_frame_data")
            continue
        _add(reasons, scale <= 0, "invalid_scale")
        if expected_depth is not None:
            _add(reasons, anchor.get("depth") != expected_depth, "depth_mismatch")
        placed = _placed_box(ratio_bounds, scale, offset)
        frame_boxes.append([placed.left, placed.top, placed.right, placed.bottom])
        placed_widths.append((ratio_bounds.right - ratio_bounds.left) * scale)
        _add(
            reasons,
            placed.left < 0 or placed.top < 0 or placed.right > appearance.width or placed.bottom > appearance.height,
            "crop",
        )
        protected = frame.get("protected_regions", {})
        eyes = protected.get("eyes", []) if isinstance(protected, dict) else []
        _add(reasons, _has_occlusion(appearance, eyes, scale, offset), "protected_region_occlusion")
        if aperture is not None:
            source_feature = (
                aperture.left + (aperture.right - aperture.left - 1) / 2,
                aperture.top + (aperture.bottom - aperture.top - 1) / 2,
            )
            placed_feature = placed_feature_center(source_feature, scale, offset)
            delta = (placed_feature[0] - face[0], placed_feature[1] - face[1])
            feature_errors.append(max(abs(delta[0]), abs(delta[1])))
            residuals.append(delta)

    head_widths = [float(frame.get("head_width", 0)) for frame in frames if isinstance(frame, dict)]
    outer_ratio = max(placed_widths, default=0) / head_widths[0] if head_widths and head_widths[0] else 0
    allowed_ratio = contract.get("outer_width_ratio", [0, float("inf")])
    low_ratio, high_ratio = (float(allowed_ratio[0]), float(allowed_ratio[1]))
    _add(reasons, outer_ratio < low_ratio, "scale_ratio_low")
    _add(reasons, outer_ratio > high_ratio, "scale_ratio_high")
    max_feature_error = max(feature_errors, default=0)
    _add(reasons, max_feature_error > float(contract.get("feature_center_max_px", 1)), "feature_center_offset")
    first_residual = residuals[0] if residuals else (0.0, 0.0)
    max_jitter = max(
        (max(abs(value[0] - first_residual[0]), abs(value[1] - first_residual[1])) for value in residuals),
        default=0,
    )
    _add(reasons, max_jitter > float(contract.get("residual_jitter_max_px", 1)), "residual_jitter")

    after_sha256 = {name: _sha256(path) for name, path in paths.items()}
    _add(reasons, input_sha256 != after_sha256, "source_changed")
    metrics: dict[str, object] = {
        "outer_width_ratio": outer_ratio,
        "max_feature_center_error_px": max_feature_error,
        "max_residual_jitter_px": max_jitter,
        "frame_boxes": frame_boxes,
        "frame_count": len(frames),
        "aperture_box": asdict(aperture) if aperture else None,
    }
    return HarmonyReport(
        verdict="hard_fail" if reasons else "review",
        reason_codes=tuple(sorted(reasons)),
        metrics=metrics,
        input_sha256=after_sha256,
    )


def apply_visual_rubric(report: HarmonyReport, rubric: VisualRubric) -> HarmonyReport:
    if report.verdict == "hard_fail":
        return report
    dimensions = (
        rubric.identity,
        rubric.function,
        rubric.material,
        rubric.hierarchy,
        rubric.originality,
    )
    complete = all(isinstance(score, int) and 0 <= score <= 2 and bool(evidence.strip()) for score, evidence in dimensions)
    total = sum(score for score, _ in dimensions) if complete else 0
    verdict = "harmony_pass" if complete and total >= 8 and all(score > 0 for score, _ in dimensions) else "review"
    reasons = set(report.reason_codes)
    if not complete:
        reasons.add("visual_rubric_incomplete")
    elif verdict == "review":
        reasons.add("visual_rubric_review")
    metrics = dict(report.metrics)
    metrics["visual_rubric_total"] = total
    return HarmonyReport(verdict, tuple(sorted(reasons)), metrics, report.input_sha256)


def _write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_harmony_outputs(report: HarmonyReport, inputs: HarmonyInputs) -> None:
    inputs.out_dir.mkdir(parents=True, exist_ok=True)
    _write_json(inputs.out_dir / "harmony-report.json", asdict(report))
    with Image.open(inputs.character_atlas) as opened_atlas:
        atlas = opened_atlas.convert("RGBA")
    overlay = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for index, box in enumerate(report.metrics.get("frame_boxes", [])):
        left, top, right, bottom = (int(value) for value in box)
        x_offset = index * 128
        draw.rectangle((x_offset + left, top, x_offset + right - 1, bottom - 1), outline=(255, 0, 255, 255), width=1)
    overlay.save(inputs.out_dir / "harmony-overlay.png")
    preview = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    preview.paste(atlas, ((1920 - atlas.width) // 2, (1080 - atlas.height) // 2), atlas)
    preview.save(inputs.out_dir / "harmony-actual-size.png")


def _rubric_from_json(path: Path) -> VisualRubric:
    payload = _read_json(path)
    values: list[tuple[int, str]] = []
    for name in ("identity", "function", "material", "hierarchy", "originality"):
        value = payload[name]
        if isinstance(value, dict):
            values.append((int(value["score"]), str(value["evidence"])))
        else:
            values.append((int(value[0]), str(value[1])))
    return VisualRubric(*values)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--character-atlas", type=Path, required=True)
    parser.add_argument("--appearance", type=Path, required=True)
    parser.add_argument("--icon", type=Path, required=True)
    parser.add_argument("--anchors", type=Path, required=True)
    parser.add_argument("--rig-profile", type=Path, required=True)
    parser.add_argument("--slot", required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--suggest-transform", action="store_true")
    parser.add_argument("--visual-rubric", type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    inputs = HarmonyInputs(
        character_atlas=arguments.character_atlas,
        appearance=arguments.appearance,
        icon=arguments.icon,
        anchors=arguments.anchors,
        rig_profile=arguments.rig_profile,
        slot=arguments.slot,
        out_dir=arguments.out_dir,
    )
    report = analyze_harmony(inputs)
    if arguments.visual_rubric:
        report = apply_visual_rubric(report, _rubric_from_json(arguments.visual_rubric))
    write_harmony_outputs(report, inputs)
    if arguments.suggest_transform:
        _write_json(inputs.out_dir / "transform-suggestion.json", {"reason_codes": list(report.reason_codes)})
    return 2 if report.verdict == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
