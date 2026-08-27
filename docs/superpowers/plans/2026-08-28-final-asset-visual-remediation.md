# Final Asset Visual Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear the seven development-preview visual blockers found by the independent 70-unit audit without changing gameplay IDs, values, or shipping approvals.

**Architecture:** Candidate raster repairs remain isolated in the development-preview overlay and preserve every approved shipping hash. Runtime presentation repairs are split into combat geometry, real UI consumers, and evidence regeneration so each can be tested and reviewed independently. Real 1280×720 routes, not galleries or synthetic observers, own the final visual and coverage evidence.

**Tech Stack:** Godot 4.7 typed GDScript, GdUnit4, built-in ImageGen, `generate2dsprite` deterministic postprocessing, GOGOBRO item-harmony v2 checkers, Python/Pillow QA, Windows OpenGL route captures.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

**Audit:** `.superpowers/sdd/2026-08-27-brotato-structured-ui-redesign/final-asset-visual-audit.md`

## Global Constraints

- Keep exactly one character definition: `character.niko:character/niko`.
- Preserve all canonical content/static IDs and gameplay values; presentation-only boundary margin changes are allowed only to keep the enlarged weapon ring on screen.
- Never overwrite `game/assets/gogobro_static/`, `gogobro_static_runtime_bindings_v1.json`, approved candidate records, shipping hashes, or approval state.
- New art is `candidate_preview_only`; no candidate receives or inherits shipping approval.
- Generate each distinct raster with a separate built-in ImageGen call. Use solid `#FF00FF` raw backgrounds and deterministic postprocessing; code must not draw replacement art.
- Clarity at actual game size is the gate. Preserve useful moderate detail; do not force coarse pixels or large color blocks.
- Items/upgrades must be physical or body-part-themed. Weapons must be recognizable as their mapped CS archetype before reading the label.
- No decorative frame around the viewport, no fake entries, no gallery-only consumers, and no texture-counting via palette sampling.
- Every capture is an actual 1280×720 application route with nearest-filtered game textures.
- The 60-tuple all-item worn-appearance matrix remains an explicitly separate release gate. This plan validates only the currently integrated helmet appearance in both trusted Niko walking animations.

## File Structure

| File or area | Responsibility |
| --- | --- |
| `game/assets/gogobro_static_preview/{weapons,upgrades,items,ui}/` | Candidate-only repaired rasters consumed by debug preview. |
| `game/content/assets/gogobro_static_candidate_preview_v1.json` | Exact candidate paths, hashes, geometry, filters, and preview-only status. |
| `tools/assets/gogobro_static_candidate_preview_coverage_v1.json` | Source/curated evidence and mechanical QC for all preview units. |
| `game/content/packs/items/smoke_shell_helmet/smoke_shell_helmet_preview_factory.gd` | Preview-only worn helmet definition; shipping factory remains immutable. |
| `game/gameplay/actors/player_actor.gd` | Pivot-aware six-weapon ring and edge-safe player clamp extent. |
| `game/gameplay/world/static_world_presenter.gd` | Deterministic off-grid, center-clear world composition. |
| `game/gameplay/actors/enemy_actor.gd` | Cohesive role palette without gameplay changes. |
| `game/content/assets/gogobro_static_consumer_registry.gd` | Records actual visible texture consumption. |
| `game/content/assets/gogobro_static_coverage_audit.gd` | Rejects false coverage for required visible UI textures. |
| `game/ui/{diagnostic_screen,difficulty_select_screen,brotato_combat_hud,main_menu_screen}.gd` | Real low-border consumers and compact button layout. |
| `tests/` and real route smoke tests | TDD contracts, 70/70 evidence, captures, and runtime regressions. |

---

### Task 1: Repair candidate raster identity and preview helmet parity

