# Main Merge Red-Gate Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the final GOGOBRO integration branch satisfy an honest full-suite merge gate, then make it eligible for fast-forward integration into `main`.

**Architecture:** Preserve accepted gameplay and presentation contracts while repairing two production-data regressions. Migrate legacy tests to current public APIs and behavior, regenerate deterministic evidence, and represent window-only tests as explicit headless skips instead of timeouts or false failures.

**Tech Stack:** Godot 4.7.1, typed GDScript, GdUnit4 6.2.0, PowerShell, Python static-asset generators, Git worktrees.

**Spec:** `docs/superpowers/specs/2026-09-03-main-merge-red-gate-remediation-design.md`

## Global Constraints

- Work only in `E:/01_gobro/.worktrees/gobro-release-integration-v2-20260902` until the final merge step.
- Never run two Godot/GOGOBRO invocations concurrently; verify zero matching processes before and after every run.
- Never touch, stop, or inspect unrelated games or processes.
- Preserve `main`'s dirty worktree recoverably before moving `refs/heads/main`.
- Do not weaken accepted emergency-stop tuning, single-zone flow, 32-slot roster, checkpoint exactness, or static-only feedback.
- A test expectation may change only when this spec names the accepted replacement contract.
- Exact staging only; never stage generated `.uid` files or unrelated `.import` artifacts.

---

### Task 1: Restore production balance and shipping import invariants

**Files:**
- Modify: `game/content/assets/gogobro_static_preview_content_v1.json`
- Modify: `game/content/validation_content_factory.gd`
- Modify: `game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_1672x941.png.import`
- Modify: `game/assets/gogobro_static/ui/zone_thumbnail_training_ground_v2_256x144_rgba8.png.import`
- Modify: `game/assets/gogobro_static/world/community_server_floor_training_ground_v2_1448x1086.png.import`
- Modify: `game/assets/gogobro_static/world/community_server_floor_training_ground_v2_2048x1536_rgba8.png.import`
- Test: `tests/unit/test_weapon_archetype_runtime.gd`
- Test: `tests/unit/test_static_preview_content_factory.gd`
- Test: `tests/unit/test_shipping_static_import_policy.gd`

**Interfaces:**
- Consumes: approved weapon matrix pinned by the existing tests and spec.
- Produces: 12 definitions with exact approved base damage/cooldown; four lossless shipping imports.

- [ ] **Step 1: Preserve the verified RED evidence**

Use `reports/main-merge-preflight-20260903/report_1/results.xml`: weapon archetypes have 21 failures, preview content has 2, and shipping import policy has 4.

- [ ] **Step 2: Restore exact production values**

Set the JSON damage/cooldown pairs to:

```text
community_tapper 3.0 / 0.18
wood_stock_assault_rifle 8.0 / 0.34
heavy_bolt_sniper 30.0 / 1.45
suppressed_carbine 7.0 / 0.38
suppressed_tactical_pistol 6.0 / 0.42
heavy_hand_cannon 18.0 / 0.82
box_submachine_gun 4.0 / 0.16
compact_submachine_gun 4.5 / 0.15
bullpup_pdw 5.0 / 0.20
folding_stock_submachine_gun 5.5 / 0.22
```

Keep all other JSON fields unchanged. In `_weapon_pack`, set:

```gdscript
weapon.damage = 7.0 if melee else 4.0
weapon.cooldown_seconds = 0.55 if melee else 0.42
```

Set `process/fix_alpha_border=false` in all four listed sidecars.

- [ ] **Step 3: Verify GREEN**

Run the three focused suites serially with `tools/run_tests.ps1`, then run `git diff --check`. Expected: zero errors/failures/orphans and exit 0.

- [ ] **Step 4: Commit**

Stage only the six production files and commit `fix: restore approved weapon and import contracts`.

### Task 2: Migrate combat/HUD/reward legacy tests to accepted runtime contracts

**Files:**
- Modify: `tests/unit/test_brotato_combat_hud.gd`
- Modify: `tests/unit/test_combat_event_publication.gd`
- Modify: `tests/unit/test_combat_feedback_presenter.gd`
- Modify: `tests/unit/test_combat_static_ui_consumers.gd`
- Modify: `tests/unit/test_pause_overlay.gd`
- Modify: `tests/unit/test_reward_ledger.gd`

