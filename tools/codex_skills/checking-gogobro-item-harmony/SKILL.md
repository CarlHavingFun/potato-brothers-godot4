---
name: checking-gogobro-item-harmony
description: Use when authoring or reviewing GOGOBRO per-frame character item sockets, item icons, or appearance layers for slot/socket fit, pivot alignment, scale, occlusion, pixel density, palette, depth, runtime parity, or multi-frame visual harmony.
---

# Checking Gogobro Item Harmony

Author and review GOGOBRO character socket rigs and item appearance layers with deterministic hard gates first, then visual inspection. Keep equipment conflict rules separate from spatial attachment geometry.

This Skill's equipment-bearing animation scope is walking only. Author and trust per-frame item sockets for walking states. A hurt response is a whole-composite white flash applied after the base character and appearance layers are combined; it is not a separate hit sprite with copied equipment sockets. A death state hides the appearance layer and plays the unadorned death animation. Do not author, infer, or fall back to hurt/hit/death sockets.

## Choose the workflow

- For a new or changed character animation, read [trusted-bindings-and-appearance-matrix.md](references/trusted-bindings-and-appearance-matrix.md), [attachment-rig-schema.md](references/attachment-rig-schema.md), and [slot-profiles.md](references/slot-profiles.md) before designing the socket catalog, then run `scripts/check_character_socket_rig.py`. Every declared socket and every socket required by the character's explicit profile kind must exist on every frame of every registered animation.
- For a new or changed item, first require a passing socket-rig report, then read [slot-profiles.md](references/slot-profiles.md) and [appearance-contract-v2.md](references/appearance-contract-v2.md). Author a strict v2 item contract and run `scripts/check_item_socket_harmony_v2.py`.
- Before release, read [trusted-bindings-and-appearance-matrix.md](references/trusted-bindings-and-appearance-matrix.md), validate the manifest against [character-item-appearance-matrix-v1.schema.json](references/character-item-appearance-matrix-v1.schema.json), then run `scripts/check_character_item_appearance_matrix.py --matrix <matrix.json> --registry <authoritative-registry.json> --out-dir <new-output-dir>`. A single passing item contract proves only that one tuple; it does not establish roster coverage.
- Treat `scripts/check_item_harmony.py` and existing `gogobro-item-anchors-v1` files as frozen v1 candidate-audit compatibility only. New runtime content uses the v2 character rig plus one item pivot; do not use old per-item absolute offsets for approval or runtime placement.
- The v2 item checker gates the worn appearance layer, not its inventory icon. Audit the icon separately with the frozen checker's icon pixel/style policy (or the approved icon QA pipeline). Neither gate substitutes for the other.

`conflict_slot` decides which owned appearance wins. `socket_id` decides where it attaches. Different item topologies in one slot use different sockets, such as `head_shell` versus `forehead`.

## Character socket-rig gate

1. Run `scripts/check_character_socket_rig.py --rig <v2.json> --atlas <atlas.png> --asset-registry <authoritative-registry.json> --out-dir <new-output-dir>`.
2. The character checker requires an exact Skill-owned rig binding: rig SHA-256, rig ID, source-profile path/schema/hash, atlas/hash/grid, exact FPS, complete animation-ID set, and every row/frame count must match. It resolves the source profile and compares every authored attachment region, `face_roi`, and protected region with the corresponding rig frame. An intentional rig change must update the trusted catalog in the same reviewed package change before it can return `rig_pass`. Stop on `hard_fail`; report reason codes, coverage, and affected animation/frame/socket.
3. Before trusting a changed walking animation, run `scripts/check_stale_socket_geometry.py --baseline-rig <previous-approved-rig.json> --candidate-rig <new-rig.json> --animation <walking-animation-id>`. A cyclic copy of the old frames is a negative-control failure when one axis-aligned scale/translation explains at least 80% of old-to-candidate socket positions; sparse opaque-contact snapping cannot hide the reuse. The CLI pins the baseline hash to the current trusted binding, searches every cycle phase, and checks newly appended frames separately. Run it before replacing that binding.
4. Inspect both `socket-rig-overview.png` and every `socket-rig-<animation>-contact-sheet.png`. JSON completeness alone is not visual approval.
5. Confirm the Godot runtime parity test reads the same v2 walking JSON and exact FPS. Validate every currently integrated appearance origin against its resolved socket transform. Verify hurt flashes the combined base-plus-appearance result white, and death disables the appearance layer rather than requesting hit/death sockets. Ungenerated or unintegrated items may pass socket-coverage checks, but cannot receive item-harmony approval. A passing offline rig without runtime parity is not integrated.
6. Never reuse frame zero, the preceding frame, an older animation's coordinate cycle, or a slot-region center when a frame socket is missing.
7. Treat `profile_kind` as mandatory trusted character metadata. `humanoid_v1` requires the clothes socket and every left/right shoulder, upper-arm, forearm, and hand socket on every walking frame. A non-humanoid character must name another explicitly supported profile kind; never silently apply `humanoid_v1` or an empty topology.
8. Interpret socket suffixes `left` and `right` in authored-frame image space: `left` is the smaller-x side of the image, not the character's anatomical side. Re-mark them for every frame, character, animation, and facing; never auto-mirror or swap sockets from another animation.
9. For `humanoid_v1`, confirm all nine clothes/arm topology sockets land on an opaque base-atlas pixel in every walking frame. This contact rule is profile-owned; do not apply it globally to intentionally suspended hip, side, or trinket sockets.