**Files:**
- Modify: `game/assets/gogobro_static_preview/weapons/warmup_shiv.png`
- Modify: `game/assets/gogobro_static_preview/upgrades/pre_aim_drills.png`
- Modify: `game/assets/gogobro_static_preview/items/smoke_shell_helmet.png`
- Create: `game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png`
- Modify: `game/assets/gogobro_static_preview/ui/combat_hud_shell.png`
- Modify: `game/content/assets/gogobro_static_candidate_preview_v1.json`
- Modify: `tools/assets/gogobro_static_candidate_preview_coverage_v1.json`
- Create: `game/content/packs/items/smoke_shell_helmet/smoke_shell_helmet_preview_factory.gd`
- Modify: `game/content/assets/gogobro_static_preview_content_factory.gd`
- Modify: `tests/unit/test_static_candidate_preview_manifest.gd`
- Modify: `tests/unit/test_static_candidate_preview_runtime.gd`
- Modify: `tests/unit/test_static_redraw_contract.gd`
- Modify: `tests/unit/test_combat_static_ui_consumers.gd`
- Test: `tests/unit/test_smoke_shell_helmet_install.gd`

**Interfaces:**
- Preserve: `warmup_shiv` pivot `[24,39]` and contact `[52,25]`; all other IDs, roles, selectors, pivots, anchors, sizes, mechanics, and nearest/no-mipmap contracts.
- Produce: `SmokeShellHelmetPreviewFactory.configure_item(definition: GogoItemDefinition) -> void`, using the new preview worn raster and the existing `head/head_shell/RIGID/40`, scale `0.625`, pivot `[36,48]`, offset `[0,0]` tuple.
- Preserve: `SmokeShellHelmetFactory` and every approved shipping raster/hash byte-for-byte.

- [x] **Step 1: Write failing preview identity/isolation tests**

Add exact candidate-source assertions for `warmup_shiv/candidate-003`, `pre_aim_drills/candidate-002`, `smoke_shell_helmet/candidate-005`, and `combat_hud_shell/candidate-002`. Assert preview helmet appearance texture path is `res://game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png`, while the shipping path and hashes remain unchanged. Add a shell pixel-structure check that its outer 3px border is fully transparent and its bottom half contains no empty inventory-slot frame.

```gdscript
assert_str(String(preview_helmet.appearances[0].texture.resource_path)).is_equal(
	"res://game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png"
)
assert_str(FileAccess.get_sha256(
	"res://game/assets/gogobro_static/items/smoke_shell_helmet_appearance.png"
).to_upper()).is_equal("B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A")
```