**Interfaces:**
- Consumes: authoritative `weapon_inventory`, `SessionPlayerState.INITIAL_MATERIALS`, bundled pickup entries, current HUD tree, static-only feedback, melee windup.
- Produces: behavior tests that fail on mutations of those current contracts without asserting obsolete private structure.

- [ ] **Step 1: Use existing full-suite failures as RED**

Confirm the six suites account for the inventory projection errors, old material totals, two-pickup assumption, visible full-screen shell, raw 64×64 feedback sizing, immediate melee hit, and six-placeholder pause loadout.

- [ ] **Step 2: Update fixtures through public behavior**

Populate weapons with `player.weapon_inventory.add_weapon(content_id, content_snapshot, 1)` and assert `error == OK`. Test snapshot detachment by removing an authoritative instance after snapshot creation, not by mutating `weapon_ids`.

- [ ] **Step 3: Replace obsolete totals and structures**

Use literal behavior deltas from `SessionPlayerState.INITIAL_MATERIALS`: unchanged `20`, plus 10 is `30`, plus 6 is `26`, and plus 3 is `23`. Expect one bundled pickup while retaining the two ordered reward commits. Assert hidden/null full-screen shell, local opaque metric backing, font sizes 26/14, and `MaterialIcon`; the disabled shell consumer has no display scale contract.

- [ ] **Step 4: Update feedback/melee behavior**

Expect `static_asset_required` with no procedural blocks when a static-only effect lacks a snapshot. For resolved static effects, assert `texture_size == Vector2i(effect.size_px, effect.size_px)` and centered pivot. Start melee at delta `0.0`, then advance by `weapon.debug_melee_seconds_until_contact() + 0.001` before asserting contact, damage, and hitstop.

- [ ] **Step 5: Update pause loadout behavior**

Assert exactly the owned weapon slots under `Loadout/ItemsScroll/ItemsGrid`; do not expect six capacity placeholders or `Loadout/Items`.

- [ ] **Step 6: Verify and commit**

Run all six focused suites plus `test_combat_pickup.gd`, `test_combat_runtime_correctness.gd`, `test_brotato_structured_screens.gd`, and `test_visible_quality_contract.gd`; expect zero errors/failures/orphans. Commit only the six tests as `test: align combat contracts with accepted runtime`.

### Task 3: Repair selection isolation and accepted-content probes

**Files:**
- Modify: `tools/run_tests.ps1`
- Modify: `tests/unit/test_playtest_menu_selection.gd`
- Modify: `tests/unit/test_content_optional_icon.gd`
- Modify: `tests/unit/test_upgrade_reward_diversity.gd`

**Interfaces:**
- Consumes: isolated environment variables set by the runner, pointer coordinates, accepted `重甲头盔` name, 60 Hz counter-strafe behavior.
- Produces: fail-closed generic isolation and stable selection/content tests.

- [ ] **Step 1: Preserve RED evidence**

Use the current report: selection has pointer cascades and task6-only profile failures; optional icon expects the old name; braking compares two saturated zero velocities.

- [ ] **Step 2: Harden the runner and profile guard**

Change the runner script argument from `res://addons/gdUnit4/bin/GdUnitCmdTool.gd` to `res://tests/helpers/isolated_gdunit_entry.gd`. In `_checked_profile_case_paths`, require exact equality with `GOGOBRO_TEST_EXPECTED_APPDATA`, `GOGOBRO_TEST_EXPECTED_LOCALAPPDATA`, and `GOGOBRO_TEST_EXPECTED_USER_DATA_DIR`; require all are absolute and outside `res://`; remove task6 naming/receipt assumptions; require each profile/temp/backup path to be directly under the exact user-data root.

- [ ] **Step 3: Fix real pointer coordinates and stale literals**

In `_click`, assign the same button-center vector to both `down.position` and `down.global_position`. Expect `重甲头盔` for `training_1`. Change the braking probe delta from `0.05` to `1.0 / 60.0` for both ordinary and improved release paths.

- [ ] **Step 4: Verify and commit**

Run the three focused suites and the staged-selection/task-zone/counter-strafe guards. Expected: zero errors/failures/orphans plus `ISOLATION_GUARD_OK`. Commit only the four files as `test: repair isolated selection regression coverage`.

### Task 4: Refresh deterministic static-asset evidence

