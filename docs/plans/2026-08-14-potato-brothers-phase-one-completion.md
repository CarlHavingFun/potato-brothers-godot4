# Potato Brothers Phase One Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the remaining work for a playable, saveable, exportable ten-wave Phase 1 build on the single local `main` branch.

**Architecture:** Keep immutable gameplay content in the restricted default content pack and mutable run data in `RunState`. Move orchestration and transactions out of `Global` and UI scripts into focused services, while retaining the working Godot component scenes. Implement and verify one vertical slice at a time so `main` remains runnable after every local commit.

**Tech Stack:** Godot 4.7.1 Standard, GDScript, Compatibility renderer, GdUnit4 6.2.0, Godot MCP/CLI 0.8.2, PowerShell, GitHub Actions.

**Branch rule:** Work directly on the only `main` branch. Do not create branches, worktrees, PRs, or remote pushes. Each commit below is a local `git commit` unless the user later explicitly requests a push.

---

## Completion order

The order is deliberately dependency-driven:

1. Stabilize and commit the current expanded content checkpoint.
2. Establish directors and deterministic services.
3. Make all sixteen stats and both aim modes affect live combat.
4. Complete waves, difficulty scaling, and MouseDog.
5. Complete upgrades, reward boxes, shop, and inventory flow.
6. Complete the ten-wave win/death product loop.
7. Integrate local saves, unlocks, settings, and translations.
8. Produce and validate the restricted content PCK.
9. Add end-to-end, leak, and performance verification.
10. Export the three desktop builds and stop at the playtest gate.

## Global verification command

Run after every task:

```powershell
.\tools\run_tests.ps1 `
  -GodotBinary 'D:\999_Godot\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe' `
  -TestPath 'res://tests' `
  -ReportDirectory 'res://test_reports\phase_one'
```

Expected: exit code `0`, zero errors, zero failures, zero skipped tests, and zero orphans.

Also run after scene or lifecycle changes:

```powershell
.\tools\check_clean_exit.ps1 `
  -GodotBinary 'D:\999_Godot\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe' `
  -Mode Editor

.\tools\check_clean_exit.ps1 `
  -GodotBinary 'D:\999_Godot\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe' `
  -Mode Game
