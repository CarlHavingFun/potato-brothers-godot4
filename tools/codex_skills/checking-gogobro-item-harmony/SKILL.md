---
name: checking-gogobro-item-harmony
description: Use when reviewing or integrating GOGOBRO item icons and character appearance layers for scale, anchor alignment, protected-region occlusion, pixel density, palette fit, depth, or multi-frame visual harmony.
---

# Checking Gogobro Item Harmony

Review GOGOBRO item icons and character appearance layers with deterministic hard gates first, then a visual rubric. The checker is the sole source of geometry, alpha, pixel-grid, outline, depth, occlusion, icon-policy, provenance, and multi-frame findings.

## Required recipe

Return the verdict and evidence in this order:

1. Run `scripts/check_item_harmony.py` with the character atlas, appearance, icon, anchors, rig profile, slot, and a separate output directory. Add `--visual-rubric` only for a completed strict rubric; use `--suggest-transform` for non-mutating evidence.
2. If the checker returns `hard_fail`, report its reason codes and measurements, then stop before approval.
3. If geometry passes, inspect both `harmony-overlay.png` and `harmony-actual-size.png`.
4. Score character identity, item function, material/outline fit, value/color hierarchy, and originality from 0–2. Each JSON dimension is exactly `{score, evidence}` with an integer score (never bool) and non-empty evidence; no extra or missing keys.
5. Return `review` when the total is below 8/10 or any score is zero; otherwise return `harmony_pass`.
6. Never mutate source assets or anchors, accept a transform suggestion automatically, or advance registry approval.

## Slot selection

When choosing or reviewing a slot profile, read [slot-profiles.md](references/slot-profiles.md). Use the rig's exact named feature and protected regions; do not apply head geometry to another slot.

Formal v1 anchors bind a 64×64 logical canvas, exact 2× appearance and 4× icon grids, nearest resampling, and a frozen outline palette. Never derive or relax that palette during review. Canonical v1 rigs bind the character-atlas SHA-256. `direct_icon_reuse:true` requires exact nearest 2× reuse; `false` permits an independent icon that still passes its 4× grid.

## Output contract

The checker measures the exact nearest-resized raster used in its composite, not continuous projected geometry. `harmony-report.json` includes slot, measurements, thresholds, input hashes, atlas expected/actual, and source-integrity before/after/changed keys. A missing source is `null` without erasing other hashes. A failing suggestion remains `manual_correction_required` unless a measured passing transform exists.

The checker returns `hard_fail`, `review`, or `harmony_pass`. Include reason codes, measured values, visual-rubric evidence, and the final verdict. `hard_fail` blocks approval. `harmony_pass` confirms this gate only; explicit human approval is still required.
