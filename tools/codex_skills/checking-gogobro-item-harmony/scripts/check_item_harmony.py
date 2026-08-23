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


def _input_paths(inputs: HarmonyInputs) -> dict[str, Path]:
    return {
        "character_atlas": inputs.character_atlas,
        "appearance": inputs.appearance,
        "icon": inputs.icon,
        "anchors": inputs.anchors,
        "rig_profile": inputs.rig_profile,
    }


def _hash_paths(paths: dict[str, Path]) -> dict[str, str]:
    return {name: _sha256(path) for name, path in paths.items()}


def _safe_hash_paths(paths: dict[str, Path]) -> dict[str, str]:
    try:
        return _hash_paths(paths)
    except OSError:
        return {}


def _with_hard_reason(report: HarmonyReport, reason: str) -> HarmonyReport:
    return HarmonyReport(
        "hard_fail",
        tuple(sorted({*report.reason_codes, reason})),
        dict(report.metrics),
        report.input_sha256,
    )


def check_source_integrity(
    report: HarmonyReport,
    inputs: HarmonyInputs,
    expected_hashes: dict[str, str],
    extra_sources: dict[str, Path] | None = None,
) -> HarmonyReport:
    """Return a hard-fail report when any source differs from its initial hash."""
    paths = _input_paths(inputs)
    if extra_sources:
        paths.update(extra_sources)
    try:
        current_hashes = _hash_paths(paths)
    except OSError:
        return _with_hard_reason(report, "source_changed")
    return report if current_hashes == expected_hashes else _with_hard_reason(report, "source_changed")


def _output_paths(inputs: HarmonyInputs, include_suggestion: bool) -> tuple[Path, ...]:
    paths = [
        inputs.out_dir / "harmony-report.json",
        inputs.out_dir / "harmony-overlay.png",
        inputs.out_dir / "harmony-actual-size.png",
    ]
    if include_suggestion:
        paths.append(inputs.out_dir / "transform-suggestion.json")
    return tuple(paths)


def _has_output_collision(
    inputs: HarmonyInputs,
    include_suggestion: bool,
    extra_sources: dict[str, Path] | None = None,
) -> bool:
    sources = list(_input_paths(inputs).values())
    if extra_sources:
        sources.extend(extra_sources.values())
    source_paths = {path.resolve() for path in sources}
    return any(path.resolve() in source_paths for path in _output_paths(inputs, include_suggestion))


