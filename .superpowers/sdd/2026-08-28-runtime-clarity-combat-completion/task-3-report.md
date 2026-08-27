# Task 3 report — local hitstop and player-hit feedback

**Status:** DONE

**Branch/worktree:** `codex/runtime-hitstop` in `E:\01_gobro\.worktrees\runtime-hitstop`, based on `f293e7ad5344b04367835185cb11c9f27b37f642`.

## Outcome

- Added a `CombatWorld`-owned local hitstop clock with public request/frozen queries and a test-visible remaining-time query.
- Requests clamp to `0.025–0.060` seconds and coalesce by maximum. The clock advances from `CombatWorld._physics_process` without touching `Engine.time_scale` or `SceneTree.paused`.
- Player, enemy, weapon, and projectile physics callbacks now return before their first simulation mutation while local combat simulation is frozen. The world clock, wave timer, HUD publication, feedback presenter, camera, and pause-input path remain outside that gate.
- Contact timing is deterministic and priority ordered: explosion `0.060`, critical `0.045`, rifle/heavy `0.035`, otherwise `0.025`. Real player health reduction requests `0.040`.
- Added typed player `damage_taken(integer_global_position, final_damage, remaining_health, lethal, sequence)`. It publishes only after actual non-dodged, non-invulnerable health loss, increments monotonically, and preserves the existing `health_changed` before `died` ordering.
- Routed player damage into one short red/white `player_hit` slot in the existing fixed 96-slot presenter pool plus a bounded deterministic camera impulse.
- Changed only `community_tapper` attack range from `420.0` to `88.0`; its internal ID, melee mode, name, damage, cooldown, projectile speed, knockback, price, feedback profile, and impact kind remain fixed by regression tests.
- Preserved Task 1 enemy authored-texture setup and circle fallback; `enemy_actor.gd` only gained the early local-freeze gate in its physics callback.

## TDD evidence

The tests were written before production changes and observed failing for the intended missing behavior.

### RED

- `test_combat_runtime_correctness.gd`: 29 cases, 8 expected failures across missing request/query APIs, four-actor freeze behavior, duration matrix, and player damage routing.
- `test_combat_event_publication.gd`: 8 cases, 3 expected failures for the missing typed signal and damage ordering behavior.
- `test_combat_feedback_presenter.gd`: 9 cases, 1 expected failure for the missing bounded player-hit slot.
- `test_static_preview_content_factory.gd`: 4 cases, 1 expected failure because range was still `420.0`.
- The first attempted RED run required a one-time headless editor import so GdUnit and imported textures were registered; after import, the failures above were functional rather than harness errors.

### GREEN

- `test_combat_runtime_correctness.gd`: 29/29.
- `test_combat_event_publication.gd`: 8/8.
- `test_combat_feedback_presenter.gd`: 9/9.
- `test_static_preview_content_factory.gd`: 4/4.
- A mutation check temporarily removed melee hitstop routing; the new real-melee assertion failed with remaining time `0.000` instead of `0.035`, then passed after restoring the production line.

## Regression verification

- `test_enemy_actor_visual.gd`: 2/2, proving Task 1 authored sprites, nearest filtering, fallback, and collision radius remain intact.
- `test_weapon_archetype_runtime.gd`: 5/5 after changing the single approved range expectation to `88.0`; the table still freezes every other weapon field.
- `test_brotato_combat_hud.gd`: 6/6.
- `test_pause_overlay.gd`: 4/4.
- `full_static_assets_combat_v1_smoke.gd`: 2/2, `FULL_STATIC_ASSETS_COMBAT_V1_OK`.
- Direct `item_appearance_v2_smoke.gd`: `ITEM_APPEARANCE_V2_SMOKE_OK overlays=2`; the smoke now advances the world-owned 40 ms hitstop before expecting the player flash's simulation timer to expire.
- Complete `tools/run_tests.ps1`: **355/355 cases**, 36/36 suites, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans.
- Headless Godot editor import: exit 0.
- `git diff --check`: clean.

## Self-review and mutation coverage

- Removing any one of the four actor freeze gates mutates a separately asserted position/cooldown/timer/velocity/lifetime value.
- Wrong min/max/coalescing logic, global-time mutation, or failure to decrement the local clock breaks the local-clock test.
- Wrong profile/impact priority breaks literal duration-table cases; missing melee routing breaks the real melee mutation assertion.
- Publishing on dodge/invulnerability, skipping a real hit, resetting/non-incrementing sequence, changing integer position, or moving the new event outside `health_changed -> damage_taken -> died` breaks player event tests.
- Allocating a second feedback pool, losing red/white primitives, accepting duplicate player-hit sequence, or omitting camera impulse breaks presenter tests.
- Any `community_tapper` ID/mode/value drift beyond the approved range change breaks the preview factory or 12-weapon archetype table.

## Concerns

- No task-blocking concern remains.
- The full suite retains pre-existing `screen_base.gd` non-equal-anchor warnings in menu/combat routes and the intentional reward-token collision warning exercised by `test_combat_event_publication.gd`; all suites exit cleanly.
- Task 3 brief/design/plan were present only in the concurrently modified `full-static-assets-runtime` worktree, so they were read there without modifying it. All Task 3 edits and test execution stayed in the dedicated `runtime-hitstop` worktree.
