# Runtime Regression Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore fullscreen control, visible starting-loadout selection, automatic weapon attacks, and repeated enemy contact damage.

**Architecture:** Keep display state in the Global autoload, selection state in SelectionPanel/SelectionCard, weapon targeting in Weapon, and repeat-hit cadence in the reusable hitbox/hurtbox components. Enemy scenes opt into repeat damage so all other attacks retain single-hit behavior.

**Tech Stack:** Godot 4.7.1, GDScript, GdUnit4 6.2.0, Godot MCP/CLI 0.8.2.

---

### Task 1: Add regression tests

**Files:**
- Create: `tests/unit/test_runtime_regressions.gd`
- Modify: `tests/unit/test_selection_panel.gd`

1. Add tests for F11/Alt+Enter fullscreen toggle state.
2. Add tests for the card overlay, row ButtonGroups, weapon target resolution, automatic cooldown start, and 0.75-second repeated contact damage.
3. Run the two suites with `tools/run_tests.ps1` and confirm failures describe missing behavior.

### Task 2: Restore selection feedback

**Files:**
- Modify: `scenes/ui/selection_panel/selection_card.gd`
- Modify: `scenes/ui/selection_panel/selection_card.tscn`
- Modify: `scenes/ui/selection_panel/selection_panel.gd`

1. Make cards toggle buttons and expose a selected overlay.
2. Assign separate character/weapon ButtonGroups.
3. Set the clicked card pressed only after content selection succeeds.
4. Run selection regression tests and confirm green.

### Task 3: Restore automatic attacks

**Files:**
- Modify: `scenes/weapons/weapon.gd`

1. Resolve detection Areas to their owning Enemy.
2. Deduplicate targets and prune invalid enemies.
3. Resolve exits through the same mapping.
4. Run automatic-attack regression tests and confirm the cooldown starts.

### Task 4: Repeat enemy contact damage

**Files:**
- Modify: `scenes/components/hitbox_component.gd`
- Modify: `scenes/components/hurtbox_component.gd`
- Modify: `scenes/components/hurtbox_component.tscn`
- Modify: `scenes/unit/enemy/enemy_chaser_slow.tscn`

1. Add an exported repeat interval defaulting to zero.
2. Track repeat-enabled overlaps and emit every 0.75 seconds.
3. Clear overlap state on exit or invalidation.
4. Configure the enemy base contact hitbox to 0.75 seconds.
5. Run contact regression tests and confirm projectiles/melee remain non-repeating.

### Task 5: Add fullscreen shortcuts

**Files:**
- Modify: `autoloads/global.gd`

1. Process F11 and Alt+Enter while paused.
2. Toggle persisted fullscreen state through the existing settings application path.
3. Run fullscreen regression tests.

### Task 6: Full verification and release

**Files:**
- Modify as required: `docs/PHASE_ONE_PLAYTEST.md`
- Generated: `dist/potato-brothers-phase1/*`

1. Validate modified scripts and run all GdUnit suites under Godot 4.7.1.
2. Run Godot MCP scene tree, play, input, runtime tree/errors, screenshot, and stop checks.
3. Build the phase-one desktop release and verify hashes.
4. Commit only the intended files to local `main`; do not push.
