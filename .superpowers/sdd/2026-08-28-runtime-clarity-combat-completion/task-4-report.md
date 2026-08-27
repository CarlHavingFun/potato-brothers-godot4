# Task 4 report — exact-once magnetic pickups

**Status:** DONE

**Implementation commit:** `4c7b3a5` (`feat(combat): add exact-once magnetic pickups`)

**Branch/worktree:** `codex/full-static-assets-runtime` in `E:\01_gobro\.worktrees\full-static-assets-runtime`, resumed from Task 3 fix commit `2d1054e`.

## Outcome

- Added `GogoCombatPickup` and a dedicated `CombatWorld/PickupLayer` with the required `DROPPED -> MAGNETIZING -> COLLECTED` lifecycle.
- Enemy death now reserves XP and supply in the existing reward ledger, then spawns exactly one pickup for each non-zero reserved reward. The canonical enemy-death path no longer applies rewards immediately.
- Pickup placement uses a deterministic small integer offset derived from the enemy and pickup runtime IDs. Movement reads the player's live `pickup_range`, accelerates smoothly, and uses a fixed 18 px contact radius.
- Collection commits `COLLECTED` before calling `GameSession.apply_reserved_reward`. The world unregisters the pickup before applying, emits `pickup_collected` only for `APPLIED`, and makes repeated or reentrant collection attempts side-effect free.
- Missing pickup textures use a procedural fallback and remain collectible. Real `experience_pickup` and `supply_pickup` textures use nearest filtering and register the dynamic pickup script as their actual consumer.
- Wave completion auto-collects live pickups in stable runtime-ID order, emits the final post-collection HUD snapshot, then finishes the wave.
- Removed decorative XP and supply props from `StaticWorldPresenter`; retained `medical_pickup` as non-interactive scenery.
- Preserved Task 3 actor-phase local hitstop, immediate lethal session failure with delayed `run_failed` feedback transition, and the ban on global time mutation. Preserved Task 1 authored enemy visuals and the Task 6 static snapshot.
- Retained `commit_enemy_reward_snapshot` only as the existing legacy immediate adapter. No live enemy-death path calls it.

## TDD evidence

Tests were introduced in small RED -> GREEN cycles for layer/state creation, deterministic pop offsets, live-range magnetic motion, reserve-without-apply spawning, exact-once collection, missing-texture fallback, real dynamic asset consumption, enemy death routing, stable wave-end collection, and static presenter removal.

Notable observed RED results:

- Initial pickup tests failed while `PickupLayer`, `combat_pickup.gd`, deterministic offsets, configuration, movement, spawn, and collection APIs were absent.
- Enemy-death/event tests failed while rewards still applied immediately.
- Static presenter tests failed while decorative XP/supply nodes remained.
- The positive dynamic-visual test failed with no `StaticVisual` before the real texture branch was restored.
- A fixed-contact mutation removed both contact checks: the 18 px boundary case stayed `DROPPED`, two pickups remained active, and XP stayed zero. Restoring the fixed-radius checks made the 18.00/18.01 boundary test pass.
- Full-suite RED after static prop removal exposed exactly seven stale coverage assertions: 68/70 and unresolved XP/supply. The fixture was migrated through the real `CombatWorld` reserve -> dynamic spawn path, restoring 70/70 without synthetic observations.
- Task 3 feedback regression initially retained four old immediate-reward assertions. It was migrated to assert death-time reservation/live pickups first and reward application only after canonical collection, while preserving the original muzzle/contact/death and duplicate-feedback checks.

## Final verification

- Task 4 focused plus Task 1/Task 3 regressions: **101/101**, 12/12 suites, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans.
- Complete Godot test suite: **368/368**, 37/37 suites, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans.
- Combat smoke: **2/2**, `FULL_STATIC_ASSETS_COMBAT_V1_OK`; dynamic XP/supply pickups were created with real textures, observed live, and collected through the canonical event. Static asset coverage remained **70/70**.
- Exact-once pickup suite: **9/9**.
- Task 3 combat runtime correctness: **32/32**.
- Event publication: **8/8**.
- Combat feedback presenter: **9/9**.
- Static presenter: **9/9**.
- Static coverage audit: **7/7**, 70/70 units.
- Reward ledger: **6/6**.
- `git diff --check`: clean before commit.

## Concerns

- No task-blocking concern remains.
- The test routes retain pre-existing non-equal-anchor warnings from `screen_base.gd` and intentional reward-token collision warnings in ledger/event tests; all commands exit successfully.
- Headless combat capture reports `capture=headless-unavailable`, as before, while still running the live route, dynamic pickup assertions, and 70/70 consumer coverage.