- [x] **Step 2: Run the focused tests RED**

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -TestPath res://tests/unit/test_static_candidate_preview_manifest.gd -ReportDir reports/art-remediation-red
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -TestPath res://tests/unit/test_static_candidate_preview_runtime.gd -ReportDir reports/art-runtime-red
```

Expected: old candidate paths fail, preview helmet still loads shipping appearance, and the old HUD shell violates the transparent-edge/no-slot check.

- [x] **Step 3: Generate four new candidate rasters**

Before generation, view Niko's mother frame plus accepted detailed item/weapon references. Call built-in ImageGen once per distinct asset. Save raw and prompt/provenance under these new inbox roots:

- `GOGOBRO_ASSET_INBOX/02_static_assets/weapons/warmup_shiv/candidate-003/`
- `GOGOBRO_ASSET_INBOX/02_static_assets/upgrades/pre_aim_drills/candidate-002/`
- `GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-005/`
- `GOGOBRO_ASSET_INBOX/02_static_assets/ui_brand/combat_hud_shell/candidate-002/`

The prompts must require, respectively: a side-on open Butterfly Knife with two separated handles and two exposed pivots; a tangible optic-adjustment training jig rather than a reticle; one olive smoke-filter helmet identity used for icon and worn layer; and a transparent low-border HUD underlay containing only separated top-left/top-center backing accents with no outer frame or bottom inventory slots.

- [x] **Step 4: Postprocess and visually gate at actual size**

Use `generate2dsprite` only for chroma cleanup, alpha, component filtering, nearest scaling, safe margins, and QC. Export 64×64 weapon/upgrade/icon, the 128×128 helmet appearance used by the current `walk_down` preview runtime, a candidate-only 96×96 derivative of the same helmet identity for trusted `walk_left45` compatibility checking, and a 320×180 HUD underlay. Inspect 1× and 6× views. Reject a generic knife, freestanding reticle, mismatched helmet, blurry edge, clipped subject, or shell that outlines the viewport. The 96×96 derivative is evidence for the differently sized trusted animation, not a claim that `walk_left45` is already runtime-integrated.

- [x] **Step 5: Integrate preview-only files and update exact hashes**

Copy byte-identical curated outputs to the preview paths, update candidate manifest/coverage hashes and source paths, and make `GogoStaticPreviewContentFactory` use `SmokeShellHelmetPreviewFactory` only in preview content. Shipping service and approved factory remain unchanged.

- [x] **Step 6: Run helmet harmony and focused GREEN**

Run both trusted Niko rig checks and strict v2 helmet harmony checks for `walk_down` and `walk_left45`; both must return `harmony_pass`. Correct the preflight's impossible single-source command by using the 128×128 runtime appearance for the 128×128 `walk_down` rig and the explicitly candidate-only 96×96 derivative for the 96×96 `walk_left45` rig. Report `walk_down` as actual preview-runtime parity and `walk_left45` only as trusted-animation compatibility; do not claim that the latter is currently runtime-integrated. Then run:

```powershell
python tools/assets/build_static_candidate_preview.py --check --source-root E:\01_gobro
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_manifest.gd -ReportDir reports/art-manifest-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_runtime.gd -ReportDir reports/art-runtime-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_smoke_shell_helmet_install.gd -ReportDir reports/art-helmet-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_redraw_contract.gd -ReportDir reports/art-contract-green
```

- [ ] **Step 7: Commit and request blind actual-size art review**

```powershell
git add game/assets/gogobro_static_preview/weapons/warmup_shiv.png game/assets/gogobro_static_preview/upgrades/pre_aim_drills.png game/assets/gogobro_static_preview/items/smoke_shell_helmet.png game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png game/assets/gogobro_static_preview/ui/combat_hud_shell.png game/content/assets/gogobro_static_candidate_preview_v1.json tools/assets/gogobro_static_candidate_preview_coverage_v1.json game/content/packs/items/smoke_shell_helmet/smoke_shell_helmet_preview_factory.gd game/content/assets/gogobro_static_preview_content_factory.gd tests/unit/test_static_candidate_preview_manifest.gd tests/unit/test_static_candidate_preview_runtime.gd tests/unit/test_static_redraw_contract.gd tests/unit/test_combat_static_ui_consumers.gd tests/unit/test_smoke_shell_helmet_install.gd
git commit -m "fix: repair final preview asset identities"
```

The reviewer must identify the Butterfly Knife and physical pre-aim object without labels, compare helmet icon/worn identity on Niko, and reject any coarse-pixel requirement not supported by actual-size clarity.

---

### Task 2: Clear Niko with a pivot-aware weapon ring and finish the arena composition

**Files:**
- Modify: `game/gameplay/actors/player_actor.gd`
- Modify: `game/gameplay/world/static_world_presenter.gd`
- Modify: `game/gameplay/actors/enemy_actor.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`
- Modify: `tests/unit/test_static_world_presenter.gd`
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`
- Modify: `tests/integration/static_candidate_preview_combat_v1_smoke.gd`

**Interfaces:**
- Produce: `weapon_visual_footprint_radius(bounds: Vector2i, pivot: Vector2i) -> float`.
- Extend compatibly: `weapon_orbit_radius(count: int, weapon_display_bounds: Array[Vector2i] = [], weapon_pivots: Array[Vector2i] = []) -> float`.
- Preserve: six evenly spaced slots, nearest-target rotation, automatic fire cadence, muzzle anchors, all damage/range/cooldown values and IDs.
- Preserve: `StaticWorldPresenter.configure`, `apply_capture_safe_layout`, `consumer_records`, and record schema.