```

Expected: no script error, orphan node, ObjectDB instance, or resource leak report.

---

### Task 1: Stabilize the current expanded content checkpoint

**Files:**

- Modify: `autoloads/global.gd`
- Modify: `content_packs/default/pack.tres`
- Modify: `core/content/content_catalog.gd`
- Modify: `core/content/passive_item_def.gd`
- Modify: `core/content/upgrade_def.gd`
- Modify: `core/content/wave_def.gd`
- Create: `core/content/wave_spawn_def.gd`
- Modify: `scenes/arena/spawner.gd`
- Modify: `scenes/ui/shop_panel/shop_panel.gd`
- Modify: `scenes/ui/upgrade_card/upgrade_card.gd`
- Modify: `tools/content/generate_default_pack.gd`
- Test: `tests/unit/test_content_pack.gd`
- Test: `tests/unit/test_tutorial_run_bridge.gd`

**Steps:**

1. Run `git diff --check` and review every current uncommitted file.
2. Add a failing test for a missing `WaveDef`, a wave with an unknown enemy ID, and a spawn with a null scene.
3. Run `test_content_pack.gd` and confirm the new cases fail.
4. Extend `ContentValidator` to reject those invalid references.
5. Guard `Spawner.spawn_enemy()` when both the new definition and legacy wave data are absent.
6. Regenerate `content_packs/default/pack.tres` and reimport with Godot 4.7.1.
7. Run the full suite and both clean-exit checks.
8. Use MCP to verify six character cards, eleven starting weapons, wave 1, and wave 10 configuration with zero runtime errors.
9. Commit locally:

```powershell
git add autoloads content_packs/default core/content scenes/arena/spawner.gd scenes/ui/shop_panel/shop_panel.gd scenes/ui/upgrade_card/upgrade_card.gd tests/unit tools/content
git commit -m "feat: expand and validate phase one content"
```

### Task 2: Add deterministic directors and transaction services

**Files:**

- Create: `core/directors/run_director.gd`
- Create: `core/directors/wave_director.gd`
- Create: `core/services/shop_service.gd`
- Create: `core/services/reward_service.gd`
- Create: `core/services/combat_resolver.gd`
- Modify: `core/state/run_state.gd`
- Modify: `autoloads/global.gd`
- Modify: `scenes/arena/arena.gd`
- Test: `tests/unit/test_run_director.gd`
- Test: `tests/unit/test_shop_service.gd`
- Test: `tests/unit/test_reward_service.gd`
- Test: `tests/unit/test_combat_resolver.gd`

**Steps:**

1. Write failing tests for the allowed phase sequence: selection → combat → upgrade → chest → shop → combat, with victory/death as terminal phases.
2. Write failing tests proving identical run seeds produce identical shop, reward, and wave selections.
3. Write failing rollback tests for insufficient materials, full weapon slots, max-stack passives, and invalid combinations.
4. Implement `RunDirector` as the sole phase-transition authority.
5. Implement one seeded `RandomNumberGenerator` stream per run and pass it to the services.
6. Move rarity selection, price calculation, lock/refresh, purchase, combine, and sale decisions out of `Global` and UI scripts into `ShopService`.
7. Implement `RewardService` queue operations without creating UI nodes.
8. Implement `CombatResolver` as pure damage/stat calculation with no scene dependency.
9. Keep temporary compatibility methods in `Global`, but make each method delegate to the new service.
10. Run all tests, clean exits, and MCP phase inspection.
11. Commit locally:

```powershell
git add core autoloads/global.gd scenes/arena/arena.gd tests
git commit -m "feat: add deterministic run and gameplay services"
```

### Task 3: Connect all sixteen stats and both aim modes to live combat

**Files:**

- Modify: `core/services/combat_resolver.gd`
- Modify: `core/adapters/tutorial_stats_adapter.gd`
- Modify: `scenes/unit/players/player.gd`
- Modify: `scenes/unit/players/weapon_container.gd`
- Modify: `scenes/weapons/weapon.gd`
- Modify: `scenes/weapons/melee/melee_behavior.gd`
- Modify: `scenes/weapons/range/range_behavior.gd`
- Modify: `scenes/components/health_component.gd`
- Modify: `project.godot`
- Test: `tests/unit/test_combat_resolver.gd`
- Test: `tests/scenes/test_player_combat.gd`

**Steps:**

1. Add failing unit tests for damage, melee/ranged/elemental scaling, attack speed, critical hit, armor, dodge, life steal, recovery, range, speed, luck, harvesting, and engineering.
2. Add failing Scene Runner tests for dash, nearest-target aiming, mouse-direction aiming, melee attack, ranged attack, and signal counts.
3. Implement the formulas in `CombatResolver`; clamp unsafe values such as negative cooldown and dodge above the design cap.
4. Make weapon cooldown, range, damage, projectile, and healing paths consume the run-owned `PlayerStats` values.
5. Route automatic targeting through the nearest valid enemy.
6. Route manual aiming through the current mouse world position while retaining automatic firing.
7. Add the aim-mode input/config binding without mutating static resources.
8. Run tests and use MCP input plus screenshots to verify both modes and dash.
9. Commit locally:

```powershell
git add core scenes project.godot tests
git commit -m "feat: connect stats and aim modes to combat"
```

### Task 4: Complete ten waves, difficulty scaling, and MouseDog

**Files:**

- Create: `content_packs/default/enemies/mouse_dog/mouse_dog.tscn`
- Create: `content_packs/default/enemies/mouse_dog/mouse_dog.gd`
- Create: `content_packs/default/enemies/mouse_dog/mouse_dog_attack_controller.gd`
- Modify: `scenes/arena/spawner.gd`
- Modify: `core/directors/wave_director.gd`
- Modify: `content_packs/default/pack.tres`
- Modify: `tools/content/generate_default_pack.gd`
- Test: `tests/unit/test_wave_director.gd`
- Test: `tests/scenes/test_mouse_dog.gd`
- Test: `tests/scenes/test_ten_wave_spawn_flow.gd`

**Steps:**

1. Add failing tests for the ten approved durations and each wave's allowed spawn set.
2. Add failing tests for all five health, damage, speed, and density multipliers.
3. Add failing tests that MouseDog appears once in wave 10 and limited reinforcements remain bounded.
4. Add failing tests for enrage below 50% health and below 65% on difficulty 5.
5. Implement `WaveDirector` scheduling and difficulty scaling without modifying `EnemyDef.stats`.
6. Build a dedicated MouseDog component scene and migrate its Unity attack behavior into Godot state logic.
7. Ensure death stops boss attacks, timers, and signals exactly once.
8. Run tests; use MCP to inspect the boss tree, collision layers, enrage transition, and runtime errors.
9. Commit locally:

```powershell
git add core/directors scenes/arena content_packs/default tools/content tests
git commit -m "feat: complete ten waves and MouseDog boss"
```

### Task 5: Complete upgrade, reward-box, shop, and inventory flow

**Files:**

- Create: `scenes/ui/reward_panel/reward_panel.tscn`
- Create: `scenes/ui/reward_panel/reward_panel.gd`
- Create: `scenes/ui/reward_card/reward_card.tscn`
- Create: `scenes/ui/reward_card/reward_card.gd`
- Modify: `scenes/ui/upgrade_panel/upgrade_panel.gd`
- Modify: `scenes/ui/shop_panel/shop_panel.gd`
- Modify: `scenes/ui/shop_card/shop_card.gd`
- Modify: `scenes/ui/item_card/item_card.gd`
- Modify: `scenes/arena/arena.tscn`
- Modify: `scenes/arena/arena.gd`
- Test: `tests/unit/test_shop_service.gd`
- Test: `tests/unit/test_reward_service.gd`
- Test: `tests/scenes/test_between_wave_flow.gd`

**Steps:**

1. Add failing tests for queued level-ups, multiple upgrade choices, chest ordering, claim, recycle, and empty queues.
2. Add failing tests for four shop offers, refresh cost, locking, luck rarity adjustment, six weapon slots, combine, 75% sale, and passive stacking.
3. Implement the reward panel as a view of `RewardService`; it must not own rewards.
4. Refactor upgrade and shop panels into views/controllers that call services and render returned results.
5. Remove direct inventory mutation, direct material deduction, and random selection from UI scripts.
6. Make the between-wave sequence drain every queued upgrade, then every chest, then open the shop.
7. Run tests and use MCP simulated input to purchase, lock, refresh, combine, sell, claim, and recycle.
8. Commit locally:

```powershell
git add core/services scenes/ui scenes/arena tests
git commit -m "feat: complete between-wave rewards and shop flow"
```

### Task 6: Complete title-to-settlement product flow

**Files:**

- Create: `scenes/ui/title/title.tscn`
- Create: `scenes/ui/title/title.gd`
- Create: `scenes/ui/difficulty_panel/difficulty_panel.tscn`
- Create: `scenes/ui/difficulty_panel/difficulty_panel.gd`
- Create: `scenes/ui/pause_panel/pause_panel.tscn`
- Create: `scenes/ui/pause_panel/pause_panel.gd`
- Create: `scenes/ui/settlement_panel/settlement_panel.tscn`
- Create: `scenes/ui/settlement_panel/settlement_panel.gd`
- Modify: `scenes/ui/selection_panel/selection_panel.tscn`
- Modify: `scenes/ui/selection_panel/selection_panel.gd`
- Modify: `scenes/arena/arena.tscn`
- Modify: `scenes/arena/arena.gd`
- Modify: `project.godot`
- Test: `tests/scenes/test_full_run_victory.gd`
- Test: `tests/scenes/test_full_run_death.gd`

**Steps:**

1. Write failing Scene Runner tests for title → character → weapon → difficulty → combat.
2. Write a fixed-seed, accelerated-frame failing test for wave-10 victory.
3. Write a failing test for death at an arbitrary wave and restart to a fresh run.
4. Implement title, difficulty, pause, victory, death, and settlement panels.
5. Make wave 10 completion enter victory instead of opening another upgrade/shop cycle.
6. Make player death enter death exactly once and stop combat/spawn timers.
7. Display character, difficulty, wave, materials, elapsed time, and result in settlement.
8. Run the suite and perform two consecutive MCP-controlled runs without restarting the editor.
9. Commit locally:

```powershell
git add scenes project.godot tests/scenes
git commit -m "feat: complete phase one game loop and settlement"
```

### Task 7: Integrate saves, unlocks, settings, and translations

**Files:**

- Modify: `core/save/local_save_provider.gd`
- Modify: `core/state/meta_progress.gd`
- Modify: `core/directors/run_director.gd`
- Create: `scenes/ui/settings_panel/settings_panel.tscn`
- Create: `scenes/ui/settings_panel/settings_panel.gd`
- Create: `content_packs/default/i18n/game.zh_CN.po`
- Create: `content_packs/default/i18n/game.en.po`
- Modify: `content_packs/default/pack.tres`
- Modify: `project.godot`
- Test: `tests/unit/test_difficulty_and_save.gd`
- Test: `tests/unit/test_translation_contract.gd`
- Test: `tests/scenes/test_save_restart_flow.gd`

**Steps:**

1. Add failing tests for `user://save/packs/potato_default/save_v1.json`, atomic temp replacement, `.bak` recovery, and corrupt-primary recovery.
2. Add failing tests for difficulty 1 being initially open, sequential unlocks, and per-character highest clear.
3. Add failing tests for Chinese default, English switch, missing-key English fallback, and an explicit warning.
4. Add failing tests for music, SFX, fullscreen, resolution, and aim-mode persistence.
5. Wire save/load to run settlement and application startup.
6. Implement the settings panel and audio buses.
7. Register translations from the mounted content pack and replace user-visible hardcoded strings with keys.
8. Verify save restart with Scene Runner and MCP.
9. Commit locally:

```powershell
git add core content_packs/default scenes/ui/settings_panel project.godot tests
git commit -m "feat: add progression saves settings and localization"
```

### Task 8: Build and validate the restricted default content PCK

**Files:**

- Modify: `core/content/bootstrap_content_loader.gd`
- Modify: `core/content/content_validator.gd`
- Create: `tools/content/validate_content_pack.gd`
- Create: `tools/build_content_pack.ps1`
- Create: `export_content_presets.cfg`
- Modify: `.gitignore`
- Test: `tests/unit/test_content_pack_security.gd`
- Test: `tests/integration/test_external_content_pack.gd`

**Steps:**

1. Add failing tests for duplicate IDs, missing references, scripts, native binaries, absolute paths, `..` traversal, and core-path replacement attempts.
2. Add a failing integration test that starts with only the generated `default_content.pck` mounted using `replace_files=false`.
3. Strengthen `ContentValidator` and scene-contract validation.
4. Build the content pack from `content_packs/default/` only.
5. Keep gameplay scripts, addons, and tests out of the content PCK.
6. Replace the PCK with a test fixture pack and prove the core starts without code changes.
7. Run validation, tests, and clean exits.
8. Commit locally:

```powershell
git add core/content tools export_content_presets.cfg .gitignore tests
git commit -m "feat: build restricted default content pack"
```

