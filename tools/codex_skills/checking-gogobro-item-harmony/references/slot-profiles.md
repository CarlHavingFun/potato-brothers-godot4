# GOGOBRO slot profiles

Use this reference only when choosing or reviewing an appearance slot. The rig profile supplies the named ROI for every frame; boxes use `[left, top, right, bottom]` with exclusive right/bottom edges. A candidate may narrow these limits but must not relax them.

## Conflict slots and spatial sockets

Slots are conflict groups. Sockets are per-frame character coordinates. An appearance must declare both; the v2 character rig validates the pair.

These slot/socket profiles are authored only for equipment-bearing walking frames. Hurt keeps the same walking appearance composite and flashes the whole result white; death hides the appearance layer. Hit/hurt/death art has no slot profile, no item socket set, and no fallback to walking coordinates.

### Mandatory `humanoid_v1` topology

Every humanoid walking frame includes this minimum topology even when the current registry does not yet assign a visible item to every socket:

| Socket | Conflict slot | Allowed modes | Default depth | Opaque contact | Intended anatomy |
| --- | --- | --- | ---: | --- | --- |
| `clothes_body` | `clothes` | `FRAME_OVERLAY` | 20 | required | body garment canvas |
| `shoulder_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-left shoulder |
| `upper_arm_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-left upper arm |
| `forearm_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-left forearm |
| `hand_left` | `arm_left` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-left hand/contact point |
| `shoulder_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-right shoulder |
| `upper_arm_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-right upper arm |
| `forearm_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-right forearm |
| `hand_right` | `arm_right` | `RIGID`, `FRAME_OVERLAY` | 50 | required | image-right hand/contact point |

`left` and `right` mean authored-frame image space: `left` has the smaller x coordinate and `right` has the larger x coordinate. They are not the character's anatomical sides. Mark each socket from that frame's visible anatomy; do not copy frame zero, derive every arm segment from one hand point, or automatically mirror/swap a previous facing or animation. Depth 20 places clothes below the depth-50 arm segments. Image-space left and right arms use separate conflict slots, while the segment sockets within a side let the item select the correct anatomy. All nine rows above require the socket pixel to hit alpha greater than zero in the current base-atlas frame. This is not a global rule: hip, side-hanging, trinket, and similar sockets can be suspended in transparent space unless their trusted profile says otherwise. These profile sockets do not rewrite an existing item's registry tuple: every item contract must still match its exact authoritative slot, socket, mode and depth.

A non-humanoid character must declare another explicit trusted profile kind with its own topology. Never silently use `humanoid_v1`, omit the baseline, or accept an unknown kind as having no required sockets.

### Initial visible-item mapping

The 30-item initial mapping is fixed as follows:

| Asset ID | Conflict slot | Socket ID | Mode | Depth |
| --- | --- | --- | --- | ---: |
| `ballistic_liner` | `torso` | `chest_center` | `FRAME_OVERLAY` | 40 |
| `silent_step_insoles` | `feet` | `feet_pair` | `FRAME_OVERLAY` | 40 |
| `crosshair_shim` | `wrist` | `wrist_right` | `FRAME_OVERLAY` | 40 |
| `supply_radar` | `side_left` | `hip_left` | `RIGID` | 40 |
| `trade_guard` | `wrist` | `wrist_left` | `FRAME_OVERLAY` | 40 |
| `tactical_med_patch` | `torso` | `chest_left` | `FRAME_OVERLAY` | 40 |
| `smoke_shell_helmet` | `head` | `head_shell` | `RIGID` | 40 |
| `force_buy_runners` | `feet` | `feet_pair` | `FRAME_OVERLAY` | 40 |
| `eco_round_coin_pouch` | `side_right` | `hip_right` | `RIGID` | 40 |
| `rebound_fire_bottle` | `side_left` | `hip_left` | `RIGID` | 40 |
| `entry_fragger_dumbbell` | `back` | `back_upper` | `RIGID` | -10 |
| `corner_lucky_claw` | `trinket_left` | `trinket_left` | `RIGID` | 40 |
| `scorched_defuse_pliers` | `side_right` | `hip_right` | `RIGID` | 40 |
| `save_time_watch` | `wrist` | `wrist_right` | `FRAME_OVERLAY` | 40 |
| `skyline_grenade` | `side_left` | `hip_left` | `RIGID` | 40 |
| `post_match_analysis_desk` | `back` | `back_center` | `RIGID` | -10 |
| `one_missed_shot` | `trinket_right` | `trinket_right` | `RIGID` | 40 |
| `falling_sniper_charm` | `trinket_left` | `trinket_left` | `RIGID` | 40 |
| `boost_step_stool` | `back` | `back_lower` | `RIGID` | -10 |
| `post_match_mic` | `torso` | `chest_center` | `FRAME_OVERLAY` | 40 |
| `halftime_tactics_board` | `back` | `back_center` | `RIGID` | -10 |
| `hand_cannon_ace_coin` | `trinket_right` | `trinket_right` | `RIGID` | 40 |
| `sneaky_site_mask` | `face` | `face_mask` | `RIGID` | 40 |
| `arena_chant_cassette` | `side_right` | `hip_right` | `RIGID` | 40 |
| `mouse_lift_pad` | `back` | `back_upper` | `RIGID` | -10 |
| `lineup_chalk` | `side_left` | `hip_left` | `RIGID` | 40 |
| `site_hold_bandana` | `head` | `forehead` | `RIGID` | 40 |
| `airshot_wing_charm` | `trinket_left` | `trinket_left` | `RIGID` | 40 |
| `clutch_stopwatch` | `wrist` | `wrist_left` | `FRAME_OVERLAY` | 40 |
| `three_beat_magazine` | `side_right` | `hip_right` | `RIGID` | 40 |

