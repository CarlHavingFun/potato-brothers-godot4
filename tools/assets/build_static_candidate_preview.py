#!/usr/bin/env python3
"""Install non-shipping candidate PNGs into a Godot-only development preview tree."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


REPO = Path(__file__).resolve().parents[2]
ROOT = REPO.parent
STATIC = ROOT / "GOGOBRO_ASSET_INBOX" / "02_static_assets"
COVERAGE = STATIC / "batches/wave-045-coverage-first-ui/qa/full-static-candidate-coverage.json"
OUTPUT = REPO / "game/assets/gogobro_static_preview"
MANIFEST = REPO / "game/content/assets/gogobro_static_candidate_preview_v1.json"

CATEGORY_DIR = {
    "weapon": "weapons",
    "item": "items",
    "upgrade": "upgrades",
    "world": "world",
    "ui_brand": "ui",
}
ROLE = {
    "weapon": "world_sprite",
    "item": "icon",
    "upgrade": "icon",
    "world": "world_sprite",
    "ui_brand": "ui_texture",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def alpha_anchors(image: Image.Image, category: str) -> tuple[list[int], dict[str, list[int]]]:
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        return [image.width // 2, image.height // 2], {}
    left, top, right, bottom = box
    if category != "weapon":
        return [image.width // 2, image.height // 2], {}

    # Coverage-first firearm convention: all candidates point right. The provisional
    # grip pivot sits one third into the silhouette; the muzzle is the median opaque
    # pixel at the rightmost occupied column. Human curation can replace these later.
    pivot_x = max(left, min(right - 1, left + (right - left) // 3))
    pivot_y = max(top, min(bottom - 1, top + (bottom - top) * 3 // 5))
    pixels = alpha.load()
    muzzle_x = right - 1
    muzzle_ys = [y for y in range(top, bottom) if pixels[muzzle_x, y] > 0]
    muzzle_y = muzzle_ys[len(muzzle_ys) // 2] if muzzle_ys else (top + bottom - 1) // 2
    return [pivot_x, pivot_y], {"muzzle": [muzzle_x, muzzle_y]}


def main() -> int:
    report = json.loads(COVERAGE.read_text(encoding="utf-8"))
    if not report.get("ok") or len(report.get("rows", [])) != 61:
        raise SystemExit("candidate coverage report is not complete")

    units: list[dict[str, object]] = []
    for row in report["rows"]:
        asset_id = row["asset_id"]
        category = row["category"]
        if asset_id == "service_carbine" or category not in CATEGORY_DIR:
            raise SystemExit(f"forbidden preview unit: {asset_id}")
        source = ROOT / row["coverage_png"]
        if not source.is_file():
            raise SystemExit(f"missing candidate: {source}")
        image = Image.open(source).convert("RGBA")
        if image.getchannel("A").getbbox() is None and category != "ui_brand":
            raise SystemExit(f"empty candidate: {asset_id}")
        destination = OUTPUT / CATEGORY_DIR[category] / f"{asset_id}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        pivot, anchors = alpha_anchors(image, category)
        resource_path = "res://" + destination.relative_to(REPO).as_posix()
        units.append({
            "asset_id": asset_id,
            "category": category,
            "role": ROLE[category],
            "resource_path": resource_path,
            "source_candidate_path": str(source.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha256(destination),
            "pixel_size": [image.width, image.height],
            "display_size_px": [image.width, image.height],
            "pivot_px": pivot,
            "anchors_px": anchors,
            "texture_filter": "nearest",
            "mipmaps": False,
            "approval_status": "candidate_preview_only",
            "preview_alias_asset_ids": ["service_pistol"] if asset_id == "wood_stock_assault_rifle" else [],
        })

    category_counts = {
        category: sum(unit["category"] == category for unit in units)
        for category in CATEGORY_DIR
    }
    manifest = {
        "schema_version": "gogobro-static-candidate-preview-v1",
        "kind": "development_candidate_preview_only",
        "enabled_in_shipping": False,
        "human_approval_implied": False,
        "character_assets_included": False,
        "expected_unit_count": 61,
        "category_counts": category_counts,
        "coverage_report_sha256": sha256(COVERAGE),
        "units": units,
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "ok": len(units) == 61,
        "unit_count": len(units),
        "category_counts": category_counts,
        "manifest": str(MANIFEST),
        "manifest_sha256": sha256(MANIFEST),
        "preview_root": str(OUTPUT),
    }, ensure_ascii=False, indent=2))
    return 0 if len(units) == 61 else 1


if __name__ == "__main__":
    raise SystemExit(main())