### Task 9: Add lifecycle, stress, and regression gates

**Files:**

- Create: `tests/scenes/test_two_run_lifecycle.gd`
- Create: `tests/scenes/test_collision_contracts.gd`
- Create: `tests/performance/test_combat_stress.gd`
- Create: `tools/run_phase_one_acceptance.ps1`
- Modify: `tools/check_clean_exit.ps1`

**Steps:**

1. Add collision-contract tests for player, enemy, friendly attack, hostile attack, pickup, and world layers.
2. Add a two-run test checking signal counts, freed nodes, resources, and stable memory after teardown.
3. Add a 1080p stress scene with 250 enemies and 200 projectiles.
4. Measure a stable sampling window and fail below 55 average FPS on the target Windows machine.
5. Make `run_phase_one_acceptance.ps1` run import, validation, PCK build, full GdUnit, clean exits, two-run lifecycle, and stress tests in order.
6. Use MCP for the required scene tree → play → errors → input → screenshot → stop sequence.
7. Commit locally:

```powershell
git add tests tools
git commit -m "test: add phase one lifecycle and performance gates"
```

### Task 10: Export desktop builds and stop at the playtest gate

**Files:**

- Create: `export_presets.cfg`
- Create: `tools/build_release.ps1`
- Create: `.github/workflows/phase-one.yml`
- Modify: `docs/THIRD_PARTY.md`
- Create: `docs/phase-one-playtest.md`

**Steps:**

1. Configure Windows, Linux, and macOS core exports excluding MCP, GdUnit4, tests, and reports.
2. Assemble each release directory with the core executable/PCK and `default_content.pck`.
3. Add CI jobs for import, validation, GdUnit, and native export; publish JUnit/HTML reports on Ubuntu.
4. Run the complete local acceptance script and retain its report paths.
5. Smoke-test the Windows release outside the project directory.
6. Verify the release has no Unity cloud endpoint, XLua, Addressables, MCP, GdUnit4, or test content.
7. Record the exact build SHA-256 values and known balance notes.
8. Commit locally:

```powershell
git add export_presets.cfg tools/build_release.ps1 .github docs
git commit -m "build: package phase one desktop releases"
```

9. Do not begin Phase 2. Deliver the Phase 1 build and wait for user feedback on balance and game feel.

---

## Phase One definition of done

Phase 1 is complete only when all of the following are evidenced in the same final acceptance run:

- All six characters and eleven weapon families can start a run.
- Ten-wave victory and arbitrary-wave death both reach settlement.
- Upgrade queues, reward boxes, shop, backpack, combine, sale, locks, and refresh work through services.
- Five difficulties apply approved multipliers and unlock sequentially per character.
- MouseDog has its own scene, attacks, single-spawn rule, death cleanup, and difficulty-aware enrage threshold.
- Local save, backup recovery, settings, Chinese, and English survive restart.
- Replacing the default content PCK requires no core-code modification.
- Full GdUnit, Scene Runner, content validation, clean exit, two-run lifecycle, and performance gates pass.
- Windows, Linux, and macOS exports are produced without development addons or tests.
- A Windows build is provided for user playtesting, and Phase 2 remains paused.
