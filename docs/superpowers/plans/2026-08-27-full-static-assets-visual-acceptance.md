# Full Static Assets Visual Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce reproducible real-route evidence, eliminate runtime leaks and fake combat evidence, prove all 70 static assets have real consumers, and pass an independent hands-on comparison between locally installed Brotato and GOGOBRO.

**Architecture:** Integration tests drive real app routes in a non-headless 1280×720 viewport and capture one PNG per screen plus live combat. A machine report proves asset coverage and event provenance. A fresh review subagent receives only the approved spec, exact-size captures, contact sheets, and a fixed rubric; every hard failure or score below threshold becomes a concrete repair loop before completion.

**Tech Stack:** Godot 4.7, GdUnit4, Windows/OpenGL screenshot runner, JSON coverage reports, independent Codex subagent review.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

## Global Constraints

- A staged collage or manually inserted event is not acceptable evidence.
- Screenshot tests run non-headless and wait for two `RenderingServer.frame_post_draw` events.
- Combat evidence contains naturally published normal, critical, pierce, and skyline-grenade explosion events.
- Every process exits 0 with zero GdUnit orphans and zero renderer RID leaks.
- Coverage requires exactly 70/70 canonical units and real consumers.
- Visual acceptance is based on 100%-scale 1280×720 route captures and 100%-scale 64/96-pixel asset sheets.
- An independent reviewer must play both local games, score every rubric axis at least 4/5, and report no hard failure.
- The agent team owns the review and repair loop; do not pause for per-asset user approval.

## File structure

| File | Responsibility |
|---|---|
| `tests/integration/full_static_assets_menu_v1_smoke.gd` | Captures main menu, character, weapon, difficulty, shop, and upgrade routes. |
| `tests/integration/full_static_assets_combat_v1_smoke.gd` | Captures live six-weapon combat and natural event provenance. |
| `tests/unit/test_combat_runtime_correctness.gd` | Enforces complete object/RID cleanup, including spawn markers. |
| `game/content/assets/gogobro_static_coverage_audit.gd` | Produces exact real-consumer coverage result. |
| `tools/assets/build_static_visual_review_packet.py` | Builds exact-size weapon/item sheets and a review manifest without altering pixels. |
| `docs/qa/full-static-assets-visual-review.md` | Independent reviewer scores, hard failures, evidence paths, and required repairs. |

---

### Task 1: Make live combat evidence canonical and leak-free

**Files:**
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`
- Modify only at root cause: `game/gameplay/world/static_spawn_marker.gd`, `game/gameplay/world/combat_world.gd`, or `game/gameplay/weapons/weapon_instance.gd`

**Interfaces:**
- Produces report fields `shot_count`, `contact_count`, `impact_kinds_observed`, `impact_sources`, and `orphan_count`.
- `impact_sources.explosion` must equal `gogobro.preview:item/skyline_grenade`.

- [ ] **Step 1: Keep the existing failing combat reproduction and capture diagnostics**

Run:

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/integration/full_static_assets_combat_v1_smoke.gd"
```

Require diagnostics to print the six equipped IDs, shots, contacts, kinds, and event sources. Do not increase the frame budget before proving why an event is missing.

- [ ] **Step 2: Select six deterministic weapons and own the skyline grenade**

Equip AK-47, AWP, M4A1-S, Desert Eagle, P90, and UMP-45 by stable content ID rather than content-array order. Add `skyline_grenade` to canonical `player.item_ids`, give targets enough health for seven attacks, and assert the explosion source from the published event payload.

- [ ] **Step 3: Write and fix the spawn-marker orphan reproduction**

The test clears the world before marker completion, waits one process and one physics frame, and asserts no marker, timer, callback, enemy, or RID remains. Fix ownership at the lifecycle source; do not suppress the orphan detector.