- [ ] **Step 1: Write failing geometry, palette, and composition tests**

```gdscript
var radius := actor.weapon_orbit_radius(6, bounds, pivots)
var footprint := actor.weapon_visual_footprint_radius(Vector2i(96, 64), Vector2i(38, 40))
assert_float(radius - footprint).is_greater_equal(GogoPlayerActor.NIKO_CLEAR_RADIUS)
assert_str(GogoEnemyActor.visual_color_for_role(GogoEnemyDefinition.Role.SHOOTER).to_html(false)).is_equal("9aa75a")
```

Replace obsolete `% 64 == 0` prop assertions with deterministic same-seed equality, at least eight off-grid foreground placements, no player-center overlap, no HUD overlap, and no intersecting prop rectangles.

- [ ] **Step 2: Run focused tests RED**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_runtime_correctness.gd -ReportDir reports/combat-presentation-red
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_world_presenter.gd -ReportDir reports/world-presentation-red
```

- [ ] **Step 3: Implement pivot-aware orbit and edge-safe clamping**

Compute each weapon's farthest pivot-to-corner radius. Choose the ring radius from both Niko clearance and adjacent-slot chord clearance, using 16px player gap and 12px slot gap. Cache the complete orbit extent and use it as the arena clamp margin. Do not change sprite pivot, muzzle, rotation, target selection, or weapon stats.

- [ ] **Step 4: Implement deterministic off-grid world composition and enemy palette**

Use seeded, asymmetric perimeter/scatter anchors with a clear combat center and rejection for HUD/prop intersections. Map chaser/shooter/charger to rust `b86d52`, olive `9aa75a`, and amber `d68a3a` with the existing dark outline; do not change enemy mechanics.

- [ ] **Step 5: Fix only the capture fixture's arena size and run GREEN**

Set `CAPTURE_ARENA_SIZE = Vector2(1280, 720)` in the integration fixture; leave the normal `2048×1536` zone intact. Assert the arena covers the capture, all six rotated footprint circles clear Niko and neighbors, and at least eight foreground records are off-grid.

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_runtime_correctness.gd -ReportDir reports/combat-presentation-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_world_presenter.gd -ReportDir reports/world-presentation-green
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_combat_v1_smoke.gd -a res://tests/integration/static_candidate_preview_combat_v1_smoke.gd"
```

- [ ] **Step 6: Inspect real 1280×720 combat and commit**

At 1×, require visible gaps between Niko and all six target-facing weapons, no weapon-to-weapon intersection, full floor/boundary coverage, sparse non-grid props, and cohesive enemies. Verify actual shots, contacts, recoil, critical/pierce/explosion feedback and auto-fire still occur.

```powershell
git add game/gameplay/actors/player_actor.gd game/gameplay/world/static_world_presenter.gd game/gameplay/actors/enemy_actor.gd tests/unit/test_combat_runtime_correctness.gd tests/unit/test_static_world_presenter.gd tests/integration/full_static_assets_combat_v1_smoke.gd tests/integration/static_candidate_preview_combat_v1_smoke.gd
git commit -m "fix: clear the six-weapon combat composition"
```

---

### Task 3: Add honest visible UI consumers and compact main-menu buttons

**Files:**
- Modify: `game/content/assets/gogobro_static_consumer_registry.gd`
- Modify: `game/content/assets/gogobro_static_coverage_audit.gd`
- Modify: `game/ui/screen_base.gd`
- Modify: `game/ui/diagnostic_screen.gd`
- Modify: `game/ui/difficulty_select_screen.gd`
- Modify: `game/ui/brotato_combat_hud.gd`
- Modify: `game/ui/main_menu_screen.gd`
- Modify: `tests/unit/test_static_asset_coverage_audit.gd`
- Modify: `tests/unit/test_static_menu_consumers.gd`
- Modify: `tests/unit/test_combat_static_ui_consumers.gd`
- Modify: `tests/integration/full_static_assets_menu_v1_smoke.gd`
- Modify: `tests/integration/full_static_assets_combat_v1_smoke.gd`
- Modify: `tests/integration/button_stability_v2_smoke.gd`

