#!/usr/bin/env python3
"""Validate installed static redraw PNGs against the checked-in contract.

The mechanical result deliberately stays separate from actual-size visual approval.
Palette size is reported for review but is not a rejection criterion: crisp, readable
pixel art may retain moderate structural and surface detail.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import deque
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, UnidentifiedImageError


SCHEMA_VERSION = "gogobro-static-redraw-contract-v1"
REQUIRED_RECORD_FIELDS = {
    "asset_id",
    "visible_name_zh",
    "visible_name_en",
    "subject",
    "width",
    "height",
    "mode",
    "pivot_px",
    "anchor_px",
}
MINIMUM_MARGIN_PX = 2
MINIMUM_COMPONENT_RATIO = 0.82
MINIMUM_FIREARM_WIDTH_PX = 70
MINIMUM_KNIFE_EXTENT_PX = 42


class ContractError(ValueError):
    """Raised when the contract cannot enumerate deterministic result rows."""


def _is_int(value: Any) -> bool:
    return type(value) is int


def _validate_point(
    value: Any,
    *,
    label: str,
    width: int,
    height: int,
) -> tuple[list[int] | None, list[str]]:
    errors: list[str] = []
    if not isinstance(value, list) or len(value) != 2:
        return None, [f"{label} must be a two-integer array"]
    if not all(_is_int(coordinate) for coordinate in value):
        return None, [f"{label} must contain integers"]
    point = [value[0], value[1]]
    if not (0 <= point[0] < width and 0 <= point[1] < height):
        errors.append(f"{label} must be inside the declared canvas")
    return point, errors


def _validate_record(
    category: str,
    asset_id: str,
    record: Any,
) -> tuple[dict[str, Any] | None, list[str]]:
    if not isinstance(record, dict):
        return None, ["record must be an object"]

    errors: list[str] = []
    missing_fields = sorted(REQUIRED_RECORD_FIELDS - set(record))
    if missing_fields:
        errors.append(f"missing required fields: {', '.join(missing_fields)}")

    if record.get("asset_id") != asset_id:
        errors.append("asset_id must match its map key")
    for field in ("visible_name_zh", "visible_name_en", "subject"):
        value = record.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{field} must be a non-empty string")

    width = record.get("width")
    height = record.get("height")
    if not _is_int(width) or width <= 0:
        errors.append("width must be a positive integer")
    if not _is_int(height) or height <= 0:
        errors.append("height must be a positive integer")
    if not _is_int(width) or width <= 0 or not _is_int(height) or height <= 0:
        return None, errors

    mode = record.get("mode")
    if category == "weapons" and mode not in {"melee", "ranged"}:
        errors.append("weapon mode must be melee or ranged")
    if category == "items" and mode != "item":
        errors.append("item mode must be item")

    pivot, point_errors = _validate_point(
        record.get("pivot_px"),
        label="pivot_px",
        width=width,
        height=height,
    )
    errors.extend(point_errors)

    anchors = record.get("anchor_px")
    expected_anchor_names: set[str]
    if mode == "ranged":
        expected_anchor_names = {"muzzle"}
    elif mode == "melee":
        expected_anchor_names = {"contact"}
    else:
        expected_anchor_names = {"contact", "display"}

    anchor_name: str | None = None
    anchor: list[int] | None = None
    if not isinstance(anchors, dict) or len(anchors) != 1:
        errors.append("anchor_px must contain exactly one named anchor")
    else:
        anchor_name = next(iter(anchors))
        if anchor_name not in expected_anchor_names:
            expected = " or ".join(sorted(expected_anchor_names))
            errors.append(f"anchor_px must use {expected} for mode {mode}")
        anchor, point_errors = _validate_point(
            anchors[anchor_name],
            label=f"anchor_px.{anchor_name}",
            width=width,
            height=height,
        )
        errors.extend(point_errors)

    if category == "weapons" and pivot is not None and anchor is not None:
        if anchor[0] <= pivot[0]:
            errors.append("weapon anchor must be forward of its pivot")
        minimum_forward_x = width * (3 if mode == "ranged" else 2) // 4
        if mode == "melee":
            minimum_forward_x = width * 2 // 3
        if anchor[0] < minimum_forward_x:
            errors.append("weapon anchor must be in the forward acceptance region")

    normalized = dict(record)
    normalized["pivot_px"] = pivot
    normalized["anchor_name"] = anchor_name
    normalized["anchor"] = anchor
    return normalized, errors


def _opaque_bbox(
    pixels: list[tuple[int, int, int, int]],
    width: int,
) -> tuple[int, int, int, int] | None:
    opaque_indices = [index for index, pixel in enumerate(pixels) if pixel[3] > 0]
    if not opaque_indices:
        return None
    xs = [index % width for index in opaque_indices]
    ys = [index // width for index in opaque_indices]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def _largest_connected_component(
    pixels: list[tuple[int, int, int, int]],
    width: int,
) -> tuple[set[tuple[int, int]], int]:
    opaque = {
        (index % width, index // width)
        for index, pixel in enumerate(pixels)
        if pixel[3] > 0
    }
    if not opaque:
        return set(), 0

    remaining = set(opaque)
    largest: set[tuple[int, int]] = set()
    neighbours = (
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (1, 0),
        (-1, 1),
        (0, 1),
        (1, 1),
    )
    while remaining:
        start = remaining.pop()
        queue: deque[tuple[int, int]] = deque([start])
        current: set[tuple[int, int]] = {start}
        while queue:
            x, y = queue.popleft()
            for dx, dy in neighbours:
                candidate = (x + dx, y + dy)
                if candidate in remaining:
                    remaining.remove(candidate)
                    queue.append(candidate)
                    current.add(candidate)
        if len(current) > len(largest):
            largest = current
    return largest, len(opaque)


def _point_near_component(
    component: set[tuple[int, int]],
    point: list[int] | None,
    radius: int,
) -> bool:
    if point is None:
        return False
    return any(
        abs(x - point[0]) <= radius and abs(y - point[1]) <= radius
        for x, y in component
    )


def _point_inside_bbox(
    point: list[int] | None,
    bbox: tuple[int, int, int, int] | None,
) -> bool:
    if point is None or bbox is None:
        return False
    left, top, right, bottom = bbox
    return left <= point[0] < right and top <= point[1] < bottom


def _empty_checks() -> dict[str, bool]:
    return {
        "contract": False,
        "file_present": False,
        "png_readable": False,
        "size": False,
        "binary_alpha": False,
        "transparent_rgb_zero": False,
        "safe_margin": False,
        "connected_component": False,
        "anchor_contract": False,
        "silhouette_extent": False,
    }


def _validate_png(
    category: str,
    asset_id: str,
    record_value: Any,
    assets_root: Path,
) -> dict[str, Any]:
    checks = _empty_checks()
    errors: list[str] = []
    metrics: dict[str, Any] = {}
    record, contract_errors = _validate_record(category, asset_id, record_value)
    checks["contract"] = not contract_errors
    errors.extend(contract_errors)

    path = assets_root / category / f"{asset_id}.png"
    checks["file_present"] = path.is_file()
    if not checks["file_present"]:
        errors.append("installed PNG is missing")

    if record is not None and checks["file_present"]:
        try:
            with Image.open(path) as source:
                source.load()
                image_format = source.format
                rgba = source.convert("RGBA")
        except (OSError, UnidentifiedImageError) as error:
            errors.append(f"PNG could not be read: {error}")
        else:
            checks["png_readable"] = image_format == "PNG"
            if not checks["png_readable"]:
                errors.append("installed file must be PNG data")

            width, height = rgba.size
            pixels = list(rgba.getdata())
            metrics["size"] = [width, height]
            checks["size"] = (width, height) == (
                record["width"],
                record["height"],
            )
            if not checks["size"]:
                errors.append(
                    "size must be "
                    f"{record['width']}x{record['height']}, got {width}x{height}"
                )

            alpha_values = sorted({pixel[3] for pixel in pixels})
            metrics["alpha_values"] = alpha_values
            checks["binary_alpha"] = set(alpha_values) <= {0, 255}
            if not checks["binary_alpha"]:
                errors.append("alpha values must be a subset of [0, 255]")

            checks["transparent_rgb_zero"] = all(
                pixel[3] != 0 or pixel[:3] == (0, 0, 0) for pixel in pixels
            )
            if not checks["transparent_rgb_zero"]:
                errors.append("transparent pixels must have zero RGB")

            bbox = _opaque_bbox(pixels, width)
            metrics["opaque_bbox"] = list(bbox) if bbox is not None else None
            if bbox is None:
                margins = None
                occupied_width = 0
                occupied_height = 0
            else:
                left, top, right, bottom = bbox
                margins = {
                    "left": left,
                    "top": top,
                    "right": width - right,
                    "bottom": height - bottom,
                }
                occupied_width = right - left
                occupied_height = bottom - top
            metrics["margins_px"] = margins
            metrics["occupied_width"] = occupied_width
            metrics["occupied_height"] = occupied_height
            checks["safe_margin"] = (
                margins is not None
                and min(margins.values()) >= MINIMUM_MARGIN_PX
            )
            if not checks["safe_margin"]:
                errors.append(
                    "nontransparent subject needs at least "
                    f"{MINIMUM_MARGIN_PX}px margin"
                )

            opaque_colors = {
                pixel[:3] for pixel in pixels if pixel[3] == 255
            }
            metrics["unique_opaque_colors"] = len(opaque_colors)

            largest_component, opaque_count = _largest_connected_component(
                pixels,
                width,
            )
            if largest_component:
                component_xs = [point[0] for point in largest_component]
                component_ys = [point[1] for point in largest_component]
                largest_component_width = max(component_xs) - min(component_xs) + 1
                largest_component_height = max(component_ys) - min(component_ys) + 1
            else:
                largest_component_width = 0
                largest_component_height = 0
            metrics["largest_component_width"] = largest_component_width
            metrics["largest_component_height"] = largest_component_height
            component_ratio = (
                len(largest_component) / opaque_count if opaque_count else 0.0
            )
            metrics["largest_connected_component_ratio"] = round(
                component_ratio,
                6,
            )
            checks["connected_component"] = (
                component_ratio >= MINIMUM_COMPONENT_RATIO
            )
            if not checks["connected_component"]:
                errors.append(
                    "largest connected component ratio must be at least "
                    f"{MINIMUM_COMPONENT_RATIO:.2f}"
                )

            mode = record.get("mode")
            if category == "weapons" and mode == "ranged":
                checks["silhouette_extent"] = (
                    largest_component_width >= MINIMUM_FIREARM_WIDTH_PX
                )
                if not checks["silhouette_extent"]:
                    errors.append(
                        "firearm largest connected component width must be at least "
                        f"{MINIMUM_FIREARM_WIDTH_PX}px"
                    )
            elif category == "weapons" and mode == "melee":
                checks["silhouette_extent"] = (
                    max(largest_component_width, largest_component_height)
                    >= MINIMUM_KNIFE_EXTENT_PX
                )
                if not checks["silhouette_extent"]:
                    errors.append(
                        "knife largest connected component width or height "
                        "must be at least "
                        f"{MINIMUM_KNIFE_EXTENT_PX}px"
                    )
            else:
                checks["silhouette_extent"] = bbox is not None

            pivot = record.get("pivot_px")
            anchor = record.get("anchor")
            if category == "weapons":
                checks["anchor_contract"] = (
                    not contract_errors
                    and _point_near_component(largest_component, pivot, 6)
                    and _point_near_component(largest_component, anchor, 4)
                )
            else:
                checks["anchor_contract"] = (
                    not contract_errors
                    and _point_inside_bbox(pivot, bbox)
                    and _point_inside_bbox(anchor, bbox)
                )
            if not checks["anchor_contract"]:
                errors.append("pivot_px and anchor_px must align with the subject")

    row = {
        "asset_id": asset_id,
        "category": category,
        "path": str(path),
        "mechanical_pass": all(checks.values()),
        "visual_approval": "not_evaluated",
        "actual_size_readability": "requires_human_review",
        "checks": checks,
        "metrics": metrics,
        "errors": errors,
    }
    return row


def _load_contract(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"could not load contract {path}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("contract root must be an object")
    if value.get("schema_version") != SCHEMA_VERSION:
        raise ContractError(f"schema_version must be {SCHEMA_VERSION}")
    for category in ("weapons", "items"):
        if not isinstance(value.get(category), dict):
            raise ContractError(f"contract.{category} must be an object")
    return value


def _selected_categories(category: str | None) -> Iterable[str]:
    if category is None:
        return ("weapons", "items")
    return (category,)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate installed weapon/item redraw PNGs mechanically.",
    )
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--assets-root", type=Path, required=True)
    parser.add_argument("--category", choices=("weapons", "items"))
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        contract = _load_contract(args.contract)
    except ContractError as error:
        print(str(error), file=sys.stderr)
        return 2

    rows = [
        _validate_png(category, asset_id, record, args.assets_root)
        for category in _selected_categories(args.category)
        for asset_id, record in contract[category].items()
    ]

    for row in rows:
        print(json.dumps(row, ensure_ascii=False, sort_keys=True))

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    return 0 if rows and all(row["mechanical_pass"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
