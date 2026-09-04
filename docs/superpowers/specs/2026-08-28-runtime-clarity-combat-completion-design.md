# GOGOBRO Runtime Clarity and Combat Completion Design

**Date:** 2026-08-28
**Status:** Approved for autonomous execution by the user’s standing direction to complete the full asset set without per-asset approval pauses
**Build target:** Godot 4.7, native Windows, 1280×720 reference viewport

## Goal

Turn the current development-preview asset pass into a cohesive playable build whose static visuals, Brotato-structured UI, CS-inspired weapon identities, enemies, and combat feedback remain immediately readable at actual game size.

The visual target is **clarity in motion**, not a mandatory “chunky pixels and large flat color blocks” treatment. Fine pixel detail is allowed when it survives the real runtime scale. A technically pixel-perfect source that becomes a grey blur at 1280×720 fails; a more detailed pixel-inspired source that keeps a clean silhouette and readable contrast passes.

## Binding product decisions

1. **Actual-size readability is the art gate.** Review every asset in a real 1280×720 route at its runtime size, with nearest filtering and integer-aligned presentation. Enlarged contact sheets are supporting evidence only.
2. **Keep the established project-native language.** Preserve the dark graphite outline, restrained CS-like materials, amber/orange highlights, and the approved inventory-icon palette. Do not force 16-bit wording, heavy dithering, or oversized color blocks.
3. **Niko remains the sole selectable player character.** The three enemy roles receive non-playable creature/bot sprites; they do not expand the playable roster.
4. **CS identity is silhouette-first.** The 12 weapons keep their existing internal IDs and CS archetype mapping. At runtime, a long barrel, suppressor, magazine, stock, and knife curve must remain legible. Thin critical parts should normally render at least 2–3 pixels thick.
5. **Items remain concrete inventory objects.** The 30 item icons are the completed product surface. Worn overlays are not inferred for every item: only an explicitly integrated appearance is a runtime promise. This matches the Brotato-like inventory model and avoids claiming invisible 60-tuple appearance work as finished.
6. **Preserve gameplay values and IDs by default.** Only fix a value when it directly contradicts the represented archetype or breaks playability. The known Karambit-like `community_tapper` 420-range melee behavior is such a contradiction and may be corrected with a regression test.
7. **All generated art is original.** Brotato and CS are references for structure, readability, and archetype recognition. Do not copy their files, sound samples, or UI artwork.
8. **Do not launch Brotato during this completion pass.** Prior screenshots and the existing comparison report are the only reference evidence because the previous Steam launch escaped the isolated save path. Never mutate or restore Brotato saves without explicit user direction.

## Runtime readability contract

An asset passes only when all applicable checks pass:

- It is identifiable without zooming in the 1280×720 capture.
- Its dominant silhouette separates from the arena or card background.
- Important functional parts are not reduced to sub-pixel or one-pixel noise after runtime scaling.
- Texture filtering, atlas rect, pivot, and display size match the manifest exactly.
- No unintentional edge clipping, magenta residue, interpolation blur, or non-integer placement is visible.
- Effects use high-contrast cores and short-lived secondary detail; detail cannot obscure the target, projectile, or Niko.
- Six simultaneous weapons remain readable around Niko without collapsing into one ring of visual noise.

The gate deliberately does **not** require a minimum source-pixel block size, a fixed number of colors, or a retro/chunky aesthetic.

## Completion surfaces

### 1. Static asset shipping set

- Promote the accepted 70-ID union into the shipping root and shipping manifest.
- Preserve all asset IDs, content IDs, roles, selectors, pivots, anchors, display sizes, and existing save-facing IDs.
- The release snapshot must report 70 ready, 0 fallback, and `release_ready == true`.
- The content pack containing the 12 weapons, 30 items, and six upgrades must load in release builds as well as debug builds.
- Candidate-preview plumbing may remain for future work, but the shipped build cannot depend on it for the accepted set.

### 2. Enemy visual set

Replace the programmatic circles with three original, project-native static sprites:

- **Drifter / chaser:** rust-red compact scavenger bot or creature; round but not a featureless circle; clear forward face and feet/drive silhouette.
- **Spark / shooter:** olive-lime ranged drone/creature with a luminous flash-core and obvious emitter silhouette.
- **Rammer / charger:** orange armored wedge/boar-like bot with a broad reinforced front.

Each sprite is centered, transparent after chroma cleanup, uses a stable bottom/center pivot, reads at roughly 40–56 rendered pixels, and has a role-specific silhouette independent of color.

### 3. Brotato-structured UI consistency

- Reuse the same four-state button texture system for shop actions and upgrade reroll.
- Keep the current low-border layout. Do not add nested ornamental frames.
- Maintain keyboard/gamepad focus paths and disabled-state legibility.
- Preserve the existing main menu, Niko selection, weapon selection, difficulty, combat HUD, shop, upgrade, and pause structures.

### 4. Combat feel

Add original, event-driven feedback without changing deterministic damage ordering:

- A pooled audio service and original WAV set for rapid/rifle/heavy/suppressed shots, normal/critical/explosion impact, enemy death, player hit, and pickup.
- Suppressed shots are audibly quieter and shorter than unsuppressed shots.
- Local combat hitstop, never `Engine.time_scale`: approximately 25 ms normal, 35 ms rifle/heavy, 45 ms critical, and 60 ms explosion, capped and coalesced. HUD and pause input remain responsive.
- Physical XP/material drops spawn at enemy death, pop slightly, magnet toward Niko inside pickup range, apply the already-reserved reward exactly once on collection, and auto-collect before wave transition.
- Remove decorative pickup placement that visually claims collectibility but has no gameplay behavior.
- Player damage adds a camera impulse and audio cue in addition to the existing combined-character white flash.

### 5. Evidence

- Unit and integration tests cover all new interfaces and exact-once invariants.
- Native 1280×720 real-route captures cover menu, Niko selection, weapons, difficulty, combat, pause, upgrade, and shop.
- Combat evidence includes a deterministic 12-weapon run or frame sequence showing firing, hit, kill, and pickup states at actual size.
- An independent final reviewer judges the game, not enlarged source files, and reports Critical/Important/Minor findings.

## Explicit non-goals

- Recreating every Brotato image, font, sound, or layout measurement verbatim.
- Adding another playable character.
- Generating worn overlays for every inventory item when the runtime does not consume them.
- Rebalancing the full item/weapon economy.
- Copying proprietary CS or Brotato assets.
- Treating debug-only gallery construction as proof of player-visible completion.

## Completion definition

This pass is complete when the release build resolves the accepted 70-ID static set without preview fallback; all three enemies use authored sprites; all primary action buttons use the unified state treatment; the combat has audible profile distinction, local hitstop, exact-once collectible rewards, and player-hit feedback; the 12 weapon identities and all UI routes are clear in actual-size 1280×720 evidence; the complete relevant Godot and asset-tool suites pass; and independent review has no open Critical or Important finding.
