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

The development candidate manifest provides 61 current candidates. Nine additional registry units already have active shipping bindings: `warmup_shiv`, `service_pistol`, `projectile_hit_kit`, `ballistic_liner`, `smoke_shell_helmet`, `one_more_round`, `hud_icon_kit`, `control_icon_kit`, and `difficulty_badge_kit`. Full coverage therefore requires candidate integration while preserving the separate approval status of those nine installed shipping assets.

Character scope is fixed to one definition: `character.niko:character/niko`. This work does not generate or restore another character.

## Chosen architecture

Use real consumer integration. Assets are resolved through `GogoStaticAssetSnapshot`, then consumed by content definitions, UI screens, or combat-world nodes. A gallery can be generated for QA, but it is never accepted as proof that an asset is integrated.

Two rejected alternatives are:

- a review-only gallery, which is fast but does not prove gameplay fit;
- a single monolithic preview renderer, which would duplicate runtime layout and hide integration defects.

Shipping approval and development visibility remain separate. Debug builds may activate candidate textures and candidate content. Release builds may activate only hash-bound, approved shipping textures. A candidate being playable never changes its registry approval status.

## Content model

A development-only candidate content pack supplies playable definitions for all candidate weapons, items, and upgrades that do not already have a canonical gameplay definition.

- Each of the ten candidate weapon slots receives a stable content ID, display name, original CSGO-community flavor, price, weapon class, damage, cooldown, range, projectile speed, knockback, feedback profile, and static asset ID.
- The internal asset/content IDs of all 12 weapon slots remain stable for saves and bindings. Visible names, melee/ranged mode, and combat tuning may change when required to make the slot faithfully play like its mapped CS archetype.
- `warmup_shiv` and `service_pistol` keep their currently approved shipping definitions and bindings until replacement candidates receive separate explicit approval. Debug preview may show their new candidates without overwriting shipping art.
- All 30 items receive stable definitions and icon IDs. Existing canonical items remain unchanged. Every new definition translates the literal numeric effects already declared for that registry unit into runtime stat modifiers; the integration invents no additional effects.
- All six upgrades receive stable definitions and icon IDs by translating their literal registry effects with the same rule.
- Shop, weapon selection, and upgrade selection draw from the expanded definitions in debug builds. Release builds do not install candidate-only definitions.

The content pack is deterministic: no display name, stat, price, or binding is inferred from a texture filename at runtime.

## Physical-item art contract

All 30 item entries remain mechanically stable: their internal IDs, stat modifiers, rarity, price, stack limits, and appearance sockets do not change during the art pass. An item icon must depict one concrete object that could be held, worn, stored, or placed on a table. Footprints, arrows, speed lines, floating stat symbols, isolated crosshairs, and other abstract status marks are not valid item subjects.

When an existing display name or description describes an abstract event rather than an object, localization may be renamed to the concrete object shown by the replacement icon. The internal ID and gameplay effect remain unchanged. For example, movement speed is represented by tactical runners or insoles rather than footprints, and a missed-shot concept is represented by a cracked scope lens or damaged range token rather than a floating miss marker.

Every replacement follows one shared generation contract:

- reference Niko's mother art plus the approved crisp item batch for palette, outline weight, and pixel density;
- use a perfectly solid `#FF00FF` raw background with no shadows, texture, glow, gradients, or subject-colored spill in the background;
- show one centered three-quarter-view physical object with a large, immediately readable silhouette and a four-pixel safe margin;
- use chunky pixel clusters, hard edges, no antialiasing, no photographic micro-detail, and a restrained charcoal/orange/off-white/utility-color palette;
- prefer an exaggerated CSGO-community prop or joke over a realistic miniature when realism becomes unreadable at 64 pixels;
- chroma-key only after generation, then export a transparent 64×64 PNG with nearest-neighbor sampling and strict edge, alpha, palette, and actual-size QC.

The magenta background is a generation and cleanup tool only. It is never visible in the shipped or development-preview game texture. Candidate output remains development-only until separately approved; a redraw does not inherit approval from the asset it replaces.

## CS weapon archetype contract

All 12 weapon visuals are regenerated through the same solid-magenta, chunky-pixel pipeline as the physical items. A weapon is not accepted as a generic rifle, generic pistol, or invented sci-fi silhouette: its defining CS archetype must be readable at actual gameplay size before the name is shown.

The stable slot mapping is:

| Internal asset ID | Visible archetype | Required silhouette cues |
| --- | --- | --- |
| `warmup_shiv` | 蝴蝶刀 / Butterfly Knife | split handles, exposed pivot, short straight blade |
| `community_tapper` | 爪子刀 / Karambit | finger ring, strongly curved claw blade |
| `wood_stock_assault_rifle` | AK-47 | wood stock/handguard, curved magazine, long gas tube |
| `heavy_bolt_sniper` | AWP | long heavy barrel, large scope, green chassis mass |
| `suppressed_carbine` | M4A1-S | straight magazine, AR receiver, long suppressor |
| `suppressed_tactical_pistol` | USP-S | angular slide, slim grip, prominent suppressor |
| `heavy_hand_cannon` | Desert Eagle | oversized squared slide, thick barrel and grip |
| `service_pistol` | Glock-18 | compact squared slide, short barrel, simple grip angle |
| `box_submachine_gun` | MAC-10 | boxy receiver, short barrel, compact magazine mass |
| `compact_submachine_gun` | MP9 | compact polymer body, top rail, skeleton stock cue |
| `bullpup_pdw` | P90 | horizontal top magazine, rounded bullpup body |
| `folding_stock_submachine_gun` | UMP-45 | long box magazine, blocky receiver, folding stock |

This mapping references real silhouette families, not Valve textures or commercial skins. Surface treatment remains original GOGOBRO: charcoal metal, warm orange accents, muted utility green, off-white highlights, and small community-joke stickers that do not obscure the weapon class.

Firearms are authored right-facing in a 96×64 gameplay texture; knives use a 64×64 gameplay texture. The occupied silhouette must use most of the safe region, barrels and suppressors must remain several pixels thick after final export, and small controls are collapsed into larger color blocks. Every weapon declares an integer pivot plus muzzle or contact anchor. Runtime rotation/mirroring happens around that pivot with nearest-neighbor rendering.

Combat behavior follows the visible archetype: knives use short-range contact, SMGs use rapid low-recoil fire, pistols use compact deliberate fire, AK/M4 use readable rifle recoil, and AWP uses a slow high-impact shot. Critical, penetration, and explosion feedback must arise from canonical mechanics. A gun is not given an implausible explosive identity merely to make a screenshot; explosive feedback comes from a grenade, explosive prop, or another explicitly authored CS-grounded source.

## Weapon presentation and combat feedback

Weapons occupy up to six evenly spaced sockets on a 72-pixel ring around Niko. Every instance independently selects the nearest valid target, rotates toward it, and automatically attacks. It owns its own texture, pivot, muzzle anchor, recoil transform, cooldown, projectile sequence, and feedback sequence.

Large pixel silhouettes take priority over firearm realism. Candidate textures render at nearest-neighbor integer scale. A weapon that becomes ambiguous at gameplay size is revised in the next candidate with fewer thin barrel pixels and larger color masses; runtime never smooths or downscales it to conceal the issue.

Shot feedback is emitted from the declared muzzle anchor. The feedback presenter supplies a short high-contrast muzzle flash, integer recoil, visible projectile, contact burst, damage event, death burst, and bounded integer camera impulse. This keeps the Brotato-like cause-and-effect chain readable without changing combat simulation order.

## Brotato-style combat HUD

The HUD stays in a top-level `CanvasLayer` and never moves with camera impulses. It uses native 1280×720 text and controls. Pixel textures may use exact nearest-neighbor integer scaling, but the complete interface is not rendered as a low-resolution canvas.

The information hierarchy is fixed:

- top center: large remaining seconds, with `第 X 波` directly below;
- bottom left: health icon, current/max health, and a wide color-coded health bar;
- bottom center: level plus current experience progress;
- bottom right: material icon and current material count;
- lower edge: six compact weapon slots using weapon icons and one rarity accent per slot;
- right edge: compact acquired-item icons without an enclosing ornamental column, capped visually and summarized with a count when the list exceeds the visible strip;
- control hints appear during wave one and disappear permanently after the first non-zero movement input or after four elapsed combat seconds, whichever occurs first.

The shell, card frame, icons, numbers, and bars use high-contrast off-white, charcoal, orange, red, green, and CSGO utility accents. Text remains readable over every world tile through local dark backplates or one-pixel integer outlines. The HUD does not show decorative prose during combat.

The combat HUD has no full-screen ornamental frame. Health, experience, materials, timer, weapon cells, and item cells may each have one local backing shape or one outline, never both an outer container and nested framed children. World visibility and combat readability take priority over decorative chrome.

HUD data comes only from canonical session signals. `CombatWorld` adds `hud_snapshot_changed(snapshot: GogoCombatHudSnapshot)` while retaining the existing `hud_changed` signal for compatibility. The typed snapshot contains health, maximum health, seconds, wave, level, experience, next-level requirement, materials, weapon IDs, and item IDs. `CombatScreen` listens to the typed signal and never reads private world fields every frame.

## Interface reference boundary and border budget

Brotato is the structural reference for information hierarchy, screen composition, card density, state flow, and input affordances. GOGOBRO does not copy Brotato textures, character art, fonts, icons, logos, wording, or source files. All visible art remains original pixel CSGO-community work.

All screens share a strict border budget:

- no decorative frame around the entire viewport;
- at most one outline around a card, button, slot, or stats surface;
- no bordered panel containing another bordered panel unless the inner border is the single rarity cue around an icon;
- prefer spacing, alignment, flat dark fills, typography, and small orange/rarity accents to establish hierarchy;
- separators are one pixel or a color change, not another nine-slice box;
- focused and selected states change fill, value color, or one accent edge instead of adding another frame.

