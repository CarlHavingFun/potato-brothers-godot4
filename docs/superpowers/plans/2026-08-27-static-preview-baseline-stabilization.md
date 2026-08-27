# Static Preview Baseline Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the already-implemented dirty static-preview integration into a coherent, tested checkpoint before the weapon/item/UI redesign touches the same files.

**Architecture:** Preserve the existing candidate variant, world-layout, HUD, menu-consumer, display-scale, and generic projectile-mechanics work. Exclude the obsolete Desert-Eagle explosion mapping and the still-red combat capture from this checkpoint; later approved tasks replace them with the canonical skyline-grenade source and stable-ID capture fixture. Add runtime lifecycle cleanup so pending enemies cannot outlive a destroyed combat world.

**Tech Stack:** Godot 4.7 typed GDScript, GdUnit4, JSON candidate manifests, nearest-neighbor PNG assets.

**Spec:** `docs/superpowers/specs/2026-08-27-full-static-assets-brotato-hud-design.md`

## Global Constraints

- Preserve every existing dirty change unless this plan explicitly identifies it as obsolete.
- Do not overwrite approved shipping artwork or approval evidence.
- Do not commit `heavy_hand_cannon -> explosion`; Desert Eagle must remain a normal ballistic weapon.
- Do not weaken or fake the live combat capture; leave its skyline-grenade conversion for the dedicated runtime task.
- Candidate UI/world variants remain development-only and hash-bound.
- All focused tests in this checkpoint exit 0 with zero orphans.

---

### Task 1: Reconcile, verify, and commit the existing preview foundation

**Files:**
- Preserve and commit: `game/content/assets/gogobro_static_candidate_preview_service.gd`
- Preserve and commit: `game/content/assets/gogobro_static_candidate_preview_v1.json`
- Preserve and commit: `game/gameplay/weapons/projectile.gd`
- Preserve and commit: `game/gameplay/weapons/weapon_instance.gd`
- Preserve and commit: `game/gameplay/world/static_world_presenter.gd`
- Preserve and commit: `game/ui/brotato_combat_hud.gd`
- Preserve and commit: `game/ui/combat_screen.gd`
- Preserve and commit: `game/ui/screen_base.gd`
- Preserve and commit: `game/ui/static_card_presenter.gd`
- Preserve and commit: `tests/integration/full_static_assets_menu_v1_smoke.gd`
- Preserve and commit: all currently dirty focused unit tests except obsolete preview-weapon explosion expectations.
- Preserve and commit: current untracked UI rarity/button variants, world decor variants, and `tests/unit/test_projectile_impact_mechanics.gd`.
- Modify: `game/gameplay/world/combat_world.gd`
- Modify: `tests/unit/test_combat_runtime_correctness.gd`
- Leave uncommitted for the later canonical trigger task: `game/content/assets/gogobro_static_preview_content_factory.gd`, `game/content/assets/gogobro_static_preview_content_v1.json`, and `tests/integration/full_static_assets_combat_v1_smoke.gd`.

**Interfaces:**
- Produces a stable development-preview snapshot with exact selector variants and no aliases.
- Preserves generic projectile behavior for `normal`, `critical`, `pierce_exit`, and `explosion` without assigning explosion to Desert Eagle.
- Produces `CombatWorld._exit_tree()` cleanup that stops ticking and frees all pending/active combat actors.

- [ ] **Step 1: Read and classify every dirty hunk before staging**

Require each hunk to belong to candidate variants, real UI/world consumers, native HUD, display scale, generic projectile mechanics, route evidence, or test coverage. Record any unrelated hunk in the report and leave it unstaged.

- [ ] **Step 2: Remove only the obsolete preview-weapon explosion assertion**

Keep the three real projectile behavior tests. Remove the uncommitted test that requires `heavy_hand_cannon` to map to `explosion`; do not remove or weaken generic explosion mechanics.

- [ ] **Step 3: Add a failing runtime-destruction test**

```gdscript
func test_world_exit_frees_pending_enemy_spawn() -> void:
	var world := _running_world_with_pending_marker()
	assert_int(world.pending_spawn_enemy_count()).is_equal(1)
	world.free()
	await get_tree().process_frame
	assert_int(Engine.get_process_frames()).is_greater(0)
```

The break caught is a pending `GogoEnemyActor`/Body2D surviving after its owning world exits. Verify RED through GdUnit orphan/RID output, not only a source-text assertion.

- [ ] **Step 4: Implement lifecycle cleanup at the owner**

```gdscript
func _exit_tree() -> void:
	running = false
	_clear_active_combat_actors()
```

Make cleanup idempotent so explicit test/session clears followed by `_exit_tree()` do not double-free enemies or markers.

- [ ] **Step 5: Run the focused baseline suites**

```powershell
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_manifest.gd -ReportDir reports/baseline-manifest
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_candidate_preview_runtime.gd -ReportDir reports/baseline-runtime
tools\run_tests.ps1 -TestPath res://tests/unit/test_brotato_combat_hud.gd -ReportDir reports/baseline-hud
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_menu_consumers.gd -ReportDir reports/baseline-menu
tools\run_tests.ps1 -TestPath res://tests/unit/test_static_world_presenter.gd -ReportDir reports/baseline-world
tools\run_tests.ps1 -TestPath res://tests/unit/test_projectile_impact_mechanics.gd -ReportDir reports/baseline-projectile
tools\run_tests.ps1 -TestPath res://tests/unit/test_combat_runtime_correctness.gd -ReportDir reports/baseline-cleanup
```

Expected: every command exits 0 with zero orphans.

- [ ] **Step 6: Run the real menu capture**

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd"
```

Expected: exit 0 and four current-route baseline captures. They are evidence for later comparison, not final UI acceptance.

- [ ] **Step 7: Commit only the checkpoint-owned files**

Use explicit `git add` paths. Confirm the three deferred files remain dirty and no other pre-existing change was dropped. Commit as:

```powershell
git commit -m "feat: stabilize static preview runtime foundation"
```

## Self-review result

- Spec coverage: the checkpoint preserves every completed prior integration slice, removes only the now-invalid Desert-Eagle mapping expectation, fixes the proven lifecycle leak, and leaves the canonical explosion/capture conversion for its owning task.
- Placeholder scan: files, excluded hunks, failing behavior, implementation, commands, and expected results are explicit.
- Type consistency: generic projectile kinds and combat-world lifecycle remain compatible with the later skyline-grenade trigger task.