**Files:**
- Modify: `tools/assets/gogobro_static_candidate_preview_coverage_v1.json`
- Modify: `tests/unit/test_static_candidate_preview_manifest.gd`
- Modify: `tests/unit/test_static_item_redraw_integration.gd`

**Interfaces:**
- Consumes: accepted candidate-003 for pre-aim drills, candidate-002 for rebound bottle, current generator-clean runtime manifest.
- Produces: checked-in coverage and literal regression constants that exactly identify accepted source bytes.

- [ ] **Step 1: Preserve RED evidence**

Use the current report: preview check exits 1 with stale coverage, and item redraw constants name older accepted sources/hashes.

- [ ] **Step 2: Regenerate coverage mechanically**

Run `python tools/assets/build_static_candidate_preview.py` in its documented write mode, then `python tools/assets/build_static_candidate_preview.py --check`. Do not manually rewrite generated JSON.

- [ ] **Step 3: Update accepted literal baselines**

Set pre-aim drills to candidate-003. Set rebound bottle to candidate-002 and its current SHA-256. Set the normalized runtime-manifest SHA to the value produced by the current generator. Do not change production manifests or art bytes.

- [ ] **Step 4: Verify and commit**

Run both focused suites, `python tools/build_static_shipping_install.py`, both generator checks, and `git diff --check`. Commit only the generated coverage and two tests as `test: refresh accepted static asset evidence`.

### Task 5: Make rendered-only test waivers explicit and close the full gate

**Files:**
- Modify: `tests/integration/native_960_character_flow_v1.gd`
- Modify: `tests/integration/native_960_hud_layout_v1.gd`
- Modify: `tests/integration/task_zone_native_960_visual_v1.gd`
- Modify: `tests/unit/test_weapon_quality_integration.gd`
- Create: `docs/superpowers/reports/2026-09-03-main-merge-red-gate-closeout.md`

**Interfaces:**
- Consumes: GdUnit `_skip` / `_skip_reason` test parameters and existing rendered evidence.
- Produces: generic headless suite with four transparent skips and a report linking their rendered lane.

- [ ] **Step 1: Convert wrong-environment failures into explicit skips**

For the two root-observer suites and the capture-only weapon case, add test parameters equivalent to:

```gdscript
_skip := DisplayServer.get_name() == "headless" or OS.get_environment("GOGOBRO_ROOT_OBSERVER_ENABLED") != "1",
_skip_reason := "requires the windowed 960x540 visual/root-observer runner"
```

For task-zone native 960, skip only when `DisplayServer.get_name() == "headless"` with reason `requires the windowed 960x540 visual runner`.

- [ ] **Step 2: Verify focused skip behavior**

Run each focused file through the generic headless runner. Expected: the four cases are reported skipped immediately, with no timeout and no failure.

- [ ] **Step 3: Run the complete generic suite**

Run `tools/run_tests.ps1 -TestPath res://tests -ReportDirectory res://reports/main-merge-final-20260903`. Expected: 638 discovered cases, zero errors/failures/orphans, and exactly four documented skips.

- [ ] **Step 4: Write closeout evidence**

Record exact suite counts, report paths, generator checks, commit IDs, and rendered evidence paths for character, HUD, task-zone, and weapon menu. State that headless skips are not rendered proof.

- [ ] **Step 5: Commit**

Commit the four test annotations and closeout report as `test: separate rendered visual gates from headless suite`.

### Task 6: Review and integrate into main

**Files:**
- No product-file edits expected.
- Git refs/worktree state only after final review is clean.

**Interfaces:**
- Consumes: green branch and recoverable main-worktree protection.
- Produces: `main` containing the final reviewed commits without losing prior dirty work.

- [ ] **Step 1: Run final whole-branch review**

Review the complete remediation diff against the spec and resolve all Critical/Important findings before integration.

- [ ] **Step 2: Reconfirm merge topology**

Require `main` to be an ancestor of the remediation branch with zero commits unique to `main`.

- [ ] **Step 3: Protect the dirty main checkout**

Create a dated safety branch at current `main`, stash tracked and untracked files with a dated message, and verify the stash exists before moving `main`. Do not delete the safety branch or stash.

- [ ] **Step 4: Fast-forward and verify**

Fast-forward `main`, run the complete generic suite on the merged result, and report exact commit/test/stash evidence. Preserve the integration worktree if its generated untracked files prevent non-destructive cleanup.
