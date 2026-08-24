# GOGOBRO character attachment rig v2

Use this reference when creating, changing, or integrating a character animation or its item sockets.

## Separation of responsibilities

- `conflict_slot`: inventory/display conflict, such as `head`, `wrist`, or `back`.
- `socket_id`: character-space installation topology, such as `head_shell`, `forehead`, or `chest_left`.
- `rendered_pivot_px`: the item pixel on the exact nearest-resized runtime raster that attaches to the socket.

The character owns animation/frame socket positions. The item owns its pivot, local correction, scale, mode and depth. Never store a hand-authored absolute item offset for every animation frame as the runtime source of truth.

## Canonical schema

`gogobro-character-attachment-rig-v2` binds one character rig validation unit to its immutable atlas hash. Coordinates use top-left-origin integer pixels in the authored frame. Region boxes are `[left, top, right, bottom]` with exclusive right/bottom edges. Package authority is selected per character and animation by the Skill-owned trusted binding; different animations may bind different rigs, atlases, grids, rows and frame counts.

Validation also requires the authoritative static-asset registry. A unit is visible/wearable only when `category` is `item` and the `appearance` key is present. An item without that key is non-visible and does not enter the trusted visible-item count, semantic mapping digest, rig requirements, or release matrix. When the key is present, its value must contain exactly `slot`, `socket`, `mode`, and integer `depth` with exact types; missing or extra fields hard-fail. The rig socket catalog may contain additional sockets for future content, but it must cover every socket required by visible item appearances. For every required socket, the catalog `slot_id`, `allowed_modes`, and `default_depth` must accept all registry declarations. The registry, not a duplicated Markdown table, is the machine source of truth.

Each socket catalog entry declares:

- `slot_id`
- `allowed_modes`: `RIGID` and/or `FRAME_OVERLAY`
- `default_depth`; back sockets must be negative
- `reference_region`
- `flip_h`; arbitrary runtime rotation is not allowed for this front-facing pixel rig
- `max_residual_jitter_px`

Each registered walking animation declares exact positive finite `fps`, `frame_count`, atlas `row`, and a sequential frame array. Every frame must have its exact `frame_index`, deterministic `frame_name`, non-empty reference regions, non-empty protected regions, and exactly every socket in the catalog. Every reference and protected box must stay completely inside the frame. A socket is a two-integer pixel position inside its reference region.

Equipment sockets exist only for walking. Hurt is rendered by applying a white flash to the already combined character-plus-appearance composite. Death hides the appearance layer and plays its unadorned animation. Neither state receives hit/hurt/death sockets, copied walking coordinates, fallback socket lookup, or item-overlay atlases.

Within one atlas/rig validation unit, packing remains rectangular: one registered animation per selected atlas row, exact frame-size divisibility, no duplicate row, no truncated final column, and no unregistered content presented as part of that unit. A row's registered frame count and columns must match its trusted animation binding exactly. Different animations are not globally required to share a frame count: bind them independently, using separate trusted atlas/rig units when their widths or grids differ. Never pad, truncate, or borrow frames merely to match another animation.

Trust is closed over each rig: the complete set of catalog animation IDs bound to that trusted rig must exactly equal the keys of `rig.animations`. Every ID is checked against its own trusted row, grid and frame count. An animation found only in the rig is unregistered and hard-fails; an animation found only in the catalog is missing and hard-fails. Do not validate a selected animation while ignoring extra animations in the same trusted rig.

The rig's relative `source_profile` is part of the character gate, not only the downstream item gate. Its path, schema and SHA-256 must equal the trusted binding; its atlas hash/size, frame size, grid, frame count and FPS must agree with the same animation. For every profile frame, `attachment_regions` must equal the rig regions it owns (`side_left` maps to `hip_left`, `side_right` maps to `hip_right`), `face_roi` must equal rig region `face`, and `protected_regions` must match exactly. Extra rig-derived geometry such as `head` is permitted only where the profile does not define the box.

Missing frames or sockets are invalid. Do not inherit, interpolate, clamp, or substitute another socket.

Socket names ending in `_left` and `_right` use authored-frame image space. `_left` is the side with smaller x coordinates in that rendered frame; `_right` is the side with larger x coordinates. They do not identify the character's anatomical left and right. Every character, animation, facing and frame must be marked from its own authored image. Do not automatically mirror, exchange, or carry these sockets from a preceding frame or another animation, even when silhouettes appear symmetric.

