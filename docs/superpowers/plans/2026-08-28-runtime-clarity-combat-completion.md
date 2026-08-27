# Runtime Clarity and Combat Completion Implementation Plan

> **Spec:** `docs/superpowers/specs/2026-08-28-runtime-clarity-combat-completion-design.md`

**Goal:** Finish the authored visible surfaces and combat-feedback loop, then promote the accepted static set so a native release build is as complete and clear as the development preview.

**Architecture:** Keep the existing content IDs, deterministic combat event ordering, and static-asset snapshot boundary. Enemy art is content-owned actor art (like Niko), while the established 70-unit static registry remains the weapon/item/upgrade/world/UI/projectile contract. Combat feedback is event-driven; local hitstop never changes `Engine.time_scale` or `SceneTree.paused`; reward drops use the existing reservation ledger for exact-once application.

**Tech stack:** Godot 4.7 / GDScript, Python 3 asset tools, built-in image generation, GUT tests, native Windows/OpenGL capture.

## Global constraints

- Actual-size 1280×720 readability is the visual authority. Fine pixel detail is allowed; chunky pixels and large flat blocks are not mandatory.
- Preserve the current dark graphite, warm amber/orange, restrained CS-material, crisp-outline project style.
- Generated raster art must originate from the built-in image generation tool, use the Generate2dsprite magenta-cleanup workflow, and be inspected after processing.
- Niko remains the only selectable player character. Do not add playable characters.
- Preserve existing gameplay IDs and values except the contradictory 420-range Karambit-like melee range, which may be corrected.
- Do not copy or extract Brotato/CS assets or audio. Do not launch Brotato or touch its save files.
- Keep all combat rewards exact-once and deterministic. Preserve existing public signal signatures unless this plan explicitly introduces a new signal.
- Never modify `Engine.time_scale` for feedback and never use `SceneTree.paused` for hitstop.
- Keep the low-border Brotato-structured UI; do not add decorative frame nesting.
- Every implementation task must begin with a failing focused test, make it pass, run the relevant regression set, self-review, and commit.

### Task 1: Generate and integrate three readable enemy sprites

**Files:**

- Create: `game/assets/enemies/drifter.png`
- Create: `game/assets/enemies/spark.png`
- Create: `game/assets/enemies/rammer.png`
- Create: `game/assets/enemies/provenance/drifter/prompt-used.txt`
- Create: `game/assets/enemies/provenance/drifter/pipeline-meta.json`
- Create: `game/assets/enemies/provenance/spark/prompt-used.txt`
- Create: `game/assets/enemies/provenance/spark/pipeline-meta.json`
- Create: `game/assets/enemies/provenance/rammer/prompt-used.txt`
- Create: `game/assets/enemies/provenance/rammer/pipeline-meta.json`
- Modify: `game/content/enemy_definition.gd`
- Modify: `game/content/validation_content_factory.gd`
- Modify: `game/gameplay/actors/enemy_actor.gd`
- Create: `tests/unit/test_enemy_actor_visual.gd`
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`

**Requirements:**

1. Use built-in image generation once per enemy with the approved weapon/item/HUD imagery as style reference. Use `pixel_inspired` / `project-native`, a fully flat `#FF00FF` background, no text, no border, no shadow plate, and a centered 3/4 top-down subject.
2. Produce three role-readable silhouettes: rust-red compact drifter/chaser, olive-lime flash-core spark/shooter, and orange reinforced wedge rammer/charger. They must remain distinguishable in greyscale and not rely only on hue.
3. Postprocess each raw result with `generate2dsprite.py` as a single static asset, largest component, centered alignment, strict edge QC. Deliver a 64×64 transparent PNG at 1:1 runtime scale with the opaque subject occupying approximately 42–52 pixels and no magenta residue.
4. Add `visual_texture: Texture2D` to `GogoEnemyDefinition`; bind the three textures in `ValidationContentFactory` without changing enemy IDs, roles, health, speed, damage, or rewards.
5. `GogoEnemyActor` creates a nearest-filtered `Sprite2D` when `definition.visual_texture` exists and only draws the old role-colored circle fallback when the authored texture is unavailable. Preserve the 14-pixel collision radius and all combat behavior.
6. The integration capture must deliberately place one of each role in view and assert all three have authored sprites and no fallback circle.

