# GOGOBRO item appearance contract v2

Use `appearance-contract-v2.schema.json` for the machine-readable shape and `check_item_socket_harmony_v2.py` for the authoritative semantic gate. JSON Schema validation alone is not approval.

## Ownership and source binding

One contract binds exactly one `asset_id`, character, animation, immutable v2 character rig, authoritative asset registry, character atlas and appearance PNG by lowercase SHA-256. The registry remains authoritative for the exact `slot`, `socket`, `mode` and `depth` tuple. The item contract adds its scale, pivot, local correction, frame layout and pixel contract. It cannot replace or loosen registry, rig, trusted profile topology, or checker-owned character/animation binding values.

Do not add per-frame absolute offsets. The character rig owns every frame's socket position. The item's single `rendered_pivot_px` and `local_offset_px` are resolved against each of those positions.

The v2 appearance contract applies only to equipment-bearing walking animations. It never binds a hurt/hit/death animation. Hurt applies a white replacement effect to the already combined base-plus-appearance composite, while death hides the appearance layer and plays unadorned character art. Do not create a contract, overlay atlas, socket fallback, or matrix entry for either state.

## Canonical shape

```json
{
  "schema_version": "gogobro-item-appearance-contract-v2",
  "asset_id": "smoke_shell_helmet",
  "character_id": "character.niko:character/niko",
  "animation_id": "walk_down",
  "appearance": {
    "slot": "head",
    "socket": "head_shell",
    "mode": "RIGID",
    "depth": 40,
    "render_scale": [0.625, 0.625],
    "rendered_pivot_px": [36, 48],
    "local_offset_px": [0, 0]
  },
  "pixel_contract": {
    "frame_size_px": [128, 128],
    "source_size_px": [128, 128],
    "frame_layout": {
      "columns": 1,
      "rows": 1,
      "frame_count": 1,
      "frame_order": "single"
    },
    "logical_pixel_scale": 2,
    "resampling": "nearest",
    "alpha": "binary",
    "transparent_rgb": "zero",
    "source_pivot_px": [58, 77]
  },
  "source_sha256": {
    "character_rig": "<64 lowercase hex characters>",
    "asset_registry": "<64 lowercase hex characters>",
    "character_atlas": "<64 lowercase hex characters>",
    "appearance": "<64 lowercase hex characters>"
  }
}
```

All arrays and JSON scalar types are exact. Boolean values and numeric strings never substitute for integers or numbers. Extra fields fail the contract so legacy offsets cannot silently return.

## Pivot rule

`source_pivot_px` is the authored functional contact point on the unscaled source canvas. `rendered_pivot_px` is calculated independently for each axis as `floor(source_pivot_px × render_scale + 0.5)`. A changed runtime pivot therefore cannot pass merely because the resulting sprite still fits inside the frame. Human review must confirm that the authored source pivot is the correct functional contact point: helmet aperture, belt loop, charm loop, wrist contact, and so on.

For `FRAME_OVERLAY`, both pivots are `[0,0]`; the complete frame canvas aligns by `local_offset_px`.

Both `source_pivot_px` and `rendered_pivot_px` must lie inside their respective source-frame and rendered-frame bounds. Matching the scale equation does not excuse an out-of-bounds pivot.

## Mode layouts

- `RIGID`: one source frame, one column, one row, `frame_order: single`. Its source frame size equals the selected walking rig frame size. The same rendered item is resolved against every selected walking-animation frame socket.
- `FRAME_OVERLAY`: one horizontal source atlas, `columns` and `frame_count` equal the selected trusted walking animation's independent frame count, one row, `frame_order: animation_sequence`, and `render_scale: [1,1]`. Frame `n` is composited only with walking frame `n`; no independent playback, frame reuse, padding, hurt/death substitution, or fallback is allowed.

Both modes require exact nearest-grid pixels, binary alpha, zero RGB in fully transparent pixels, non-empty frames and uncropped placed opaque bounds.