**Interfaces:**
- Produce: `GogoStaticAssetConsumerRegistry.observe_visible_texture(handle, canvas_item, scene_path, node_path, integer_display_scale := Vector2i.ONE, source_kind := &"") -> bool`.
- Produce: `GogoScreenBase.resolve_global_handle(asset_id: StringName, selector: StringName = &"") -> GogoStaticAssetHandle`.
- Require visible-texture observations for `nine_slice_panel`, `combat_hud_shell`, and `zone_thumbnail`; ordinary handle/palette observations cannot cover them.

- [ ] **Step 1: Write failing real-consumer and coverage tests**

Assert the three required IDs are uncovered unless a visible in-tree `TextureRect`/`NinePatchRect` uses the exact handle texture and records `visible_texture: true`. Assert current synthetic generic-screen observations produce `texture_not_visibly_displayed`.

```gdscript
for asset_id in [&"nine_slice_panel", &"combat_hud_shell", &"zone_thumbnail"]:
	assert_bool(_accepted_records(asset_id).any(func(record: Dictionary) -> bool:
		return bool(record.get("visible_texture", false))
	)).is_true()
```

- [ ] **Step 2: Run focused tests RED**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_asset_coverage_audit.gd -ReportDir reports/ui-coverage-red
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_menu_consumers.gd -ReportDir reports/ui-menu-red
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_static_ui_consumers.gd -ReportDir reports/ui-hud-red
```

- [ ] **Step 3: Implement visible-observation semantics**

`observe_visible_texture` returns false unless the handle/texture exists, the control is visible in tree, its `texture` property is the same texture, and scene/node provenance passes existing allowlists. Ordinary observations explicitly store `visible_texture: false`. Coverage audit hard-rejects false observations for the three IDs.

- [ ] **Step 4: Add the three restrained real consumers**

- `DiagnosticScreen`: one 736×352 `NinePatchRect` at `(272,184)` as its only principal modal surface.
- `DifficultySelectScreen`: one borderless 256×144 zone thumbnail inside `SelectedDifficultyDetail`, with badge/text moved below it and no fake zone choice.
- `BrotatoHUD`: a full 1280×720 nearest `Shell` texture below metrics using the new Task-1 underlay. Because the repaired raster has transparent outer edges, no connected viewport frame, and no lower slots, it may be shown at exact 4× without violating the border budget. Remove `MetricPalette` color sampling.

- [ ] **Step 5: Compact the main-menu action stack**

Create centered `MenuActions` sized 320×104 with two 320×48 buttons and 8px separation. Keep all four authored state textures and actions; do not stretch them across the 1216px body.

- [ ] **Step 6: Replace synthetic coverage with actual routes and run GREEN**

Route real Main Menu, Difficulty, Diagnostic, and Combat HUD instances. Capture `menu`, `difficulty-select`, `diagnostic`, and `combat`; assert exact nodes, sizes, nearest filtering, texture identity, and `visible_texture: true` provenance.

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_asset_coverage_audit.gd -ReportDir reports/ui-coverage-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_menu_consumers.gd -ReportDir reports/ui-menu-green
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_static_ui_consumers.gd -ReportDir reports/ui-hud-green
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd -a res://tests/integration/full_static_assets_combat_v1_smoke.gd -a res://tests/integration/button_stability_v2_smoke.gd"
```

- [ ] **Step 7: Inspect border budget and commit**

Require compact buttons rather than rails, one diagnostic panel only, a readable zone image without an extra frame, and a HUD underlay that is visible but does not enclose the viewport or recreate inventory slots.

