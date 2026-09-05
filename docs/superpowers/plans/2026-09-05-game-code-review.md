# Game code review and targeted fixes

**Goal:** Review the current runtime and fix reproduced defects without changing content, balance values, or the saved profile schema.

**Baseline:** `1665538`, Godot 4.7.1. Existing untracked UID/import files belong to the starting workspace. All Godot tests run serially through the isolated test entry point.

## Work

- [x] Run the existing complete GdUnit suite and inspect failures, skips, and leaks.
- [x] Review combat actors/projectiles independently; verify findings against callers and tests.
- [x] Reproduce ignored chaser/shooter knockback using real actor damage and movement; add the missing impulse to those roles without altering charger timing.
- [x] Reproduce malformed settings publication; validate known field types before publishing any loaded value, preserving sparse-file compatibility and the existing path.
- [x] Measure redundant HUD theme notifications; avoid applying an unchanged timer color and verify the 10-second danger transition.
- [x] Reproduce and fix missed contacts between weapon socket and muzzle, preserving visible launch position and shared piercing limits.
- [x] Reproduce and bound unsafe spawn relocation for impossible arena geometry, releasing pending actors.
- [x] Run focused regressions, full GdUnit, editor parsing, and the existing deterministic progression smoke as applicable. Record actual coverage limits, including the missing legacy stress scene.
- [x] Obtain an independent final diff review and record results in a review report.

Implementation uses the existing GDScript services and GdUnit framework. Each defect gets a failing behavior test before its minimal production fix. No new gameplay feature or engine upgrade is part of this pass.
