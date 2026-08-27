# Task 3 review-fix report — local hitstop and lethal player-hit lifecycle

**Status:** DONE

**Branch/worktree:** `codex/full-static-assets-runtime` in `E:\01_gobro\.worktrees\full-static-assets-runtime`, fixing reviewed HEAD `9b14090a64e91c6ffa470a99f863e8c38e7290bc`.

## Outcome

- Fixed the final-delta boundary by latching whether the current actor physics phase is frozen before decrementing the remaining clock. `debug_local_hitstop_remaining()` continues to report the continuous countdown, while `is_combat_simulation_frozen()` remains true for the actor phase that consumes the final remainder and releases on the next world tick.
- Added real projectile boundary coverage at both 60 Hz and 30 Hz. A `0.025` request can no longer resume combat simulation early or freeze zero actor frames.
- Preserved lethal `player_hit` feedback, camera impulse, and the `0.040` local freeze instead of synchronously erasing them from the `died` callback.
- Lethal cleanup still immediately retires active enemies and projectiles. `GameSession.fail_run()` and `run_failed` are committed only after the terminal local-freeze actor phase completes, so settlement routing cannot erase the hit before it is presented.
- Kept ordinary `_clear_active_combat_actors()` behavior as the default: it cancels pending terminal routing, clears hitstop state, clears presenter slots, and clears camera impulse. Only the explicit lethal cleanup path preserves terminal feedback.
- Fixed the Task 6 factory-signature drift in `test_weapon_archetype_runtime.gd` by passing the explicit preview flag. The suite now parses and actually executes all five tests.
- Hardened `tools/run_tests.ps1` so discovery script errors or zero discovered cases cannot be reported as a successful test run.
- No `Engine.time_scale` or tree-pause mutation was introduced. Task 1 enemy visuals and Task 6 release-content paths remain unchanged.

## TDD evidence

### Important 1 — final hitstop delta

**RED:** the new 30/60 Hz projectile boundary test produced four expected assertions: at 60 Hz the second actor phase moved and reported unfrozen, and at 30 Hz the first actor phase moved and reported unfrozen.

**GREEN:** the actor-phase latch made the focused runtime suite pass `30/30` at that checkpoint and `31/31` after the lethal lifecycle test was added.

### Important 2 — lethal feedback lifecycle

**RED:** the integrated lethal test produced twelve expected assertions showing synchronous `run_failed`, an already-ended session, zero hitstop, no player-hit slot, and no camera impulse immediately after damage and through the intended freeze window.

**GREEN:** the same test now proves immediate enemy/projectile retirement, `0.040` preserved hitstop, live player-hit/camera feedback through the terminal freeze, delayed `run_failed`, and default clear semantics. The full runtime-correctness suite passes `31/31`.

### Important 3 — weapon-suite discovery

**RED:** the targeted weapon suite reported `Too few arguments for _weapon_definition()` at line 195, followed by `No test cases found`; the wrapper could finish with shell exit `0`.

**GREEN:** the call now passes `true`, the suite executes `5/5`, and an intentional missing-suite probe exits `1` after the wrapper detects zero discovered cases.

## Focused and related verification

- `test_combat_runtime_correctness.gd`: **31/31**.
- `test_combat_event_publication.gd`: **8/8**.
- `test_combat_feedback_presenter.gd`: **9/9**.
- `test_static_preview_content_factory.gd`: **4/4**.
- `test_weapon_archetype_runtime.gd`: **5/5**.
- `test_enemy_actor_visual.gd`: **2/2**.
- `test_brotato_combat_hud.gd`: **6/6**.
- `test_pause_overlay.gd`: **4/4**.
- `test_static_asset_runtime_service.gd`: **29/29**.
- `full_static_assets_combat_v1_smoke.gd`: **2/2**, emitted `FULL_STATIC_ASSETS_COMBAT_V1_OK`.
- `git diff --check`: clean.

## Full-suite observation

An additional `res://tests` run discovered 357 cases and recorded five failure assertions, all outside the files and contracts changed here:

- `test_smoke_shell_helmet_install.gd`: two accepted-artifact dimension/hash assertions (`256x256` expected versus installed `64x64`, plus hash mismatch).
- `test_static_item_redraw_integration.gd`: three accepted-artifact/canonical-manifest hash assertions.

The focused Task 3 suites, Task 1 enemy-visual regression, Task 6 preview/release runtime suites, HUD/pause regressions, and full-static combat smoke all pass. These unrelated static-item artifact baselines were not modified as part of the review fix.

## Concerns

- No Task 3 review blocker remains.
- The unrelated full-suite static-item artifact/hash failures above remain for the owning asset task to reconcile.