Each render-scale axis must be finite, greater than zero and no greater than 8. This bound prevents malformed contracts from allocating unbounded diagnostic rasters; production item scales should normally stay at or below 1.

## Runtime parity formulas

For `RIGID`, every frame resolves:

```text
top_left_px = frame.socket[socket] - rendered_pivot_px + local_offset_px
godot_local_position = top_left_px - frame_size_px / 2
```

For `FRAME_OVERLAY`, every frame resolves:

```text
top_left_px = local_offset_px
godot_local_position = top_left_px - frame_size_px / 2
overlay_texture = appearance_atlas[base_frame_index]
```

The report records the socket, top-left, Godot-local position, rendered size, attached pivot, opaque bounds and overlay source-frame index for every base frame.

The item checker directly runs the character socket checker with the same authoritative registry and records a rig-gate summary. It also compares the selected walking animation's exact FPS, atlas grid, frame count, frame size and atlas SHA-256 with the rig's immutable source profile. The character gate resolves that tracked repository-relative profile and compares its per-frame attachment regions, face ROI and protected regions with the rig; absolute paths, `..` redirects and geometry drift fail.

Authority comes from the fixed-path, checker-owned character/animation catalog, not hashes supplied by the item contract. Callers cannot pass a replacement catalog, substitute the fixed sibling trust loader through `sys.modules`, or self-sign authority through synchronized input edits. Each animation binding independently pins the rig, source profile, atlas, grid, dimensions and frame count; the complete binding-ID set for a trusted rig must exactly equal its `animations` keys. Its character binding pins an explicit profile kind and the registry schema, declared visible-item count and semantic appearance-mapping digest. Synchronizing a changed contract with changed caller-supplied registry, rig, atlas or source profile files therefore still fails. A deliberately approved character, animation or item-mapping change must update the Skill binding and its bypass tests in the same reviewed change. Unregistered character/animation pairs, extra rig animations, and missing or unknown profile kinds fail closed.

## Single-contract boundary and release coverage

This checker validates exactly one worn-appearance tuple: `(character_id, asset_id, walking_animation_id)`. It does not validate the item's inventory icon; run the frozen v1 pixel/style gate or the approved icon QA pipeline separately. It also does not prove that the item has a valid appearance on every playable character or trusted walking animation. Hurt and death are runtime state effects outside this tuple space.

Before release, run the manifest-level character × visible item × animation gate described in [trusted-bindings-and-appearance-matrix.md](trusted-bindings-and-appearance-matrix.md). Every expected tuple requires its own character-specific contract plus relative rig, atlas, appearance, visual-rubric, and archived-report paths. The matrix gate reruns this checker in a fresh QA directory and requires the new `harmony_pass` report to equal the archived report exactly as JSON data. Missing or non-reproducible entries hard-fail. Generic appearances, inherited contracts, substituted animation frames, handwritten verdicts, and "no matching appearance" fallbacks are not valid coverage.

## Verdicts

Hard failures include any source hash mismatch, duplicate or missing registry asset, registry tuple mismatch, rig character/socket/slot/mode/depth mismatch, incomplete rig-frame coverage, wrong source layout, pivot-scale mismatch, pixel-contract violation, non-integral render size or cropped opaque pixels.

The output directory must be fresh: none of the three fixed outputs may already exist. It must not resolve to a source path, and its fixed outputs must not equal any rig, registry, source profile, contract, atlas, appearance or rubric input. A collision returns `hard_fail` without writing output, preventing stale images, symlinks, hard links or diagnostic files from overwriting or impersonating evidence.

After all hard gates pass, no rubric yields `review`. A strict five-dimension rubric uses the existing `identity`, `function`, `material`, `hierarchy` and `originality` keys. Total score at least 8/10 with no zero yields `harmony_pass`; otherwise the result stays `review`. Human approval remains separate.