- [ ] **Step 4: Run combat correctness and non-headless integration GREEN**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_runtime_correctness.gd -ReportDir reports/combat-cleanup
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -a res://tests/integration/full_static_assets_combat_v1_smoke.gd"
```

Expected: normal, critical, pierce, and canonical grenade explosion all appear naturally; zero orphans.

- [ ] **Step 5: Commit**

```powershell
git add tests/integration/full_static_assets_combat_v1_smoke.gd tests/unit/test_combat_runtime_correctness.gd game/gameplay/world/static_spawn_marker.gd game/gameplay/world/combat_world.gd game/gameplay/weapons/weapon_instance.gd
git commit -m "test: prove canonical live combat feedback without leaks"
```

### Task 2: Capture every required real route at 1280×720

**Files:**
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`
- Create at runtime: `user://full-static-assets-menu-v2/*.png`
- Create at runtime: `user://full-static-assets-combat-v2/combat-1280x720.png`

**Interfaces:**
- Produces separate files: `main-menu`, `character-select`, `weapon-select`, `difficulty-select`, `shop`, `upgrade-reward`, and `combat`, each suffixed `1280x720.png`.

- [ ] **Step 1: Add exact route and image assertions**

```gdscript
func _save_route_capture(viewport: SubViewport, route_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert_object(image).is_not_null()
	assert_vec2i(image.get_size()).is_equal(Vector2i(1280, 720))
	assert_int(image.save_png("%s/%s-1280x720.png" % [OUTPUT_DIR, route_name])).is_equal(OK)
```

- [ ] **Step 2: Capture actual shop and upgrade state**

Create the canonical session states required to route through shop and upgrade reward, then capture those real screens. Do not instantiate a fake card grid or inject screenshot-only children.

- [ ] **Step 3: Run the Windows/OpenGL capture suite**

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd -a res://tests/integration/full_static_assets_combat_v1_smoke.gd"
```

Expected: seven exact-size PNGs and exit 0.

- [ ] **Step 4: Commit capture code**

```powershell
git add tests/integration/full_static_assets_menu_v1_smoke.gd tests/integration/full_static_assets_combat_v1_smoke.gd
git commit -m "test: capture every Brotato-structured game route"
```

### Task 3: Prove 70/70 real consumers and build the review packet

**Files:**
- Modify: `game/content/assets/gogobro_static_coverage_audit.gd`
- Modify: `tests/unit/test_static_asset_coverage_audit.gd`
- Create: `tools/assets/build_static_visual_review_packet.py`
- Create at runtime: `reports/full-static-assets-review/manifest.json`
- Create at runtime: `reports/full-static-assets-review/weapons-actual-size.png`
- Create at runtime: `reports/full-static-assets-review/items-actual-size.png`

**Interfaces:**
- Produces: coverage JSON with `expected_units == 70`, `covered_units == 70`, empty unresolved/failure lists, and `complete == true`.
- Review manifest records every screenshot/asset path, SHA-256, pixel size, stable ID, visible name, and source kind.

- [ ] **Step 1: Extend failing coverage assertions**

Require all twelve weapon IDs to have both card and runtime consumers, all thirty item IDs to have card/inventory consumers, every UI/world/projectile unit to have its designated real consumer, and no gallery/preview-sheet path to count.

- [ ] **Step 2: Run the focused test and record RED when any consumer is missing**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_asset_coverage_audit.gd -ReportDir reports/coverage-red
```

- [ ] **Step 3: Fix only missing real bindings and rerun GREEN**

Do not register evidence from tests directly. Observe each handle at the production node where its texture is assigned, then rerun until the report is exactly 70/70.

- [ ] **Step 4: Build pixel-preserving actual-size sheets**

The script places each PNG on a flat neutral checker with nearest-neighbor disabled because no scaling is allowed. Weapon sheet labels appear outside cells and never overlap the pixels; item sheet uses 64×64 cells. Hash every source and write the review manifest.

- [ ] **Step 5: Commit audit and packet builder**

```powershell
git add game/content/assets/gogobro_static_coverage_audit.gd tests/unit/test_static_asset_coverage_audit.gd tools/assets/build_static_visual_review_packet.py
git commit -m "test: package exact static asset visual evidence"
```

### Task 4: Independent two-game playtest and visual repair loop

**Files:**
- Create: `docs/qa/full-static-assets-visual-review.md`
- Modify only assets or UI files named by concrete reviewer findings.