def _read_json(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("malformed_input")
    return payload


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
    pair = (float(value[0]), float(value[1]))
    if not all(math.isfinite(component) for component in pair):
        raise ValueError("expected finite coordinate pair")
    return pair


def _as_box(value: object) -> Box:
    if not isinstance(value, list | tuple) or len(value) != 4:
        raise ValueError("invalid_contract")
    try:
        coordinates = tuple(int(component) for component in value)
    except (TypeError, ValueError):
        raise ValueError("invalid_contract") from None
    if tuple(value) != coordinates:
        raise ValueError("invalid_contract")
    box = Box(*coordinates)
    if box.right <= box.left or box.bottom <= box.top:
        raise ValueError("invalid_contract")
    return box


def _resolve_frame_path(frame: dict[str, object], path: str) -> object:
    value: object = frame
    for component in path.split("."):
        if not component or not isinstance(value, dict) or component not in value:
            raise ValueError("invalid_contract")
        value = value[component]
    return value


def _box_center(box: Box) -> tuple[float, float]:
    return (
        box.left + (box.right - box.left - 1) / 2,
        box.top + (box.bottom - box.top - 1) / 2,
    )


def _contract_limit(
    contract: dict[str, object], canonical_name: str, legacy_name: str
) -> float:
    if canonical_name in contract and legacy_name in contract:
        canonical = float(contract[canonical_name])
        legacy = float(contract[legacy_name])
        if canonical != legacy:
            raise ValueError("invalid_contract")
        return canonical
    return float(contract.get(canonical_name, contract[legacy_name]))


def _validate_contract(
    contract: dict[str, object],
    frames: list[dict[str, object]],
    *,
    require_slot_fields: bool,
) -> None:
    allowed_flip_behaviors = {
        "none",
        "mirror_between_wrists",
        "mirror_from_side_left",
        "mirror_from_trinket_left",
        "mirror_to_side_right",
        "mirror_to_trinket_right",
    }
    try:
        ratio = contract["outer_width_ratio"]
        if not isinstance(ratio, list | tuple) or len(ratio) != 2:
            raise ValueError
        low, high = (float(value) for value in ratio)
        palette_limit = contract["max_palette_colors"]
        feature_limit = _contract_limit(
            contract, "max_feature_center_error_px", "feature_center_max_px"
        )
        jitter_limit = _contract_limit(
            contract, "max_residual_jitter_px", "residual_jitter_max_px"
        )
        feature_anchor = str(contract.get("feature_anchor", "face_center"))
        protected_region = str(contract.get("protected_region", "protected_regions.eyes"))
        max_occlusion = float(contract.get("max_occlusion_ratio", 0))
        flip_behavior = str(contract.get("flip_behavior", "none"))
        depth_band_value = contract.get("depth_band", [-math.inf, math.inf])
        if not isinstance(depth_band_value, list | tuple) or len(depth_band_value) != 2:
            raise ValueError
        depth_low, depth_high = (float(value) for value in depth_band_value)
        expected_depth_value = contract.get("expected_depth")
        expected_depth = (
            None if expected_depth_value is None else float(expected_depth_value)
        )
    except (KeyError, TypeError, ValueError):
        raise ValueError("invalid_contract") from None
    required_slot_fields = {
        "feature_anchor",
        "protected_region",
        "max_occlusion_ratio",
        "depth_band",
        "flip_behavior",
    }
    if (
        not all(math.isfinite(value) for value in (low, high, feature_limit, jitter_limit))
        or low < 0
        or high < low
        or feature_limit < 0
        or jitter_limit < 0
        or not isinstance(palette_limit, int)
        or palette_limit < 1
        or not feature_anchor
        or not protected_region
        or not math.isfinite(max_occlusion)
        or not 0 <= max_occlusion <= 1
        or depth_low > depth_high
        or flip_behavior not in allowed_flip_behaviors
        or (expected_depth is not None and not math.isfinite(expected_depth))
        or (require_slot_fields and not required_slot_fields <= set(contract))
    ):
        raise ValueError("invalid_contract")
    for frame in frames:
        feature = _resolve_frame_path(frame, feature_anchor)
        if isinstance(feature, list | tuple) and len(feature) == 2:
            _as_pair(feature)
            try:
                reference_width = float(frame["head_width"])
            except (KeyError, TypeError, ValueError):
                raise ValueError("invalid_contract") from None
            if not math.isfinite(reference_width) or reference_width <= 0:
                raise ValueError("invalid_contract")
        else:
            _as_box(feature)
        _as_box(_resolve_frame_path(frame, protected_region))
    if feature_anchor.startswith("attachment_regions.wrist_"):
        selected_side = contract.get("selected_side")
        if selected_side not in {"left", "right"}:
            raise ValueError("invalid_contract")
        if feature_anchor != f"attachment_regions.wrist_{selected_side}":
            raise ValueError("invalid_contract")


def _placed_box(bounds: Box, scale: float, offset: tuple[int, int]) -> Box:
    return Box(
        math.floor(offset[0] + bounds.left * scale),
        math.floor(offset[1] + bounds.top * scale),
        math.ceil(offset[0] + bounds.right * scale),
        math.ceil(offset[1] + bounds.bottom * scale),
    )


def _occlusion_ratio(
    appearance: Image.Image,
    protected: Box,
    scale: float,
    offset: tuple[int, int],
) -> float:
    alpha = appearance.convert("RGBA").getchannel("A")
    opaque_pixels = 0
    for y in range(protected.top, protected.bottom):
        for x in range(protected.left, protected.right):
            source_x = math.floor((x - offset[0]) / scale)
            source_y = math.floor((y - offset[1]) / scale)
            if 0 <= source_x < appearance.width and 0 <= source_y < appearance.height:
                if alpha.getpixel((source_x, source_y)) != 0:
                    opaque_pixels += 1
    area = (protected.right - protected.left) * (protected.bottom - protected.top)
    return opaque_pixels / area


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


def _analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport:
    paths = _input_paths(inputs)
    input_sha256 = _hash_paths(paths)
    reasons: set[str] = set()
    anchors = _read_json(inputs.anchors)
    profile = _read_json(inputs.rig_profile)
    frames = _profile_frames(profile)
    contract = _slot_profile(profile, inputs.slot)
    if contract:
        _validate_contract(
            contract,
            frames,
            require_slot_fields=profile.get("schema_version") == "gogobro-rig-profile-v1",
        )
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
    feature_anchor = str(contract.get("feature_anchor", "face_center"))
    protected_region = str(contract.get("protected_region", "protected_regions.eyes"))
    max_occlusion = float(contract.get("max_occlusion_ratio", 0))
    flip_behavior = str(contract.get("flip_behavior", "none"))
    depth_band = contract.get("depth_band", [-math.inf, math.inf])
    depth_low, depth_high = (float(value) for value in depth_band)
    aperture = None
    if feature_anchor == "face_center":
        try:
            aperture = find_largest_enclosed_transparent_region(appearance)
        except ValueError:
            reasons.add("missing_feature_aperture")

    anchor_frames = anchors.get("frames", [])
    if not isinstance(anchor_frames, list):
        anchor_frames = []
    _add(reasons, len(anchor_frames) != len(frames), "anchor_count")
    occupied = anchors.get("occupied_slots", [])
    _add(reasons, isinstance(occupied, list) and inputs.slot in occupied, "duplicate_slot")
    _add(
        reasons,
        anchors.get("flip_behavior", "none") != flip_behavior,
        "flip_mismatch",
    )

    ratio_bounds = bounds if bounds is not None else Box(0, 0, 0, 0)
    outer_width_ratios: list[float] = []
    feature_errors: list[float] = []
    residuals: list[tuple[float, float]] = []
    protected_occlusion_ratios: list[float] = []
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
        except (KeyError, TypeError, ValueError):
            reasons.add("invalid_frame_data")
            continue
        if not math.isfinite(scale) or scale <= 0:
            reasons.add("invalid_scale")
            continue
        if expected_depth is not None:
            _add(reasons, anchor.get("depth") != expected_depth, "depth_mismatch")
        try:
            anchor_depth = float(anchor["depth"])
        except (KeyError, TypeError, ValueError):
            reasons.add("invalid_frame_data")
            continue
        _add(
            reasons,
            not depth_low <= anchor_depth <= depth_high,
            "depth_band_mismatch",
        )
        placed = _placed_box(ratio_bounds, scale, offset)
        frame_boxes.append([placed.left, placed.top, placed.right, placed.bottom])
        target_feature = _resolve_frame_path(frame, feature_anchor)
        if isinstance(target_feature, list | tuple) and len(target_feature) == 2:
            target_center = _as_pair(target_feature)
            reference_width = float(frame["head_width"])
        else:
            target_box = _as_box(target_feature)
            target_center = _box_center(target_box)
            reference_width = target_box.right - target_box.left
        outer_width_ratios.append((placed.right - placed.left) / reference_width)
        _add(
            reasons,
            placed.left < 0 or placed.top < 0 or placed.right > appearance.width or placed.bottom > appearance.height,
            "crop",
        )
        protected_box = _as_box(_resolve_frame_path(frame, protected_region))
        occlusion_ratio = _occlusion_ratio(appearance, protected_box, scale, offset)
        protected_occlusion_ratios.append(occlusion_ratio)
        _add(
            reasons,
            occlusion_ratio > max_occlusion,
            "protected_region_occlusion",
        )
        if feature_anchor == "face_center" and aperture is not None:
            source_feature = (
                aperture.left + (aperture.right - aperture.left - 1) / 2,
                aperture.top + (aperture.bottom - aperture.top - 1) / 2,
            )
        elif bounds is not None:
            source_feature = _box_center(bounds)
        else:
            source_feature = None
        if source_feature is not None:
            placed_feature = placed_feature_center(source_feature, scale, offset)
            delta = (
                placed_feature[0] - target_center[0],
                placed_feature[1] - target_center[1],
            )
            feature_errors.append(max(abs(delta[0]), abs(delta[1])))
            residuals.append(delta)

    outer_ratio = max(outer_width_ratios, default=0)
    allowed_ratio = contract.get("outer_width_ratio", [0, float("inf")])
    low_ratio, high_ratio = (float(allowed_ratio[0]), float(allowed_ratio[1]))
    _add(reasons, any(ratio < low_ratio for ratio in outer_width_ratios), "scale_ratio_low")
    _add(reasons, any(ratio > high_ratio for ratio in outer_width_ratios), "scale_ratio_high")
    max_feature_error = max(feature_errors, default=0)
    feature_limit = _contract_limit(
        contract, "max_feature_center_error_px", "feature_center_max_px"
    )
    _add(reasons, max_feature_error > feature_limit, "feature_center_offset")
    first_residual = residuals[0] if residuals else (0.0, 0.0)
    max_jitter = max(
        (max(abs(value[0] - first_residual[0]), abs(value[1] - first_residual[1])) for value in residuals),
        default=0,
    )
    jitter_limit = _contract_limit(
        contract, "max_residual_jitter_px", "residual_jitter_max_px"
    )
    _add(reasons, max_jitter > jitter_limit, "residual_jitter")

    after_sha256 = {name: _sha256(path) for name, path in paths.items()}
    _add(reasons, input_sha256 != after_sha256, "source_changed")
    metrics: dict[str, object] = {
        "outer_width_ratio": outer_ratio,
        "outer_width_ratios": outer_width_ratios,
        "max_feature_center_error_px": max_feature_error,
        "max_residual_jitter_px": max_jitter,
        "max_protected_occlusion_ratio": max(
            protected_occlusion_ratios, default=0
        ),
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


def analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport:
    """Analyze untrusted files without allowing malformed input to escape the checker."""
    try:
        return _analyze_harmony(inputs)
    except Exception as error:  # All dependencies below consume user-supplied files.
        reason = "invalid_contract" if str(error) == "invalid_contract" else "malformed_input"
        return HarmonyReport(
            "hard_fail",
            (reason,),
            {"error": type(error).__name__},
            _safe_hash_paths(_input_paths(inputs)),
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
    path.write_bytes(
        (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    )


def write_harmony_outputs(report: HarmonyReport, inputs: HarmonyInputs) -> None:
    if _has_output_collision(inputs, include_suggestion=False):
        raise ValueError("output_path_collision")
    inputs.out_dir.mkdir(parents=True, exist_ok=True)
    _write_json(inputs.out_dir / "harmony-report.json", asdict(report))
    try:
        with Image.open(inputs.character_atlas) as opened_atlas:
            atlas = opened_atlas.convert("RGBA")
    except Exception:
        atlas = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
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
    extra_sources = (
        {"visual_rubric": arguments.visual_rubric} if arguments.visual_rubric else {}
    )
    initial_hashes = _safe_hash_paths({**_input_paths(inputs), **extra_sources})
    if _has_output_collision(inputs, arguments.suggest_transform, extra_sources):
        return 2
    report = analyze_harmony(inputs)
    if arguments.visual_rubric:
        try:
            report = apply_visual_rubric(report, _rubric_from_json(arguments.visual_rubric))
        except Exception:
            report = _with_hard_reason(report, "malformed_visual_rubric")
    write_harmony_outputs(report, inputs)
    if arguments.suggest_transform:
        _write_json(inputs.out_dir / "transform-suggestion.json", {"reason_codes": list(report.reason_codes)})
    report_after_outputs = check_source_integrity(report, inputs, initial_hashes, extra_sources)
    if report_after_outputs != report:
        write_harmony_outputs(report_after_outputs, inputs)
        report = check_source_integrity(report_after_outputs, inputs, initial_hashes, extra_sources)
    return 2 if report.verdict == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