`nine_slice_panel` remains available for one principal modal surface, but it is not applied recursively to screen, section, row, card, and button. `four_state_button` supplies interaction states; `card_and_rarity_frame_kit` supplies the single card/rarity outline. The existing text fallback remains when a release snapshot lacks a texture.

Cards keep one consistent hierarchy: a readable 64-pixel nearest-neighbor physical-object icon, name, rarity accent, concise localized stat lines, and price or selection state. Positive and negative modifiers use distinct colors. Raw internal stat keys are never shown to the player.

## Brotato-structured non-combat screens

The generic centered vertical menu is not used for the three build screens below. Each screen has a dedicated 1280×720 composition while sharing card, typography, button-state, stat-row, and inventory-slot components.

### Shop

- top band: current wave, materials, and a prominent reroll action with its current cost;
- central-left area: exactly four offer cards in one row, each with icon, name, rarity, localized effects, price, buy affordance, and its own lock state;
- right area: current player stat list, separated by spacing and value color rather than nested boxes;
- bottom area: six weapon slots followed by a compact acquired-item inventory; weapon sell/combine actions are attached to the relevant slot rather than global prose buttons;
- lower-right action: one clear continue-to-next-wave button and the next-wave warning/state.

### Upgrade reward

- left area: the same current-player stat list used by the shop;
- central/right area: exactly four upgrade choices per reward step, each showing physical or body-part-themed icon, rarity, localized effect, and a choose action;
- bottom action: reroll with its material cost;
- top status: remaining reward choices and current materials;
- choosing one card updates canonical state and either presents the next pending reward or routes to the shop.

### Character selection

- top-left: back action; top-center: character-selection title;
- central area: a roster-grid surface using Brotato-like compact selection cells;
- only Niko is a real selectable character and the only character artwork in the project;
- the right detail area shows Niko's larger preview, name, strengths/constraints, and starting-flow summary;
- no duplicated Niko tiles, invented characters, fake character portraits, or restored placeholders are used to fill the grid.

Weapon and difficulty selection continue the same light-border system and card language so the route reads as one flow rather than unrelated pages.

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
4. Item-art tests/audits enumerate all 30 items and prove every icon maps to a named physical subject, uses the shared magenta-background prompt contract, exports transparent 64×64, and passes actual-size readability review.
5. Weapon-art tests/audits enumerate all 12 slots, prove the fixed CS archetype mapping and required silhouette cues, validate pivot/anchor metadata, and reject thin or ambiguous actual-size renders.
6. UI tests instantiate the real main menu, character selection, weapon selection, difficulty selection, shop, upgrade reward, and combat HUD consumers and assert their resolved textures, card counts, information order, border-budget invariants, and fallback behavior.
7. Separate 1280×720 route captures prove the actual main menu, character selection, weapon selection, difficulty selection, shop, and upgrade reward layouts. A staged collage or manually assembled evidence panel is not accepted.
8. A 1280×720 combat capture proves tiled floor, border, props, pickups, Niko-only character scope, six orbit weapons, HUD metrics, firing, and naturally caused critical, pierce, and explosion feedback.
9. A machine-readable coverage report proves all 70 assets have real consumers. Human review checks readability and excessive-border regressions at actual size; it does not upgrade candidate approval.

## Local comparative playtest

The local installed copy of Brotato is an authorized read-only comparison target. Visual and gameplay acceptance does not rely only on screenshots or the user's per-asset approval. A fresh review subagent launches and plays Brotato, then launches and plays the current GOGOBRO build under comparable early-wave conditions. The reviewer records direct observations for weapon orbit spacing, target acquisition, automatic-fire cadence, recoil, projectile readability, hit confirmation, enemy-death response, HUD scanning order, shop density, reward-choice clarity, and border restraint.

The comparison is behavioral and structural. No Brotato executable, texture, font, audio, data file, screenshot crop, or other proprietary payload is copied into the repository. Reviewers may capture temporary full-window evidence for comparison, but only original GOGOBRO artifacts and written observations enter version control.

Per-asset approval is not requested from the user during this production pass. Generation, mechanical QC, actual-size review, runtime integration, comparative playtest, and repair are owned by the agent team. A candidate remains development-only unless the user separately grants shipping approval; passing internal review does not change that legal/runtime state.

## Completion criteria

This work is complete only when all 70 registry units resolve through real consumers; all item icons are concrete physical objects; all 12 weapons match the fixed CS archetype map; both groups use the shared magenta-background style contract; combat HUD, shop, upgrade reward, and Niko-only character selection pass the Brotato-structured layout and border-budget checks; every required real-route 1280×720 capture passes actual-size review; an independent subagent has played both the locally installed Brotato and the current GOGOBRO build and accepted the direct comparison; the complete relevant test suite passes without errors or leaks; release builds still reject candidate-only assets; and Niko remains the sole character definition. Partial candidate visibility, generic weapon silhouettes, abstract item glyphs, excessive nested frames, screenshot-only comparison, or gallery-only evidence are not completion.
