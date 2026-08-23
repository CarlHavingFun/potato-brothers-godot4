# GOGOBRO slot profiles

Use this reference only when choosing or reviewing an appearance slot. The rig profile supplies the named ROI for every frame; boxes use `[left, top, right, bottom]` with exclusive right/bottom edges. A candidate may narrow these limits but must not relax them.

Canonical v1 slot contracts require `min_outline_boundary_coverage: 1.0`; this applies to the source and every actual nearest-resized render. The `head` contract also requires `max_opaque_components: 1`. Formal `gogobro-item-anchors-v1` data binds logical canvas `[64,64]`, appearance/icon grid scales `2/4`, `resampling: nearest`, and a frozen non-empty sorted `outline_colors_rgb` list. Both source PNGs must survive exact nearest down/up RGBA round trips. Boundary colors and four-connected opaque components are measured again after each frame's real resize.

`direct_icon_reuse` is an exact boolean. Only `true` requires the icon to equal the appearance's nearest 2× derivation; `false` permits an independent icon that still satisfies the 4× grid. Niko currently uses direct reuse for `head` and independent-icon policy for every other slot.

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

The canonical Niko walk-down boxes and machine-readable thresholds are in `tools/assets/rig_profiles/niko_walk_down_v1.json`.