**Tests:**

- The new unit test proves texture assignment, nearest filtering, stable centered pivot, fallback behavior, and unchanged collision radius.
- Run the focused enemy test and the combat visual smoke at 1280×720.

### Task 2: Apply the unified four-state action treatment to shop and upgrade commands

**Files:**

- Modify: `game/ui/shop_screen.gd`
- Modify: `game/ui/upgrade_screen.gd`
- Modify: `tests/unit/test_static_menu_consumers.gd`
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`

**Requirements:**

1. Route `ShopScreen._shop_button` through inherited `configure_action_button` so Reroll, Lock/Unlock, Buy command buttons where applicable, and Continue use normal/hover/pressed/disabled textures from the same snapshot.
2. Route `UpgradeScreen` reroll through the same helper.
3. Preserve each screen's exact layout size, font size, focus metadata, callback uniqueness, disabled logic, and focus restoration.
4. Do not replace rarity-card skins with command-button textures and do not add borders.

**Tests:**

- Assert all command buttons expose distinct state styleboxes backed by the expected static selectors, including disabled state.
- Run the menu route smoke and existing shop focus tests.

### Task 3: Add local hitstop and stronger player-hit feedback

**Files:**

- Modify: `game/gameplay/world/combat_world.gd`
- Modify: `game/gameplay/actors/player_actor.gd`
- Modify: `game/gameplay/actors/enemy_actor.gd`
- Modify: `game/gameplay/weapons/weapon_instance.gd`
- Modify: `game/gameplay/weapons/projectile.gd`
- Modify: `game/gameplay/feedback/combat_feedback_presenter.gd`
- Modify: `game/content/assets/gogobro_static_preview_content_v1.json`
- Modify: `tests/unit/test_combat_feedback_presenter.gd`
- Modify: `tests/unit/test_combat_event_publication.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`
- Modify: `tests/unit/test_static_preview_content_factory.gd`

**Requirements:**

1. Add `CombatWorld.request_local_hitstop(seconds)` and `is_combat_simulation_frozen()`. Clamp requests to 0.025–0.060 seconds, coalesce by maximum, and expose debug remaining time for tests.
2. Player, enemy, weapon, and projectile physics callbacks return before simulation mutation while frozen. `CombatWorld`, feedback effects, camera, HUD, wave timer, and pause input continue processing.
3. Contact durations: normal 0.025 seconds, rifle/heavy contact 0.035 seconds, critical 0.045 seconds, explosion 0.060 seconds. A real player hit requests 0.040 seconds. Never mutate `Engine.time_scale` or tree pause state.
4. Add a monotonic `damage_taken` signal to the player that fires after a non-dodged, non-invulnerable health reduction. Include integer world position, final damage, remaining health, lethal flag, and sequence. Existing `health_changed` and `died` behavior remains compatible.
5. Add a red/white, short player-hit feedback slot and camera impulse, using the same bounded presenter pool.
6. Correct only `community_tapper` attack range from 420 to 88 while preserving its internal ID and other values.

**Tests:**

- Prove all four simulation actor types freeze, the wave/HUD timer still advances, requests coalesce/cap, and engine/tree time state never changes.
- Prove dodges/invulnerability do not publish hit feedback, real damage does, sequence is monotonic, and lethal ordering remains valid.
- Prove `community_tapper` is melee with range 88.

### Task 4: Replace decorative reward props with exact-once magnetic pickups

**Files:**

- Create: `game/gameplay/world/combat_pickup.gd`
- Modify: `game/gameplay/world/combat_world.gd`
- Modify: `game/gameplay/actors/enemy_actor.gd`
- Modify: `game/gameplay/world/static_world_presenter.gd`
- Modify: `tests/unit/test_static_world_presenter.gd`
- Create: `tests/unit/test_combat_pickup.gd`
- Modify: `tests/unit/test_reward_ledger.gd`
- Modify: `tests/unit/test_combat_event_publication.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`

**Requirements:**

1. Add a dedicated `PickupLayer` and a `GogoCombatPickup` state machine: `DROPPED -> MAGNETIZING -> COLLECTED`.
2. Enemy death still reserves XP/material rewards through the existing ledger, but no longer applies them immediately. Spawn one pickup per reserved non-zero reward, resolving `experience_pickup` or `supply_pickup` from the active static snapshot.
3. Give each drop a deterministic small integer pop offset based on enemy/runtime IDs. Magnetize inside the player's current `pickup_range`, accelerate smoothly toward Niko, and collect at a fixed contact radius.
4. On collection, transition state before calling `GameSession.apply_reserved_reward`; only an `APPLIED` result publishes `pickup_collected` and collection feedback. Duplicate callbacks cannot grant twice.
5. Before wave completion, collect all live pickups in stable runtime-ID order, then compute/emit the final HUD snapshot and finish the wave.
6. Remove decorative experience and supply pickups from `StaticWorldPresenter`; keep the medical pickup as non-interactive scenery until healing-drop mechanics exist. Dynamic pickup creation becomes the real consumer evidence for XP/material assets.
7. Missing visual handles must not block reward collection.

**Tests:**

- Cover reserve-without-apply, deterministic spawn, magnet motion, exact-once collection, missing-texture fallback, duplicate attempts, and stable wave-end auto-collection.
- Update event-order and coverage expectations so real dynamic pickup consumers replace decorative evidence.

### Task 5: Add original pooled combat audio and route every combat event

**Files:**

- Create: `tools/assets/build_combat_sfx_v1.py`
- Create: `game/assets/audio/combat/rapid_shot.wav`
- Create: `game/assets/audio/combat/rifle_shot.wav`
- Create: `game/assets/audio/combat/heavy_shot.wav`
- Create: `game/assets/audio/combat/suppressed_shot.wav`
- Create: `game/assets/audio/combat/impact_normal.wav`
- Create: `game/assets/audio/combat/impact_critical.wav`
- Create: `game/assets/audio/combat/impact_explosion.wav`
- Create: `game/assets/audio/combat/enemy_down.wav`
- Create: `game/assets/audio/combat/player_hit.wav`
- Create: `game/assets/audio/combat/pickup.wav`
- Modify: `game/platform/audio_service.gd`
- Create: `game/gameplay/feedback/combat_audio_presenter.gd`
- Modify: `game/ui/combat_screen.gd`
- Create: `tests/unit/test_audio_service.gd`
- Create: `tests/unit/test_combat_audio_presenter.gd`
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`