```powershell
git add game/content/assets/gogobro_static_consumer_registry.gd game/content/assets/gogobro_static_coverage_audit.gd game/ui/screen_base.gd game/ui/diagnostic_screen.gd game/ui/difficulty_select_screen.gd game/ui/brotato_combat_hud.gd game/ui/main_menu_screen.gd tests/unit/test_static_asset_coverage_audit.gd tests/unit/test_static_menu_consumers.gd tests/unit/test_combat_static_ui_consumers.gd tests/integration/full_static_assets_menu_v1_smoke.gd tests/integration/full_static_assets_combat_v1_smoke.gd tests/integration/button_stability_v2_smoke.gd
git commit -m "fix: make static UI coverage visible and restrained"
```

---

### Task 4: Regenerate evidence and independently compare both games

**Files:**
- Modify only if a failing final gate exposes a defect in its owning task; otherwise no production changes.
- Create ignored evidence under: `reports/final-asset-remediation/`
- Update coordination report: `.superpowers/sdd/2026-08-27-brotato-structured-ui-redesign/final-remediation-report.md`

**Interfaces:**
- Consume: Task 1 repaired preview assets, Task 2 combat geometry/composition, Task 3 visible-coverage semantics/routes.
- Produce: exact 70/70 visible/mechanical coverage report, current real-route captures, final actual-size audit, and fresh written Brotato/GOGOBRO playtest comparison.

- [ ] **Step 1: Run the complete unit and integration suite**

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -ReportDirectory res://reports/final-asset-remediation/full-suite
```

Require zero failures, errors, leaks, or orphans. Run `git diff --check`.

- [ ] **Step 2: Regenerate every real 1280×720 route artifact**

Run windowed OpenGL menu and combat smoke tests into unique uncached AppData/report directories. Record SHA-256 for main menu, character, weapon, difficulty, diagnostic, shop, upgrade, combat, and pause captures plus the coverage JSON.

- [ ] **Step 3: Re-run the 70-unit visual audit**

Create fresh contact sheets from final integrated textures. Require 70/70 development-preview units to have real consumers; 30/30 item icons physical; 12/12 CS weapon identities; 6/6 upgrades physical/body-part-themed; no Important/Critical actual-size defect. Report the 60-tuple release appearance matrix separately as not attempted, never as a development-preview failure.

- [ ] **Step 4: Fresh subagent plays Brotato and GOGOBRO**

Use isolated temporary AppData for Brotato and do not touch real saves/config/install. Play both through the new-run setup, early combat, first upgrade, and shop. Compare weapon orbit spacing, acquisition, auto-fire cadence, recoil, projectiles, hit/death feedback, HUD scan order, menu/button density, upgrade/shop clarity, and border restraint. GOGOBRO must be accepted as at least structurally/visually competitive for its original-art scope.

- [ ] **Step 5: Final whole-branch code/spec review**

Review the complete branch from the recorded pre-remediation base through HEAD. Any Critical/Important/spec gap returns to its owning implementer with a focused test and fresh re-review.

- [ ] **Step 6: Record final result**

Write `final-remediation-report.md` with commits, test counts, hashes, audit counts, comparative playtest verdict, deferred release-only 60-tuple matrix, and remaining Minor polish only.

## Self-Review Result

- Spec coverage: every development-preview blocker from `final-asset-visual-audit.md` is assigned to Tasks 1–3; Task 4 owns evidence and independent comparison.
- Placeholder scan: every step contains an exact action, path, command, and pass/fail condition.
- Type consistency: the new consumer and orbit helpers have one exact signature throughout the plan; existing public route/content interfaces remain unchanged.
- Scope ruling: the strict 60-tuple appearance matrix is deliberately excluded from this development-preview remediation because only the helmet appearance is currently integrated and no shipping/release approval is being requested. Helmet parity still receives both required v2 walking checks.
