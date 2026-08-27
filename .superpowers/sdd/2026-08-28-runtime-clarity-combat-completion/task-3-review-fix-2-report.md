# Task 3 residual review-fix report — irreversible lethal run state

**Status:** DONE

**Branch/worktree:** `codex/full-static-assets-runtime` in `E:\01_gobro\.worktrees\full-static-assets-runtime`, based on `bd867b0a96f43e6a4ab96a8ef9d7087d307199f7`.

## Residual finding

The first review fix delayed both the durable session failure and the presentation route. During that terminal-feedback window, `CombatWorld.running` was false but `session.run_state.ended` was still false. The pause-menu restart route could therefore construct another combat screen whose `start_wave()` passed its existing `ended` guard; the default clear then erased pending terminal feedback and canceled the delayed failure. Exiting the old world also canceled the pending state before the session was made terminal.

## Fix

- `_on_player_died()` now prepares the terminal pending route and preserves the 40 ms hitstop/feedback, then calls `GameSession.fail_run()` synchronously in the same guarded death commit.
- `_commit_pending_run_failure()` now publishes only `run_failed`; it no longer mutates the session.
- `_wave_transition_committed` keeps repeated `died` callbacks as no-ops, so `fail_run`, `run_ended`, and `run_failed` each publish at most once on their intended timelines.
- The existing `start_wave()` `run_state.ended` guard now immediately rejects restart attempts without entering default clear, so hitstop, the player-hit slot, camera impulse, and pending route remain intact.
- If the world exits during the presentation window, `_exit_tree()` may cancel the local pending route without reviving the already-failed session. No reentrant route signal was added to `_exit_tree()`.

## TDD evidence

### RED

The expanded lethal lifecycle test and a new exit-window integration test ran against `bd867b0` first. The focused suite executed 32 cases and produced 19 expected assertion failures:

- `run_ended` had not published and `run_state.ended` was false immediately after lethal damage.
- `start_wave()` returned `OK` instead of `ERR_INVALID_PARAMETER`, then cleared remaining hitstop, the player-hit slot, and camera impulse.
- Re-entering death/routing after that restart violated the intended single-publication timeline.
- Freeing the world before delayed routing left the session alive, and a replacement world could start the same run.

The other 30 focused cases passed in the RED run.

### GREEN

The production change is one lifecycle move: synchronous `fail_run()` in the guarded death commit and removal of the delayed duplicate call. The focused runtime suite passes **32/32**.

The tests now prove:

- session failure and `run_ended(false)` happen immediately and exactly once;
- restart is rejected without clearing terminal hitstop or feedback;
- `run_failed` remains delayed until after the local-freeze actor phase and emits exactly once;
- repeated death callbacks are no-ops;
- leaving the world before route publication cannot revive or restart the failed run.

## Related verification

- `test_combat_runtime_correctness.gd`: **32/32**.
- `test_combat_event_publication.gd`: **8/8**.
- `test_combat_feedback_presenter.gd`: **9/9**.
- `test_pause_overlay.gd`: **4/4**.
- `test_weapon_archetype_runtime.gd`: **5/5**.
- `test_static_preview_content_factory.gd`: **4/4**.
- `test_enemy_actor_visual.gd`: **2/2**.
- `test_static_asset_runtime_service.gd`: **29/29**.
- `full_static_assets_combat_v1_smoke.gd`: **2/2**, emitted `FULL_STATIC_ASSETS_COMBAT_V1_OK`.

## Worktree isolation

Concurrent edits already existed in `tests/unit/test_smoke_shell_helmet_install.gd` and `tests/unit/test_static_item_redraw_integration.gd`. They were preserved and excluded from this fix's staging and commit. No stash was read or modified.

## Concerns

- No residual Task 3 blocker remains in the tested lifecycle.