**Requirements:**

1. The builder deterministically writes original mono 16-bit PCM WAV files at 44.1 kHz. Use synthesis/noise envelopes authored in code; no external sample input. Each clip is shorter than 350 ms, peak-safe, starts/ends near zero, and has a reproducible SHA-256 report.
2. `GogoAudioService` uses 12 SFX voices on the `SFX` bus and keeps music on `Music`. `play_effect` remains backward compatible and accepts optional volume/pitch. Prefer idle voices; when saturated, steal the oldest deterministically.
3. `GogoCombatAudioPresenter` maps rapid/rifle/heavy/suppressed shots, normal/critical/pierce/explosion contacts, enemy death, player hit, and pickup collection. Suppressed shots are at least 8 dB quieter than rifle shots.
4. `CombatScreen` is the composition root: inject the app audio service, route world events once, and rely on scene teardown for disconnection. Do not add an AppKernel dependency to the combat model.
5. Fast automatic weapons must not truncate the previous voice.

**Tests:**

- Validate WAV headers/durations/peak bounds, pool size/buses, idle allocation, deterministic stealing, backward compatibility, event mapping, suppressed volume, and same-tick multi-shot voice separation.
- Integration smoke records all event classes through a test-visible debug ledger; no physical speaker assertion is required.

### Task 6: Promote the accepted static set and make content release-visible