## Trusted topology profile

The trusted character binding names an explicit `profile_kind`. In addition to sockets required by current registry items, a `humanoid_v1` rig must declare `clothes_body`, plus `shoulder`, `upper_arm`, `forearm`, and `hand` sockets for both left and right sides. Every required topology socket must appear on every frame.

`clothes_body` belongs to slot `clothes`, permits only `FRAME_OVERLAY`, and has default depth 20. Left arm-segment sockets belong to `arm_left`; right arm-segment sockets belong to `arm_right`. Arm-segment sockets permit `RIGID` and `FRAME_OVERLAY` and have default depth 50. These depth bands keep the arms above the body garment.

All nine `humanoid_v1` clothes/arm topology sockets declare `require_opaque_contact: true`. On every frame, the corresponding socket pixel in the bound base-atlas row must have alpha greater than zero. This rule applies only where the trusted profile declares it. It must not be imposed globally on hip, side-hanging, trinket, or other intentionally suspended sockets.

Non-humanoid rigs must use an explicitly implemented profile kind. Unknown or missing profile kinds fail closed; they do not inherit humanoid geometry or bypass topology coverage.

## Runtime placement

For `RIGID`, determine the pivot from the exact nearest-resized raster used at runtime:

```text
top_left_px = socket_position_px - rendered_pivot_px + local_offset_px
godot_local_position = top_left_px - frame_size_px / 2
```

Use `Sprite2D.centered = false`, nearest filtering, and the approved render scale. This keeps the resolved top-left origin integral.

For `FRAME_OVERLAY`, each overlay animation must match the base animation name and frame count. The runtime changes the overlay texture when the base frame changes; the overlay never plays independently. A full-frame overlay is positioned at `-frame_size / 2 + local_offset_px`.

## Authoring and QA

1. Design socket topology from the item-family mapping, not from a single current item.
2. Mark every socket independently on every frame in authored-frame image space. Repeated coordinates are acceptable only after visual inspection proves the anatomy is stationary; do not mirror or swap left/right from another facing or animation.
3. Before updating trust, run `check_stale_socket_geometry.py --baseline-rig <previous-approved-rig.json> --candidate-rig <new-rig.json> --animation <walking-animation-id>`. It hard-fails when one axis-aligned affine transform explains at least 80% of old-to-candidate socket positions, including phase-shifted cycles, only-new-tail reuse, and old frames with a few points snapped to opaque pixels. The CLI requires the baseline hash to equal the current trusted binding, so run it before replacing that binding.
4. Update the checker-owned trusted binding in the same reviewed change, then run `check_character_socket_rig.py --rig <v2.json> --atlas <atlas.png> --asset-registry <gogobro_static_assets_v1.json> --out-dir <new-output-dir>` in a separate output directory. The checker independently pins the rig SHA-256 and rig ID plus source profile, atlas/hash/grid, exact FPS, exact animation-ID set, row and frame count; an unbound draft cannot return `rig_pass`. The CLI always requires the authoritative registry; the Python API keeps its registry argument optional only for compatibility with older callers.
5. Inspect the overview and per-socket contact sheet, with extra attention to the final two frames and extremities.
6. Run the Godot runtime parity test. Compare actual walking `Sprite2D.position`, scale, depth, FPS and overlay texture with the offline resolved values; verify hurt composites white and death hides appearance without socket lookup.
7. Preserve each trusted walking animation's atlas hash, grid, frame count and FPS independently.

Residual jitter is measured independently for each animation as the order-independent x/y span of the socket residual from its per-frame reference-region center. Animation JSON key order must not change the verdict.

The checker hard-fails malformed contracts, invalid visible-item appearance data, registry/socket contract mismatch, trusted animation-set mismatch, per-binding row/grid/frame-count/FPS mismatch, source-profile binding or per-frame region/protected-region drift, atlas/hash or rectangular-row coverage mismatch, frame identity mismatch, missing sockets, required opaque-contact misses, missing protected regions, non-integer/out-of-frame positions or boxes, region mismatch, excessive residual jitter and front-layer back attachments. The separate stale-geometry negative gate hard-fails 80%-or-greater affine/cyclic reuse from the previous approved rig. `socket-rig-report.json` includes deterministic structured `issues`; every entry has exactly `animation`, `frame`, `socket`, and `code`, using `null` only when a failure applies globally rather than to one frame or socket.
