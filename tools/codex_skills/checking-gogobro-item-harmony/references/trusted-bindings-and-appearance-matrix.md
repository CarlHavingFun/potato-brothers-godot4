# Trusted character bindings and appearance coverage

Use this reference when adding a playable character, adding or changing one of its animations, changing the visible-item registry mapping, or preparing a release coverage audit.

## Checker-owned authority

`trusted-character-animation-bindings-v1.json` is package-owned trust configuration loaded from a fixed path inside this Skill. Runtime callers, item contracts, and command-line invocations do not provide a catalog path and cannot replace, extend, or self-sign this catalog. The checker creates and executes its trust helper from the fixed resolved sibling file rather than accepting a pre-populated `sys.modules` object; module-cache injection and caller-selected loader aliases do not establish authority.

Caller-supplied SHA-256 values still bind a contract to the exact files being checked, but they do not make those files authoritative. The checker independently resolves the character and animation from its internal catalog. Unknown characters, unknown animations, missing profile kinds, and any trusted-source mismatch fail closed.

Each trusted character binding declares:

- the exact `character_id` and whether it is a formal playable character;
- an explicit `profile_kind`;
- the authoritative registry `schema_version`, expected visible-item count, and semantic item-appearance mapping digest;
- one or more named animation bindings.

Each walking-animation binding independently declares its rig ID and SHA-256, source-profile path/schema/SHA-256, atlas SHA-256, frame size, atlas size, grid, row, frame count and exact positive finite FPS. Different characters and different walking animations may therefore use different frame counts, rates and atlas layouts. Do not infer one animation's FPS, frame count, grid, row, size, or hashes from another animation, even on the same character.

Only walking animations receive equipment bindings and per-frame sockets. Hurt is a whole-composite white flash over base plus appearance. Death hides appearance and plays an unadorned death animation. Do not register hit/hurt/death sockets or expand the appearance matrix with those non-equipment states.

For every trusted rig, collect all catalog animation IDs bound to that exact rig. This set must equal the keys in the rig's `animations` object exactly. A rig animation without a catalog binding is an untrusted, unregistered animation and hard-fails; a catalog animation absent from the rig also hard-fails. After set equality, each binding independently checks its selected atlas row, grid and frame count. Registering one animation never authorizes another animation merely because both are present in the same rig file.

The character rig checker resolves the relative source profile under the source tree and binds its path, schema and SHA-256. It then compares the profile's atlas metadata, frame count and every frame's owned attachment regions, face ROI and protected regions with the rig. Matching hashes alone cannot conceal stale or hand-edited rig regions. The binding's FPS must equal the rig animation's FPS exactly; approximate, inherited, missing, boolean, string, zero, negative, NaN and infinite rates are invalid.

Because `rig.source_profile` is one top-level path, every animation binding that shares one exact `rig_sha256` must declare the same source-profile path, schema and hash. The catalog validator rejects a rig group whose per-animation profile declarations cannot all be satisfied by that one rig.

The item count is not a global checker constant. It is part of the trusted character-to-registry binding and counts visible/wearable items only. A visible item is a registry unit with `category: item` and an `appearance` key. A `category: item` unit without that key is non-visible and is excluded from the trusted count, semantic mapping digest and appearance matrix. If the key exists, its value must have exactly `slot`, `socket`, `mode`, and `depth`, with no missing or extra keys and exact value types; malformed presence hard-fails rather than becoming non-visible. An intentional visible-item addition, removal, or appearance-remapping requires a reviewed update to the binding's item count or mapping digest. Merely updating the registry and item contract together must continue to fail.

## Profile kinds

`profile_kind` is mandatory. `humanoid_v1` has the following minimum topology on every frame of every trusted animation:

| Socket | Slot | Allowed modes | Default depth | `require_opaque_contact` |
| --- | --- | --- | ---: | --- |
| `clothes_body` | `clothes` | `FRAME_OVERLAY` | 20 | `true` |
| `shoulder_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `upper_arm_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `forearm_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `hand_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `shoulder_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `upper_arm_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `forearm_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |
| `hand_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | `true` |

The clothes layer is deliberately below the arm segments. Arm sockets use depth 50 so sleeves, guards and held attachments stay in front of the depth-20 body garment; this avoids a clothes-versus-arm same-depth ambiguity while left and right ownership remains separated by `arm_left` and `arm_right`.

