# GOGOBRO Full Static Assets and Brotato-Style HUD Design

## Goal

Make every registered non-character static asset visible through a real game consumer while keeping Niko as the only character placeholder. The combat presentation follows Brotato's information hierarchy, immediacy, large readable silhouettes, automatic weapon behavior, and compact feedback language, while all rendered artwork remains original GOGOBRO CSGO-community pixel art.

This is a functional and visual reference, not a copy of Brotato source art. No Brotato textures, fonts, icons, logos, or source files enter the project.

## Authoritative scope

The canonical registry contains exactly 70 non-character units:

- 12 weapons
- 30 items
- 6 upgrades
- 11 world assets
- 10 UI/brand assets
- 1 projectile/hit kit

The development candidate manifest provides 61 current candidates. Eight additional registry units already have active shipping bindings: `warmup_shiv`, `service_pistol`, `projectile_hit_kit`, `ballistic_liner`, `one_more_round`, `hud_icon_kit`, `control_icon_kit`, and `difficulty_badge_kit`. `smoke_shell_helmet` has explicit human approval and complete candidate evidence but has not yet been installed into the runtime tree. Full coverage therefore requires both candidate integration and installation of the approved helmet.

Character scope is fixed to one definition: `character.niko:character/niko`. This work does not generate or restore another character.

## Chosen architecture

Use real consumer integration. Assets are resolved through `GogoStaticAssetSnapshot`, then consumed by content definitions, UI screens, or combat-world nodes. A gallery can be generated for QA, but it is never accepted as proof that an asset is integrated.

Two rejected alternatives are:

- a review-only gallery, which is fast but does not prove gameplay fit;
- a single monolithic preview renderer, which would duplicate runtime layout and hide integration defects.

Shipping approval and development visibility remain separate. Debug builds may activate candidate textures and candidate content. Release builds may activate only hash-bound, approved shipping textures. A candidate being playable never changes its registry approval status.

## Content model

A development-only candidate content pack supplies playable definitions for all candidate weapons, items, and upgrades that do not already have a canonical gameplay definition.

- Each of the ten candidate firearms receives a stable content ID, display name, original CSGO-community flavor, price, weapon class, damage, cooldown, range, projectile speed, knockback, feedback profile, and static asset ID.
- `warmup_shiv` and `service_pistol` keep their approved definitions and bindings.
- All 30 items receive stable definitions and icon IDs. Existing canonical items remain unchanged. Every new definition translates the literal numeric effects already declared for that registry unit into runtime stat modifiers; the integration invents no additional effects.
- All six upgrades receive stable definitions and icon IDs by translating their literal registry effects with the same rule.
- Shop, weapon selection, and upgrade selection draw from the expanded definitions in debug builds. Release builds do not install candidate-only definitions.

The content pack is deterministic: no display name, stat, price, or binding is inferred from a texture filename at runtime.

## Weapon presentation and combat feedback

Weapons occupy up to six evenly spaced sockets on a 72-pixel ring around Niko. Every instance independently selects the nearest valid target, rotates toward it, and automatically attacks. It owns its own texture, pivot, muzzle anchor, recoil transform, cooldown, projectile sequence, and feedback sequence.

Large pixel silhouettes take priority over firearm realism. Candidate textures render at nearest-neighbor integer scale. A weapon that becomes ambiguous at gameplay size is revised in the next candidate with fewer thin barrel pixels and larger color masses; runtime never smooths or downscales it to conceal the issue.

Shot feedback is emitted from the declared muzzle anchor. The feedback presenter supplies a short high-contrast muzzle flash, integer recoil, visible projectile, contact burst, damage event, death burst, and bounded integer camera impulse. This keeps the Brotato-like cause-and-effect chain readable without changing combat simulation order.

## Brotato-style combat HUD

`combat_hud_shell` is the structural 320×180 source and renders at exactly 4× nearest-neighbor scale for the 1280×720 reference viewport. It stays in a top-level `CanvasLayer` and never moves with camera impulses.

The information hierarchy is fixed:

- top center: large remaining seconds, with `第 X 波` directly below;
- bottom left: health icon, current/max health, and a wide color-coded health bar;
- bottom center: level plus current experience progress;
- bottom right: material icon and current material count;
- lower edge: six compact weapon slots using weapon icons and tier frames;
- right edge: compact acquired-item icons, capped visually and summarized with a count when the list exceeds the visible strip;
- control hints appear during wave one and disappear permanently after the first non-zero movement input or after four elapsed combat seconds, whichever occurs first.

The shell, card frame, icons, numbers, and bars use high-contrast off-white, charcoal, orange, red, green, and CSGO utility accents. Text remains readable over every world tile through dark panels and one-pixel integer outlines. The HUD does not show decorative prose during combat.