## Required recipe

Return the verdict and evidence in this order:

1. Require a passing v2 socket rig. Author a contract that validates against [appearance-contract-v2.schema.json](references/appearance-contract-v2.schema.json), then run `scripts/check_item_socket_harmony_v2.py --rig <v2.json> --registry <authoritative-registry.json> --asset-id <asset_id> --contract <appearance-v2.json> --atlas <atlas.png> --appearance <appearance.png> --out-dir <new-output-dir>`. Add `--visual-rubric` only after completing the strict rubric.
2. If the checker returns `hard_fail`, report its reason codes and measurements, then stop before approval.
3. If geometry passes, inspect both `harmony-overlay.png` and `harmony-actual-size.png`.
4. Score character identity, item function, material/outline fit, value/color hierarchy, and originality from 0–2. Each JSON dimension is exactly `{score, evidence}` with an integer score (never bool) and non-empty evidence; no extra or missing keys.
5. Return `review` when the total is below 8/10 or any score is zero; otherwise return `harmony_pass`.
6. Verify the item's conflict slot, socket, mode and depth against the authoritative registry and character rig. Verify the rendered pivot from the contract's independent source pivot and scale. Never conflate its conflict slot with its spatial socket.
7. Confirm the v2 report's embedded character-rig gate is `rig_pass`. Its checker-owned trusted character/animation binding must match the selected walking animation's rig, source profile, atlas, frame layout, frame count and exact FPS, plus the character binding's registry schema, declared visible-item count and registry-mapping digest. For every trusted rig, the catalog animation-ID set must exactly equal `rig.animations`, and every binding must match its own row/grid/frame-count/FPS contract. Self-consistent edits to caller-supplied files do not establish authority, and callers cannot supply or override the trusted catalog or inject a replacement sibling loader.
8. Never place the output directory where `harmony-report.json`, `harmony-overlay.png` or `harmony-actual-size.png` can overwrite an input. Never mutate source assets or anchors, accept a transform suggestion automatically, or advance registry approval.

## Release coverage gate

The v2 checker validates exactly one `(character_id, asset_id, animation_id)` worn-appearance contract. Release additionally requires an exact appearance-matrix entry for every trusted playable character × every visible registry item × every trusted animation for that character. A visible item is exactly a `category: item` unit that contains the `appearance` key; a missing key means non-visible and excludes the unit from trusted mapping count/digest and the matrix, while a present but non-exact appearance object hard-fails.

Each matrix entry supplies relative paths for `contract`, archived `harmony_report`, `rig`, `atlas`, `appearance`, and `visual_rubric`. The matrix checker reruns the single-item checker in a fresh isolated QA directory and requires the recomputed `harmony_pass` report to equal the archived report exactly as JSON data. A handwritten verdict is not evidence. Missing, duplicate, extra, mismatched, stale, or non-reproducible entries hard-fail. Do not use a generic character appearance, a default animation contract, or a "no matching appearance" fallback.

## Slot selection

When choosing or reviewing a profile, read [slot-profiles.md](references/slot-profiles.md). Use the exact conflict-slot/socket pair, feature and protected regions; do not apply head geometry to another topology.

For new runtime items, the v2 appearance contract source-binds the character rig, registry, atlas and appearance. `RIGID` uses one full-frame source and resolves it against every frame socket. `FRAME_OVERLAY` uses a full horizontal animation atlas and follows the selected base animation's frame index. Its width follows that animation binding's independent frame count; never assume eight frames or reject an overlay merely because it is wider than one character frame.

For frozen v1 audit only, formal anchors bind a 64×64 logical canvas, exact 2× appearance and 4× icon grids, nearest resampling, and a frozen outline palette. Never derive or relax that palette during review. Unknown explicit anchor or rig schemas are invalid; formal anchors cannot omit `pixel_contract`. Recognized integer-`1` legacy anchors remain measurable audit evidence. Canonical v1 rigs bind the character-atlas SHA-256. `direct_icon_reuse:true` requires exact nearest 2× reuse; `false` permits an independent icon that still passes its 4× grid. Treat JSON types exactly: never coerce bools or numeric strings; offsets/boxes are integer arrays and `occupied_slots` is a string array.

## Output contract

The v2 checker measures the exact nearest-resized raster used in its composite. `harmony-report.json` records the registry mapping, rig socket contract, bound input hashes, source integrity and every frame's socket, runtime top-left, Godot-local position, rendered size, pivot, opaque bounds and overlay source-frame index. It writes `harmony-overlay.png` and `harmony-actual-size.png` when the transform can be resolved. Any hard failure exits `2`; `review` and `harmony_pass` exit `0`.

The frozen v1 checker retains its previous threshold, icon, transform-suggestion and audit report contract. Do not interpret a v1 pass as a v2 runtime-placement pass.

The socket checker returns `hard_fail` or `rig_pass`. The v2 item checker returns `hard_fail`, `review`, or `harmony_pass`. Include reason codes, resolved per-frame values, visual evidence, and the final verdict. Any hard failure blocks approval. `rig_pass` and `harmony_pass` confirm only their respective gates; explicit human approval is still required.