**Files:**

- Modify: `tools/build_static_shipping_install.py`
- Create: `game/content/assets/gogobro_static_shipping_approval_2026-08-28.json`
- Modify: `game/content/assets/gogobro_static_assets_v1.json`
- Modify: `game/content/assets/gogobro_static_runtime_bindings_v1.json`
- Copy accepted media under: `game/assets/gogobro_static/**`
- Modify: `game/content/validation_content_factory.gd`
- Modify: `game/content/assets/gogobro_static_preview_content_factory.gd`
- Modify: `game/app/app_kernel.gd`
- Modify: `tests/unit/test_static_asset_registry.gd`
- Modify: `tests/unit/test_static_asset_runtime_service.gd`
- Modify: `tests/unit/test_static_preview_content_factory.gd`
- Modify: `tests/integration/static_shipping_runtime_visual_v1_smoke.gd`

**Requirements:**

1. Extend the deterministic shipping builder to read the accepted candidate manifest, validate every source hash/dimension/pivot/anchor/selector, copy the 65 accepted preview files and variants into each registry unit's shipping path, and union them with the five non-overlapped existing shipping units for exactly 70 active IDs.
2. For four overlapping IDs, the accepted newer preview media wins. Never delete the preview copies.
3. Recompute byte and decoded RGBA8 hashes, runtime bindings, canonical registry hash, and shipping manifest. All 70 units become `approved` + `requested_active` only after their evidence record and actual-size review hashes exist.
4. The approval record must bind the user-authorized completion scope, source spec, final review report, exact shipping texture/selector hashes, and generated runtime bindings. Do not reuse the old Wave033 evidence hashes for newly promoted media.
5. Preserve all static/content IDs. Make the 12 weapons, 30 items, and six upgrades load in both debug and release. Remove `candidate_preview` tags from release definitions while preserving their IDs for save compatibility. Keep the preview overlay debug-only for future candidates.
6. A release/headless snapshot must report 70 ready, 0 fallback, no quarantined assets, and `release_ready == true`.

**Tests:**

- Dry-run the builder, run it with `--apply`, dry-run again for idempotence, then run registry/runtime unit tests and the shipping visual smoke.
- Export or launch a non-debug/native release route and prove it does not use the candidate-preview overlay.

### Task 7: Produce actual-size evidence and run the final independent gate

**Files:**

- Create ignored evidence under: `reports/runtime-clarity-combat-completion/`
- Create: `.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/final-visual-audit.md`
- Create: `.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/final-runtime-playtest.md`
- Create: `docs/superpowers/reports/2026-08-28-runtime-clarity-combat-completion.md`

**Requirements:**

1. Run import validation, the complete Godot suite, relevant Python asset/tool tests, native Windows/OpenGL menu/combat routes, and the shipping/release smoke.
2. Capture 1280×720 menu, Niko selection, weapon selection, difficulty, combat, pause, upgrade, and shop screens. Combat must include all three enemy roles, projectiles, impact, death, and real moving/collected pickups.
3. Produce a deterministic 12-weapon evidence run or short frame sequence showing first shot, sustained fire/melee, contact, kill, and pickup. Review at actual display size.
4. Play GOGOBRO locally through selection, combat, upgrade, and shop. Do not launch Brotato; use the archived direct-comparison screenshots/report and explicitly record that safety substitution.
5. Independent review must evaluate runtime clarity, UI structure, weapon identity, enemy readability, combat feedback, release readiness, and regressions. No open Critical or Important issue may remain.
6. Record exact commands, counts, screenshot hashes, known pre-existing failures, and whether they are baseline-identical.

**Verification commands:**

```powershell
Godot_v4.7-stable_win64_console.exe --headless --editor --path . --import --quit
Godot_v4.7-stable_win64_console.exe --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
python tools/build_static_shipping_install.py
python -m pytest tools/tests
```

The exact native capture commands may reuse the existing smoke scripts, but every output path must be under this plan's report directory and each process must exit cleanly.
