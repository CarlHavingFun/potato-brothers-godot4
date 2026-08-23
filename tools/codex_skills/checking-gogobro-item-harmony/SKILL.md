---
name: checking-gogobro-item-harmony
description: Use when reviewing or integrating GOGOBRO item icons and character appearance layers for scale, anchor alignment, protected-region occlusion, pixel density, palette fit, depth, or multi-frame visual harmony.
---

# Checking Gogobro Item Harmony

Use the deterministic checker as the source of geometry and pixel-quality findings when it is available.

## Checker output contract

The checker returns one of `hard_fail`, `review`, or `harmony_pass`, with reason codes and measurements for every failed gate. A `hard_fail` blocks approval. This skill never advances registry approval automatically.
