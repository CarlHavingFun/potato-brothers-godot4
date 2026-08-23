"""Deterministic hard-gate checks for GOGOBRO item appearance layers."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import deque
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

from PIL import Image, ImageDraw


RUBRIC_DIMENSIONS = (
    "identity",
    "function",
    "material",
    "hierarchy",
    "originality",
)


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
    input_sha256: dict[str, str | None]
    atlas_sha256: dict[str, str | None] = field(default_factory=dict)
    slot: str | None = None
    thresholds: dict[str, object] = field(default_factory=dict)
    source_integrity: dict[str, object] = field(default_factory=dict)


@dataclass(frozen=True)
class VisualRubric:
    identity: tuple[int, str]
    function: tuple[int, str]
    material: tuple[int, str]
    hierarchy: tuple[int, str]
    originality: tuple[int, str]


@dataclass(frozen=True)
class _RasterPlacement:
    layer: Image.Image
    bounds: Box | None
    feature_center: tuple[float, float] | None


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


def _safe_hash_paths(paths: dict[str, Path]) -> dict[str, str | None]:
    hashes: dict[str, str | None] = {}
    for name, path in paths.items():
        try:
            hashes[name] = _sha256(path)
        except OSError:
            hashes[name] = None
    return hashes


def _source_integrity(
    before: dict[str, str | None],
    after: dict[str, str | None],
) -> dict[str, object]:
    keys = sorted(set(before) | set(after))
    return {
        "after": {key: after.get(key) for key in keys},
        "before": {key: before.get(key) for key in keys},
        "changed_keys": [key for key in keys if before.get(key) != after.get(key)],
    }


def _with_hard_reason(report: HarmonyReport, reason: str) -> HarmonyReport:
    return replace(
        report,
        verdict="hard_fail",
        reason_codes=tuple(sorted({*report.reason_codes, reason})),
    )


def check_source_integrity(
    report: HarmonyReport,
    inputs: HarmonyInputs,
    expected_hashes: dict[str, str | None],
    extra_sources: dict[str, Path] | None = None,
) -> HarmonyReport:
    """Return a hard-fail report when any source differs from its initial hash."""
    paths = _input_paths(inputs)
    if extra_sources:
        paths.update(extra_sources)
    current_hashes = _safe_hash_paths(paths)
    updated = replace(
        report,
        input_sha256=dict(expected_hashes),
        source_integrity=_source_integrity(expected_hashes, current_hashes),
    )
    return (
        updated
        if current_hashes == expected_hashes
        else _with_hard_reason(updated, "source_changed")
    )


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
        direct_icon_reuse = contract.get("direct_icon_reuse", True)
        min_outline_coverage = contract.get("min_outline_boundary_coverage")
        max_opaque_components = contract.get("max_opaque_components")
    except (KeyError, TypeError, ValueError):
        raise ValueError("invalid_contract") from None
    required_slot_fields = {
        "direct_icon_reuse",
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
        or type(direct_icon_reuse) is not bool
        or (
            require_slot_fields
            and (
                isinstance(min_outline_coverage, bool)
                or not isinstance(min_outline_coverage, int | float)
                or float(min_outline_coverage) != 1.0
            )
        )
        or (
            max_opaque_components is not None
            and (
                type(max_opaque_components) is not int
                or max_opaque_components < 1
            )
        )
        or (
            require_slot_fields
            and feature_anchor == "face_center"
            and max_opaque_components is None
        )
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


def _translate_box(bounds: Box, offset: tuple[int, int]) -> Box:
    return Box(
        offset[0] + bounds.left,
        offset[1] + bounds.top,
        offset[0] + bounds.right,
        offset[1] + bounds.bottom,
    )


def _raster_placement(
    appearance: Image.Image,
    scale: float,
    offset: tuple[int, int],
    feature_anchor: str,
) -> _RasterPlacement:
    size = (
        max(1, round(appearance.width * scale)),
        max(1, round(appearance.height * scale)),
    )
    layer = appearance.resize(size, Image.Resampling.NEAREST)
    local_bounds = _alpha_bounds(layer)
    bounds = None if local_bounds is None else _translate_box(local_bounds, offset)
    feature_center: tuple[float, float] | None = None
    if feature_anchor == "face_center":
        try:
            feature_center = placed_feature_center(
                _box_center(find_largest_enclosed_transparent_region(layer)),
                1,
                offset,
            )
        except ValueError:
            pass
    elif local_bounds is not None:
        feature_center = placed_feature_center(_box_center(local_bounds), 1, offset)
    return _RasterPlacement(layer, bounds, feature_center)


def _occlusion_ratio(
    layer: Image.Image,
    protected: Box,
    offset: tuple[int, int],
) -> float:
    alpha = layer.convert("RGBA").getchannel("A")
    opaque_pixels = 0
    for y in range(protected.top, protected.bottom):
        for x in range(protected.left, protected.right):
            source_x = x - offset[0]
            source_y = y - offset[1]
            if 0 <= source_x < layer.width and 0 <= source_y < layer.height:
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


def _formal_pixel_contract(anchors: dict[str, object]) -> dict[str, object] | None:
    if anchors.get("schema_version") != "gogobro-item-anchors-v1":
        return None
    contract = anchors.get("pixel_contract")
    required = {
        "appearance_grid_scale",
        "icon_grid_scale",
        "logical_canvas",
        "outline_colors_rgb",
        "resampling",
    }
    if type(contract) is not dict or set(contract) != required:
        raise ValueError("invalid_contract")
    logical_canvas = contract["logical_canvas"]
    appearance_scale = contract["appearance_grid_scale"]
    icon_scale = contract["icon_grid_scale"]
    colors = contract["outline_colors_rgb"]
    if (
        type(logical_canvas) is not list
        or logical_canvas != [64, 64]
        or type(appearance_scale) is not int
        or appearance_scale != 2
        or type(icon_scale) is not int
        or icon_scale != 4
        or contract["resampling"] != "nearest"
        or type(colors) is not list
        or not colors
    ):
        raise ValueError("invalid_contract")
    normalized_colors: list[tuple[int, int, int]] = []
    for color in colors:
        if (
            type(color) is not list
            or len(color) != 3
            or any(type(component) is not int or not 0 <= component <= 255 for component in color)
        ):
            raise ValueError("invalid_contract")
        normalized_colors.append(tuple(color))
    if normalized_colors != sorted(set(normalized_colors)):
        raise ValueError("invalid_contract")
    return {
        **contract,
        "outline_colors_rgb": normalized_colors,
    }


def _grid_round_trip_matches(
    image: Image.Image,
    logical_canvas: tuple[int, int],
    scale: int,
) -> bool:
    expected_size = (logical_canvas[0] * scale, logical_canvas[1] * scale)
    if image.size != expected_size:
        return False
    logical = image.resize(logical_canvas, Image.Resampling.NEAREST)
    restored = logical.resize(expected_size, Image.Resampling.NEAREST)
    return restored.tobytes() == image.convert("RGBA").tobytes()


def _opaque_component_count(image: Image.Image) -> int:
    alpha = image.convert("RGBA").getchannel("A")
    opaque = {
        (x, y)
        for y in range(image.height)
        for x in range(image.width)
        if alpha.getpixel((x, y)) != 0
    }
    components = 0
    while opaque:
        components += 1
        queue: deque[tuple[int, int]] = deque([opaque.pop()])
        while queue:
            x, y = queue.popleft()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in opaque:
                    opaque.remove(neighbor)
                    queue.append(neighbor)
    return components


def _outline_boundary_evidence(
    image: Image.Image,
    outline_colors: set[tuple[int, int, int]],
) -> tuple[int, int, float]:
    rgba = image.convert("RGBA")
    matched = 0
    total = 0
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha == 0:
                continue
            boundary = any(
                neighbor_x < 0
                or neighbor_y < 0
                or neighbor_x >= rgba.width
                or neighbor_y >= rgba.height
                or rgba.getpixel((neighbor_x, neighbor_y))[3] == 0
                for neighbor_x, neighbor_y in (
                    (x - 1, y),
                    (x + 1, y),
                    (x, y - 1),
                    (x, y + 1),
                )
            )
            if boundary:
                total += 1
                matched += (red, green, blue) in outline_colors
    return matched, total, matched / total if total else 0.0


def _analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport:
    paths = _input_paths(inputs)
    input_sha256 = _hash_paths(paths)
    reasons: set[str] = set()
    anchors = _read_json(inputs.anchors)
    pixel_contract = _formal_pixel_contract(anchors)
    profile = _read_json(inputs.rig_profile)
    frames = _profile_frames(profile)
    contract = _slot_profile(profile, inputs.slot)
    canonical_profile = profile.get("schema_version") == "gogobro-rig-profile-v1"
    expected_atlas_sha256: str | None = None
    if canonical_profile:
        expected_hash = profile.get("character_atlas_sha256")
        if (
            type(expected_hash) is not str
            or len(expected_hash) != 64
            or any(character.lower() not in "0123456789abcdef" for character in expected_hash)
        ):
            raise ValueError("invalid_contract")
        expected_atlas_sha256 = expected_hash.lower()
    if contract:
        _validate_contract(
            contract,
            frames,
            require_slot_fields=canonical_profile,
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
    _add(
        reasons,
        expected_atlas_sha256 is not None
        and input_sha256["character_atlas"].lower() != expected_atlas_sha256,
        "character_atlas_hash_mismatch",
    )
    _add(reasons, not contract, "unknown_slot")
    _add(reasons, inputs.slot != anchors.get("slot"), "slot_mismatch")
    _add(reasons, appearance.size != (128, 128), "appearance_dimensions")
    _add(reasons, icon.size != (256, 256), "icon_dimensions")
    if icon.size == (256, 256) and contract.get("direct_icon_reuse", True) is True:
        _add(
            reasons,
            list(icon.get_flattened_data())
            != list(derive_nearest_2x_icon(appearance).get_flattened_data()),
            "icon_not_nearest_2x",
        )
    palette_limit = int(contract.get("max_palette_colors", 8))
    reasons.update(_pixel_reason_codes(appearance, palette_limit))
    reasons.update(_pixel_reason_codes(icon, palette_limit))

    outline_colors: set[tuple[int, int, int]] = set()
    source_opaque_components: int | None = None
    source_outline_matched: int | None = None
    source_outline_total: int | None = None
    source_outline_coverage: float | None = None
    max_opaque_components = contract.get("max_opaque_components")
    min_outline_coverage = float(
        contract.get("min_outline_boundary_coverage", 0)
    )
    if pixel_contract is not None:
        logical_canvas = tuple(pixel_contract["logical_canvas"])
        outline_colors = set(pixel_contract["outline_colors_rgb"])
        _add(
            reasons,
            not _grid_round_trip_matches(
                appearance,
                logical_canvas,
                int(pixel_contract["appearance_grid_scale"]),
            )
            or not _grid_round_trip_matches(
                icon,
                logical_canvas,
                int(pixel_contract["icon_grid_scale"]),
            ),
            "pixel_grid_incompatible",
        )
        source_opaque_components = _opaque_component_count(appearance)
        source_outline_matched, source_outline_total, source_outline_coverage = (
            _outline_boundary_evidence(appearance, outline_colors)
        )
        _add(
            reasons,
            isinstance(max_opaque_components, int)
            and source_opaque_components > max_opaque_components,
            "outline_component_count",
        )
        _add(
            reasons,
            source_outline_coverage < min_outline_coverage,
            "outline_discontinuity",
        )

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

    outer_width_ratios: list[float] = []
    feature_errors: list[float] = []
    residuals: list[tuple[float, float]] = []
    protected_occlusion_ratios: list[float] = []
    frame_boxes: list[list[int]] = []
    rendered_alpha_boxes: list[list[int]] = []
    rendered_opaque_components: list[int] = []
    rendered_outline_coverages: list[float] = []
    rendered_outline_pixels: list[dict[str, int]] = []
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
        placement = _raster_placement(appearance, scale, offset, feature_anchor)
        placed = placement.bounds or Box(0, 0, 0, 0)
        local_alpha_bounds = _alpha_bounds(placement.layer)
        if local_alpha_bounds is not None:
            rendered_alpha_boxes.append(
                [
                    local_alpha_bounds.left,
                    local_alpha_bounds.top,
                    local_alpha_bounds.right,
                    local_alpha_bounds.bottom,
                ]
            )
        if pixel_contract is not None:
            rendered_components = _opaque_component_count(placement.layer)
            rendered_matched, rendered_total, rendered_coverage = (
                _outline_boundary_evidence(placement.layer, outline_colors)
            )
            rendered_opaque_components.append(rendered_components)
            rendered_outline_coverages.append(rendered_coverage)
            rendered_outline_pixels.append(
                {"matched": rendered_matched, "total": rendered_total}
            )
            _add(
                reasons,
                isinstance(max_opaque_components, int)
                and rendered_components > max_opaque_components,
                "outline_component_count",
            )
            _add(
                reasons,
                rendered_coverage < min_outline_coverage,
                "outline_discontinuity",
            )
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
        occlusion_ratio = _occlusion_ratio(placement.layer, protected_box, offset)
        protected_occlusion_ratios.append(occlusion_ratio)
        _add(
            reasons,
            occlusion_ratio > max_occlusion,
            "protected_region_occlusion",
        )
        if feature_anchor == "face_center" and placement.feature_center is None:
            reasons.add("missing_feature_aperture")
        if placement.feature_center is not None:
            placed_feature = placement.feature_center
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

    after_sha256 = _safe_hash_paths(paths)
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
        "rendered_opaque_components": rendered_opaque_components,
        "rendered_alpha_box": (
            rendered_alpha_boxes[0]
            if rendered_alpha_boxes
            and all(box == rendered_alpha_boxes[0] for box in rendered_alpha_boxes)
            else None
        ),
        "rendered_alpha_boxes": rendered_alpha_boxes,
        "rendered_outline_boundary_coverages": rendered_outline_coverages,
        "rendered_outline_boundary_pixels": rendered_outline_pixels,
        "source_opaque_components": source_opaque_components,
        "source_outline_boundary_coverage": source_outline_coverage,
        "source_outline_boundary_pixels": (
            None
            if source_outline_matched is None or source_outline_total is None
            else {
                "matched": source_outline_matched,
                "total": source_outline_total,
            }
        ),
    }
    return HarmonyReport(
        verdict="hard_fail" if reasons else "review",
        reason_codes=tuple(sorted(reasons)),
        metrics=metrics,
        input_sha256=input_sha256,
        atlas_sha256={
            "actual": after_sha256["character_atlas"],
            "expected": expected_atlas_sha256,
        },
        slot=inputs.slot,
        thresholds={
            "max_feature_center_error_px": feature_limit,
            "max_opaque_components": max_opaque_components,
            "max_palette_colors": palette_limit,
            "max_protected_occlusion_ratio": max_occlusion,
            "max_residual_jitter_px": jitter_limit,
            "min_outline_boundary_coverage": contract.get(
                "min_outline_boundary_coverage"
            ),
            "outer_width_ratio": [low_ratio, high_ratio],
        },
        source_integrity=_source_integrity(input_sha256, after_sha256),
    )


def analyze_harmony(inputs: HarmonyInputs) -> HarmonyReport:
    """Analyze untrusted files without allowing malformed input to escape the checker."""
    try:
        return _analyze_harmony(inputs)
    except Exception as error:  # All dependencies below consume user-supplied files.
        reason = "invalid_contract" if str(error) == "invalid_contract" else "malformed_input"
        input_sha256 = _safe_hash_paths(_input_paths(inputs))
        return HarmonyReport(
            "hard_fail",
            (reason,),
            {"error": type(error).__name__},
            input_sha256,
            atlas_sha256={
                "actual": input_sha256.get("character_atlas"),
                "expected": None,
            },
            slot=inputs.slot,
            source_integrity=_source_integrity(input_sha256, input_sha256),
        )


def _with_input_sha256(
    report: HarmonyReport,
    name: str,
    digest: str | None,
) -> HarmonyReport:
    input_sha256 = dict(report.input_sha256)
    input_sha256[name] = digest
    before = report.source_integrity.get("before", report.input_sha256)
    after = report.source_integrity.get("after", report.input_sha256)
    if not isinstance(before, dict) or not isinstance(after, dict):
        before = report.input_sha256
        after = report.input_sha256
    before_hashes = {**before, name: digest}
    after_hashes = {**after, name: digest}
    return replace(
        report,
        input_sha256=input_sha256,
        source_integrity=_source_integrity(before_hashes, after_hashes),
    )


def apply_visual_rubric(
    report: HarmonyReport,
    rubric: VisualRubric,
    *,
    rubric_sha256: str | None = None,
) -> HarmonyReport:
    if rubric_sha256 is not None:
        report = _with_input_sha256(report, "visual_rubric", rubric_sha256)
    dimensions = (
        rubric.identity,
        rubric.function,
        rubric.material,
        rubric.hierarchy,
        rubric.originality,
    )
    complete = all(
        type(dimension) is tuple
        and len(dimension) == 2
        and type(dimension[0]) is int
        and 0 <= dimension[0] <= 2
        and type(dimension[1]) is str
        and bool(dimension[1].strip())
        for dimension in dimensions
    )
    if not complete:
        return _with_hard_reason(report, "malformed_visual_rubric")
    if report.verdict == "hard_fail":
        return report
    total = sum(score for score, _ in dimensions)
    verdict = "harmony_pass" if total >= 8 and all(score > 0 for score, _ in dimensions) else "review"
    reasons = set(report.reason_codes)
    if verdict == "review":
        reasons.add("visual_rubric_review")
    metrics = dict(report.metrics)
    metrics["visual_rubric_total"] = total
    return replace(
        report,
        verdict=verdict,
        reason_codes=tuple(sorted(reasons)),
        metrics=metrics,
    )


def _write_json(path: Path, payload: object) -> None:
    path.write_bytes(
        (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    )


def _diagnostic_composite(
    inputs: HarmonyInputs,
    atlas: Image.Image,
) -> tuple[Image.Image, list[dict[str, object]]]:
    """Composite the supplied appearance per frame before adding diagnostic marks."""
    with Image.open(inputs.appearance) as opened_appearance:
        appearance = opened_appearance.convert("RGBA")
    anchors = _read_json(inputs.anchors)
    profile = _read_json(inputs.rig_profile)
    frames = _profile_frames(profile)
    anchor_frames = anchors.get("frames")
    if not isinstance(anchor_frames, list) or len(anchor_frames) != len(frames):
        raise ValueError("invalid_frame_data")
    frame_size_value = profile.get("frame_size", [128, 128])
    if not isinstance(frame_size_value, list | tuple) or len(frame_size_value) != 2:
        raise ValueError("invalid_contract")
    frame_width, frame_height = (int(value) for value in frame_size_value)
    if (
        frame_width <= 0
        or frame_height <= 0
        or atlas.size != (frame_width * len(frames), frame_height)
    ):
        raise ValueError("invalid_contract")
    contract = _slot_profile(profile, inputs.slot)
    feature_anchor = str(contract.get("feature_anchor", "face_center"))
    protected_region = str(
        contract.get("protected_region", "protected_regions.eyes")
    )
    bounds = _alpha_bounds(appearance)
    if bounds is None:
        raise ValueError("empty_appearance")
    composite = Image.new("RGBA", atlas.size, (0, 0, 0, 0))
    diagnostics: list[dict[str, object]] = []
    for index, (frame, anchor) in enumerate(
        zip(frames, anchor_frames, strict=True)
    ):
        if not isinstance(frame, dict) or not isinstance(anchor, dict):
            raise ValueError("invalid_frame_data")
        scale = float(anchor["scale"])
        offset_values = _as_pair(anchor["offset"])
        offset = (int(offset_values[0]), int(offset_values[1]))
        depth = float(anchor["depth"])
        if (
            not math.isfinite(scale)
            or scale <= 0
            or offset != offset_values
            or not math.isfinite(depth)
        ):
            raise ValueError("invalid_frame_data")
        placement = _raster_placement(appearance, scale, offset, feature_anchor)
        if placement.bounds is None or placement.feature_center is None:
            raise ValueError("invalid_frame_data")
        frame_image = atlas.crop(
            (
                index * frame_width,
                0,
                (index + 1) * frame_width,
                frame_height,
            )
        )
        worn = Image.new("RGBA", (frame_width, frame_height), (0, 0, 0, 0))
        if depth < 0:
            worn.alpha_composite(placement.layer, dest=offset)
            worn.alpha_composite(frame_image)
        else:
            worn.alpha_composite(frame_image)
            worn.alpha_composite(placement.layer, dest=offset)
        composite.paste(worn, (index * frame_width, 0))

        target_feature = _resolve_frame_path(frame, feature_anchor)
        if isinstance(target_feature, list | tuple) and len(target_feature) == 2:
            target_center = _as_pair(target_feature)
        else:
            target_center = _box_center(_as_box(target_feature))
        placed_center = placement.feature_center
        diagnostics.append(
            {
                "bounds": placement.bounds,
                "error": (
                    placed_center[0] - target_center[0],
                    placed_center[1] - target_center[1],
                ),
                "frame_index": index,
                "placed_feature": placed_center,
                "protected": _as_box(
                    _resolve_frame_path(frame, protected_region)
                ),
                "target_feature": target_center,
            }
        )
    return composite, diagnostics


def _draw_cross(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    x_offset: int,
    color: tuple[int, int, int, int],
) -> None:
    x = x_offset + round(center[0])
    y = round(center[1])
    draw.line((x - 2, y, x + 2, y), fill=color, width=1)
    draw.line((x, y - 2, x, y + 2), fill=color, width=1)


def _draw_diagnostic_evidence(
    overlay: Image.Image,
    diagnostics: list[dict[str, object]],
    frame_width: int,
) -> None:
    draw = ImageDraw.Draw(overlay)
    for diagnostic in diagnostics:
        frame_index = int(diagnostic["frame_index"])
        x_offset = frame_index * frame_width
        bounds = diagnostic["bounds"]
        protected = diagnostic["protected"]
        target = diagnostic["target_feature"]
        placed = diagnostic["placed_feature"]
        if not isinstance(bounds, Box) or not isinstance(protected, Box):
            continue
        if not isinstance(target, tuple) or not isinstance(placed, tuple):
            continue
        draw.rectangle(
            (
                x_offset + bounds.left,
                bounds.top,
                x_offset + bounds.right - 1,
                bounds.bottom - 1,
            ),
            outline=(255, 0, 255, 255),
            width=1,
        )
        draw.rectangle(
            (
                x_offset + protected.left,
                protected.top,
                x_offset + protected.right - 1,
                protected.bottom - 1,
            ),
            outline=(0, 210, 255, 255),
            width=1,
        )
        target_x = x_offset + round(target[0])
        target_y = round(target[1])
        draw.rectangle(
            (target_x - 2, target_y - 2, target_x + 2, target_y + 2),
            outline=(0, 255, 96, 255),
            width=1,
        )
        _draw_cross(draw, placed, x_offset, (255, 220, 0, 255))
        draw.line(
            (
                x_offset + round(target[0]),
                round(target[1]),
                x_offset + round(placed[0]),
                round(placed[1]),
            ),
            fill=(255, 64, 64, 255),
            width=1,
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
    try:
        composite, diagnostics = _diagnostic_composite(inputs, atlas)
    except Exception:
        composite = atlas.copy()
        diagnostics = []
    overlay = composite.copy()
    if diagnostics:
        frame_width = atlas.width // len(diagnostics)
        _draw_diagnostic_evidence(overlay, diagnostics, frame_width)
    else:
        draw = ImageDraw.Draw(overlay)
        for index, box in enumerate(report.metrics.get("frame_boxes", [])):
            left, top, right, bottom = (int(value) for value in box)
            x_offset = index * 128
            draw.rectangle(
                (x_offset + left, top, x_offset + right - 1, bottom - 1),
                outline=(255, 0, 255, 255),
                width=1,
            )
    overlay.save(inputs.out_dir / "harmony-overlay.png")
    preview = Image.new("RGBA", (1920, 1080), (18, 22, 30, 255))
    preview.alpha_composite(
        composite,
        dest=((1920 - composite.width) // 2, (1080 - composite.height) // 2),
    )
    preview.save(inputs.out_dir / "harmony-actual-size.png")


def load_visual_rubric(path: Path) -> VisualRubric:
    payload = _read_json(path)
    if set(payload) != set(RUBRIC_DIMENSIONS):
        raise ValueError("malformed_visual_rubric")
    values: list[tuple[int, str]] = []
    for name in RUBRIC_DIMENSIONS:
        value = payload[name]
        if type(value) is not dict or set(value) != {"score", "evidence"}:
            raise ValueError("malformed_visual_rubric")
        score = value["score"]
        evidence = value["evidence"]
        if (
            type(score) is not int
            or not 0 <= score <= 2
            or type(evidence) is not str
            or not evidence.strip()
        ):
            raise ValueError("malformed_visual_rubric")
        values.append((score, evidence))
    return VisualRubric(*values)


def _transform_suggestion(
    report: HarmonyReport,
    inputs: HarmonyInputs,
) -> dict[str, object]:
    current_scales: list[float] = []
    integer_offsets: list[list[int]] = []
    try:
        anchors = _read_json(inputs.anchors)
        frames = anchors.get("frames")
        if not isinstance(frames, list):
            raise ValueError
        for frame in frames:
            if not isinstance(frame, dict):
                raise ValueError
            scale = float(frame["scale"])
            offset = frame["offset"]
            if (
                not math.isfinite(scale)
                or type(offset) is not list
                or len(offset) != 2
                or any(type(component) is not int for component in offset)
            ):
                raise ValueError
            current_scales.append(scale)
            integer_offsets.append(list(offset))
    except (KeyError, TypeError, ValueError):
        current_scales = []
        integer_offsets = []
    shared_scale = (
        current_scales[0]
        if current_scales and all(scale == current_scales[0] for scale in current_scales)
        else None
    )
    return {
        "current_scales": current_scales,
        "integer_offsets": integer_offsets,
        "objective_measurements": report.metrics,
        "reason_codes": list(report.reason_codes),
        "shared_scale": shared_scale,
        "slot": inputs.slot,
        "status": (
            "manual_correction_required"
            if report.verdict == "hard_fail"
            else "current_transform_passes"
        ),
        "thresholds": report.thresholds,
    }


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
            report = apply_visual_rubric(
                report,
                load_visual_rubric(arguments.visual_rubric),
                rubric_sha256=initial_hashes.get("visual_rubric"),
            )
        except Exception:
            report = _with_input_sha256(
                report,
                "visual_rubric",
                initial_hashes.get("visual_rubric"),
            )
            report = _with_hard_reason(report, "malformed_visual_rubric")
    report = check_source_integrity(report, inputs, initial_hashes, extra_sources)
    write_harmony_outputs(report, inputs)
    if arguments.suggest_transform:
        _write_json(
            inputs.out_dir / "transform-suggestion.json",
            _transform_suggestion(report, inputs),
        )
    report_after_outputs = check_source_integrity(report, inputs, initial_hashes, extra_sources)
    if report_after_outputs != report:
        write_harmony_outputs(report_after_outputs, inputs)
        report = check_source_integrity(report_after_outputs, inputs, initial_hashes, extra_sources)
        if arguments.suggest_transform:
            _write_json(
                inputs.out_dir / "transform-suggestion.json",
                _transform_suggestion(report, inputs),
            )
    return 2 if report.verdict == "hard_fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