`require_opaque_contact: true` means that, for every bound animation frame, the socket coordinate must address a base-atlas pixel whose alpha is greater than zero. It prevents a nominal shoulder, sleeve, hand, or body socket from floating in transparent space. This is an explicit topology-profile rule for these nine sockets, not a global rule for all sockets. Hip, side-hanging, trinket, and similar suspended sockets may legitimately sit in transparent space unless another trusted profile explicitly opts them into opaque contact.

All `left`/`right` names are authored-frame image-space names: `left` is the smaller-x side of the current frame, not anatomical left. Direction changes may reverse which anatomical limb occupies an image-space side. Re-author every required socket per frame for each character, animation and facing. A trusted binding never authorizes automatic mirroring, left/right exchange, or reuse from the preceding animation.

A non-humanoid character must select another explicitly implemented and trusted profile kind. Do not silently default it to `humanoid_v1`, omit topology requirements, or treat an unknown profile kind as an empty socket set.

## Character × visible item × animation matrix

`check_item_socket_harmony_v2.py` validates one character-specific worn appearance for one animation. It does not prove that the same item works on other playable characters or animations. The release coverage gate is a separate manifest-level check.

For each trusted formal playable character, form the Cartesian product of:

1. every registry `category: item` unit with a present, exact `appearance` object;
2. every trusted animation registered for that character.

The appearance matrix must contain exactly one entry for every resulting `(character_id, asset_id, animation_id)` tuple. A `category: item` unit without `appearance` is non-visible and does not produce a tuple. A present but malformed `appearance` object invalidates the registry and hard-fails; it is never skipped.

Each entry has exactly these identity and relative-path fields:

| Field | Meaning |
| --- | --- |
| `character_id` | trusted playable character |
| `animation_id` | trusted animation on that character |
| `asset_id` | visible registry item |
| `contract` | character/item/animation strict v2 contract |
| `harmony_report` | archived report expected from a fresh rerun |
| `rig` | exact character rig source |
| `atlas` | exact base character atlas source |
| `appearance` | exact worn-appearance PNG source |
| `visual_rubric` | strict five-dimension rubric source |

All six source/report paths resolve relative to the matrix manifest directory and may not use an absolute path or a `..` component. The coverage checker verifies tuple identity and bound sources so data for another character, item, animation, or an older contract cannot satisfy the entry.

The matrix is a release hard gate:

- a missing tuple fails before release;
- duplicate or unexpected tuples fail rather than being ignored;
- a stale, missing, non-passing, tuple-mismatched, or non-reproducible harmony report fails;
- a generic appearance contract, inherited default, animation substitution, or "no matching appearance" fallback is forbidden.

Run the single-contract v2 checker first for every matrix entry, including visual review and human approval where required. Validate the complete manifest against `character-item-appearance-matrix-v1.schema.json`, then run `scripts/check_character_item_appearance_matrix.py --matrix <matrix.json> --registry <authoritative-registry.json> --out-dir <new-output-dir>`. For each entry, the matrix checker calls the single-contract checker again with the listed rig, atlas, appearance, contract and visual rubric in a fresh isolated QA output directory. It requires the recomputed verdict to be `harmony_pass` and the recomputed report to equal the archived `harmony_report` exactly as parsed JSON data. Formatting differences are irrelevant, but every key and value must match. It does not trust a stored or handwritten `harmony_pass` field and cannot upgrade `review` to approval.

## Controlled update procedure

When intentionally adding a character or animation, changing an atlas/rig/source profile, or changing registry appearance semantics:

1. author and validate the new walking source data;
2. when replacing an existing trusted walking animation, run `check_stale_socket_geometry.py` against its previous approved rig and reject cyclic or single-axis-aligned-affine reuse at the 80% exact-inlier threshold; a genuinely new character/animation has no prior baseline and skips only this negative control;
3. update the Skill-owned trusted binding, including exact FPS, in the same reviewed change;
4. update bypass/forward tests so synchronized caller-file tampering still fails;
5. rerun the character rig gate, then generate and approve each required character/item/walking-animation contract;
6. rebuild the complete matrix and run its release gate;
7. confirm Godot parity against the same trusted walking rig, atlas, FPS and frame selection, plus whole-composite hurt white-flash and death-time appearance hiding.

Never expose a command-line or contract field that lets a caller choose the trusted catalog.