**Interfaces:**
- Reviewer input: spec, seven screenshots, weapon/item actual-size sheets, manifest, locally installed Brotato, and the current GOGOBRO build.
- Reviewer output: one 1-5 score for each rubric axis plus exact file/asset findings.

- [ ] **Step 1: Resolve both executable paths and capture comparable starting conditions**

Locate the installed Brotato executable from local launchers/libraries without modifying its files. Build or launch the current GOGOBRO debug project. Record executable path, version text when visible, window size, input method, and the early-wave/loadout state used in each game. Use Niko with six weapons in GOGOBRO and an early Brotato run with multiple orbiting weapons when available.

- [ ] **Step 2: Dispatch a fresh playtest subagent with no implementation rationale**

Require the reviewer to actively play both games, inspect the exact-size evidence, and score:

1. CS archetype recognition at actual size.
2. Item physicality and cross-batch style consistency.
3. Brotato-like information hierarchy and density.
4. Border restraint and world visibility.
5. Combat cause/effect readability and six-weapon legibility.

Hard failures are: any unrecognizable weapon, abstract item, soft/blurred pixel art, detail that collapses at actual size, duplicate/fake character, nested decorative frames, missing required route, fake combat event, or clipped/unreadable primary text. Moderate crisp detail is not a failure merely because it is less chunky than Brotato.

- [ ] **Step 3: Record direct comparison observations and scores**

Create `docs/qa/full-static-assets-visual-review.md` with the two executable paths, comparable play states, direct observations for orbit spacing, targeting, cadence, recoil, projectile visibility, hit/death feedback, HUD scan order, shop/reward density, evidence hashes, per-axis scores, hard failures, and repair targets. Acceptance requires every score `>= 4` and zero hard failures.

- [ ] **Step 4: Repair each concrete failure and regenerate all affected evidence**

For art failures, create the next numbered inbox candidate and rerun mechanical plus actual-size review. For UI failures, add a focused failing assertion or pixel/geometry check before editing. Rebuild the complete review packet after every repair batch.

- [ ] **Step 5: Dispatch a different fresh subagent for final two-game re-review**

The second reviewer plays both games again, receives the repaired packet, and applies the same rubric. Completion is prohibited until it independently returns all five scores at least 4/5 with no hard failure.

- [ ] **Step 6: Commit accepted review evidence**

```powershell
git add docs/qa/full-static-assets-visual-review.md
git commit -m "docs: record independent static asset visual acceptance"
```

### Task 5: Full verification and completion audit

**Files:**
- Modify only when a verified failure identifies its root cause.

**Interfaces:**
- Produces: parse-clean import, all relevant tests green, zero orphans, seven captures, exact 70/70 report, and independent visual acceptance.

- [ ] **Step 1: Import and parse**

```powershell
E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe --editor --headless --path . --import --quit
```

- [ ] **Step 2: Run the complete unit suite**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit -ReportDir reports/final-unit
```

Expected: exit 0, no failures, no orphans, no RID leaks.

- [ ] **Step 3: Run all static-asset integration suites**

Run candidate preview, shipping runtime, pixel sampling, item appearance, button stability, menu capture, and combat capture. Every process must exit 0.

- [ ] **Step 4: Audit every explicit requirement against authoritative evidence**

Check: one Niko character; 12 recognizable CS weapons; 30 physical items; stable item numbers/IDs; low-border HUD/shop/upgrade/selection; natural combat feedback; seven 1280 captures; 70/70 consumers; debug/release separation; zero errors/leaks; hands-on two-game review threshold.

- [ ] **Step 5: Inspect final git state without disturbing unrelated changes**

```powershell
git diff --check
git status --short
git log --oneline -20
```

## Self-review result

- Spec coverage: real-route captures, live event provenance, leak cleanup, 70/70 real consumers, exact-size sheets, independent two-game playtest, repair loop, and final completion audit are covered by Tasks 1-5.
- Placeholder scan: all evidence files, commands, score thresholds, hard failures, and repair rules are explicit.
- Type consistency: combat event kinds and sources, coverage fields, capture names, and review fields stay consistent across tasks.
