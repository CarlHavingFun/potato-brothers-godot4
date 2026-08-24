# GOGOBRO Character Attachment Rig v2

## Goal

Attach item appearances to character anatomy without modifying the character atlas or storing one absolute offset list per item.

## Model

The system separates three responsibilities:

- `slot`: appearance conflict and replacement rules.
- `socket_id`: the character-space attachment topology.
- item pivot: the functional pixel on the rendered item that touches the socket.

A character owns a versioned JSON rig. Each registered animation and every frame contain the complete socket catalog. A formal appearance never falls back to frame zero, the preceding frame, a region center or a legacy offset.

Niko's initial catalog contains 24 sockets:

- head: `head_shell`, `forehead`
- face: `face_mask`
- torso: `chest_center`, `chest_left`
- back: `back_upper`, `back_center`, `back_lower`
- wrists: `wrist_left`, `wrist_right`
- feet: `feet_pair`
- side attachments: `hip_left`, `hip_right`
- trinkets: `trinket_left`, `trinket_right`
- clothes: `clothes_body`
- screen-left arm: `shoulder_left`, `upper_arm_left`, `forearm_left`, `hand_left`
- screen-right arm: `shoulder_right`, `upper_arm_right`, `forearm_right`, `hand_right`

For the facing-down atlas, `left` and `right` are authored screen-space labels: `left` is the smaller pixel x coordinate. They do not mean the character's anatomical left/right. Runtime never swaps or mirrors these sockets automatically; every new facing or animation must be annotated frame by frame.

The canonical 30-item registry assigns one conflict slot, socket, mode and depth to every item. Back appearances use negative depth. Clothes share the `clothes` conflict slot at depth 20. All four screen-left arm sockets share `arm_left`, all four screen-right sockets share `arm_right`, and both arm slots render at depth 50. Thus clothes render above the base character while arm equipment renders above clothes; equal-depth ordering never depends on an appearance ID by accident.

## Runtime

`GogoCharacterAttachmentRig` loads and validates the v2 JSON, including character binding, source atlas SHA-256, exact atlas/frame grid, one unique animation per atlas row, declared FPS, frame identity, complete socket coverage, protected/reference regions, per-animation residual jitter and depth direction. Each animation covers every atlas column. Runtime `SpriteFrames` must use the same atlas resource and exact ordered `AtlasTexture` regions. The Resource stores its parsed data so content snapshot duplication preserves the rig.

`CharacterVisualRig` listens to the base `AnimatedSprite2D` frame and animation signals.

- `RIGID`: one frame-sized texture follows the active frame socket. Its top-left origin is `socket - rendered_pivot + local_offset`; the nearest-rendered size must be integral and the pivot must stay inside it.
- `FRAME_OVERLAY`: a full-frame overlay texture is selected from a synchronized `SpriteFrames`; it never plays independently. Every overlay frame is exactly the character frame size and its render scale is `Vector2.ONE`.
- `LEGACY_STATIC`: retained only for existing validation content and does not participate in formal socket integration.

Every formal `RIGID` or `FRAME_OVERLAY` appearance declares a non-empty `target_character_id`. The visual rig filters variants by the current character before conflict resolution and validation. A declared variant for another character is ignored, so one item can carry multiple character-specific render definitions. A matching-character formal variant remains fail-closed: missing textures, overlays, sockets, slots, modes, depths or frame coverage reject the configuration instead of falling back to another character or frame zero.

`clothes_body` accepts only `FRAME_OVERLAY` because clothing must deform with the eight authored body frames. Arm sockets accept `RIGID` for small attached equipment and `FRAME_OVERLAY` for deforming sleeves or guards. Both overlay types stay locked to the active base animation/frame and never own an animation clock.

The base character atlas remains byte-identical.

## Verification

- Godot integration covers all 24 sockets on all eight Niko frames, exact helmet and arm origins, screen-left/right ordering, clothes/arm depth contracts, per-side conflict resolution, target-character filtering/fail-closed matching variants, stop/reset synchronization, frame-overlay texture synchronization, atlas path/region/FPS binding and malformed-rig rejection.
- The item registry validator locks all 30 item IDs to their exact slot/socket/mode/depth tuple and rejects fractional or incorrect depth.
- The installed `checking-gogobro-item-harmony` character gate compares the rig with the authoritative 30-item registry, validates atlas binding, animation/frame identity, complete socket coverage, protected/reference regions, integer/in-region positions, per-animation residual drift and depth, then outputs an all-socket overview and a per-socket, per-frame contact sheet.
- Its v2 item gate binds one item contract to the trusted character rig, source profile, atlas and registry mapping. `RIGID` resolves one pivot across every base frame; `FRAME_OVERLAY` validates and composites the matching frame from a full horizontal appearance atlas. It records the exact runtime top-left and Godot-local position for every frame.
- Mechanical `rig_pass` / `harmony_pass` results never advance registry approval. Each generated item still requires the planned human approval card and actual-size screenshot review.
- A one-pixel socket change on the final frame is a deterministic hard failure.

## Approval status

`smoke_shell_helmet` candidate `candidate-002` received explicit user approval on `2026-08-24T12:04:47Z`. The registry preserves both original candidate records and appends a separate human-approval event; the mechanically produced `harmony_pass` remains unchanged. Its unit status is now `approved` only: no runtime asset has been copied, its runtime hash remains unset, and it is neither `integrated` nor `qa_passed`.