HUD data comes only from canonical session signals. `CombatWorld` adds `hud_snapshot_changed(snapshot: GogoCombatHudSnapshot)` while retaining the existing `hud_changed` signal for compatibility. The typed snapshot contains health, maximum health, seconds, wave, level, experience, next-level requirement, materials, weapon IDs, and item IDs. `CombatScreen` listens to the typed signal and never reads private world fields every frame.

## Menus and cards

All non-combat screens share the candidate `menu_background` with a dark readability veil. The main menu uses `gogobro_wordmark`; selection screens use `zone_thumbnail` and `difficulty_badge_kit`; centered content uses `nine_slice_panel`; buttons use `four_state_button`; weapon, item, and upgrade entries use `card_and_rarity_frame_kit`.

Cards keep one consistent hierarchy: 64-pixel nearest-neighbor icon, name, rarity/tier accent, concise stat line, and price or selection state. The existing text fallback remains when a release snapshot lacks a texture.

## World rendering

The combat world receives a dedicated static presentation layer behind actors and a prop layer below combat feedback.

- `community_server_floor` tiles the arena at its native 64-pixel grid.
- `arena_boundary_border` repeats along all four arena edges without scaling blur.
- `community_server_decor_pack`, `hazard_beacon`, `supply_crate`, and `weapon_rack` populate deterministic, collision-free visual prop sockets outside the player's initial clear radius.
- `spawn_marker` appears briefly at an enemy spawn position before activation.
- `experience_pickup`, `supply_pickup`, and `medical_pickup` represent their corresponding world drops.
- `site_hold_turret` is rendered by `GogoStructureActor`. Debug preview sessions place one neutral, collision-free turret at a deterministic upper-right prop socket; release sessions create it only from an owned structure definition.

Prop placement is seed-driven so screenshots and regressions are reproducible. Decorative assets do not alter navigation or damage unless a separate gameplay definition explicitly owns that behavior.

## Approved helmet integration

`smoke_shell_helmet` candidate 002 is installed from its approved, hash-recorded icon and appearance artifacts. The icon binds to its item definition. Its rigid appearance uses Niko's `head_shell` socket, the approved pivot, the existing eight-frame attachment rig, and depth 40. Installation must preserve the approved source hashes and may not silently regenerate the art.

## Error handling and fallbacks

- A malformed candidate manifest rejects the whole development overlay and leaves the approved shipping snapshot active.
- A missing global UI texture falls back to current flat panels and text.
- A missing content icon produces a text-only card, never an invisible selection.
- A missing world prop skips only that decorative prop; missing floor or HUD shell records a development QA failure.
- Invalid weapon pivot or muzzle metadata prevents that candidate weapon from entering the playable pack.
- Candidate states remain `preview_ready`; release readiness counts only approved `ready` states.

## Coverage contract

Every one of the 70 registry units must have at least one tested real consumer:

- weapons: selection/shop card plus runtime weapon or melee instance;
- items: shop/inventory card, and helmet appearance where applicable;
- upgrades: upgrade card;
- world: combat-world node or tile layer;
- UI/brand: an actual menu or HUD control;
- projectile/hit kit: live projectile/contact feedback.

The coverage report records asset ID, resolved role/selector, consuming scene/node, texture size, integer display scale, and whether the source is approved shipping or development preview. An unresolved unit is a hard failure even if a review sheet contains the image.

## Verification

Verification is proportional to the full scope:

1. Unit tests validate 70 registry units, exact category counts, content bindings, global bindings, pivots, muzzle anchors, nearest filtering, and debug/release separation.
2. Content tests validate one Niko character, 12 weapon definitions, 30 item definitions, and 6 upgrade definitions in the development preview catalog without exposing candidate definitions in release mode.
3. Combat tests validate six independent orbit weapons, per-weapon firing origin, recoil, projectile contact, death feedback, HUD snapshot values, and deterministic world-prop placement.
4. UI tests instantiate the real main menu, selection, shop, upgrade, and combat HUD consumers and assert their resolved textures and fallback behavior.
5. A 1280×720 menu capture proves background, wordmark, panel, button, card, zone, and difficulty consumers.
6. A 1280×720 combat capture proves tiled floor, border, props, pickups, Niko-only character scope, six orbit weapons, HUD metrics, firing, and impact feedback.
7. A machine-readable coverage report proves all 70 assets have real consumers. Human review checks readability at actual size; it does not upgrade candidate approval.

## Completion criteria

This work is complete only when all 70 registry units resolve through real consumers, the two reference captures pass actual-size review, the complete relevant test suite passes without parse errors, release builds still reject candidate-only assets, and Niko remains the sole character definition. Partial candidate visibility or a gallery-only result is not completion.