For a rigid appearance, author the rendered pivot at the functional contact point—not at the alpha-bounds center. A helmet uses its face aperture, a hanging charm uses its loop, and a side pouch uses its belt loop. Full-frame overlays still require a valid socket for coverage and conflict validation, but their runtime canvas stays aligned to the character frame.

Canonical v1 slot contracts require `min_outline_boundary_coverage: 1.0`; this applies to the source and every actual nearest-resized render. The `head` contract also requires `max_opaque_components: 1`. Formal `gogobro-item-anchors-v1` data binds logical canvas `[64,64]`, appearance/icon grid scales `2/4`, `resampling: nearest`, and a frozen non-empty sorted `outline_colors_rgb` list. Both source PNGs must survive exact nearest down/up RGBA round trips. Boundary colors and four-connected opaque components are measured again after each frame's real resize.

Schema and raw JSON validation are type-exact. Unknown explicit anchor/rig schemas fail `invalid_contract`; formal anchors require the complete pixel contract. Integer-schema-`1` legacy anchors remain measurable for audit, while schema-less fixtures are the only generic legacy form. Coordinates/scales/depths cannot be bools or numeric strings, scales/depths must be finite, offsets and boxes use exact integer arrays, frames use arrays of objects, and `occupied_slots` uses an array of strings.

`direct_icon_reuse` is an exact boolean. Only `true` requires the icon to equal the appearance's nearest 2× derivation; `false` permits an independent icon that still satisfies the 4× grid. Niko currently uses direct reuse for `head` and independent-icon policy for every other slot.

The `Flip behavior` column below is frozen v1 candidate-audit metadata for an item's paired visual treatment. It never authorizes generating, mirroring, swapping, or inheriting v2 character sockets across frames, animations, facings, or characters. The v2 rig's authored per-frame coordinates and `flip_h` contract remain authoritative.

| Slot | Feature anchor | Allowed silhouette ratio | Protected ROI | Maximum occlusion | Depth band | Flip behavior |
| --- | --- | --- | --- | --- | --- | --- |
| `head` | largest enclosed aperture → `face_center` | head width × `1.05–1.15` | `eyes` | `0` | front `1–99`; expected `40` | none |
| `face` | center of `face_roi` | face width × `0.55–0.90` | `eyes` | `0` | front `1–99`; expected `40` | none |
| `torso` | center of `attachment_regions.torso` | torso width × `0.55–1.00` | `face` | `0.15` | front `1–99`; expected `40` | none |
| `back` | center of `attachment_regions.back` | back width × `0.60–1.20` | `face` | `0.25` | behind `-99–-1`; expected `-10` | none |
| `wrist` | center of `attachment_regions.wrist_right` (`selected_side: right`) | right-wrist width × `0.25–0.60` | `face` | `0.10` | front `1–99`; expected `40` | mirror between wrist boxes |
| `feet` | center of `attachment_regions.feet` | feet width × `0.55–1.10` | `face` | `0.15` | front `1–99`; expected `40` | none |
| `side_left` | center of `attachment_regions.side_left` | side width × `0.40–0.90` | `face` | `0.10` | front `1–99`; expected `40` | mirror to right |
| `side_right` | center of `attachment_regions.side_right` | side width × `0.40–0.90` | `face` | `0.10` | front `1–99`; expected `40` | mirror from left |
| `trinket_left` | center of `attachment_regions.trinket_left` | trinket width × `0.20–0.55` | `face` | `0.05` | front `1–99`; expected `40` | mirror to right |
| `trinket_right` | center of `attachment_regions.trinket_right` | trinket width × `0.20–0.55` | `face` | `0.05` | front `1–99`; expected `40` | mirror from left |

For `head`, align the aperture to the face within 1 px per frame and keep residual jitter at or below 1 px. Other slots use their own named boxes and limits; never substitute the head aperture or head ratio.

Geometry, crop, protected-region occlusion, feature centers, and diagnostics come from the exact Pillow nearest raster at `round(source_size × scale)`. Do not use continuous floor/ceil projection or inverse-map destination pixels back into the source.

The report threshold snapshot repeats the applied appearance/icon/atlas sizes, frame count, ratio, feature/jitter/occlusion/palette/outline/component limits, depth band and expected depth, direct-icon policy, flip behavior, and formal pixel contract. Transform suggestions copy this map exactly. If anchors are missing or unreadable, the suggestion contains no claimed current transform and remains `manual_correction_required`.

The canonical Niko walk-down boxes and machine-readable thresholds are in `tools/assets/rig_profiles/niko_walk_down_v1.json`.
