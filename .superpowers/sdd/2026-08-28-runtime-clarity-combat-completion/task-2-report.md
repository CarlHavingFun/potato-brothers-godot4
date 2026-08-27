# Task 2 Report: Unified Four-State Shop and Upgrade Commands

**Status:** DONE

## Scope completed

- Routed `ShopScreen._shop_button` through inherited `configure_action_button`.
- Routed `UpgradeScreen` reroll through the same inherited helper.
- Kept the existing command dimensions and 20 px font overrides after helper configuration:
  - shop reroll `216x48`
  - shop lock/unlock `216x44`
  - shop continue `265x44`
  - upgrade reroll `240x48`
- Preserved the existing focus metadata, disabled/focus-mode branches, focus restoration, and one callback connection per command.
- Kept shop offer cards and upgrade choice cards on their existing rarity-card `StyleBoxFlat` treatment. No borders or layout frames were added.

## TDD evidence

### RED

Strengthened `tests/unit/test_static_menu_consumers.gd` before production changes. The focused suite failed in the real shop/upgrade route test because Lock, shop Reroll, Continue, and upgrade Reroll did not expose `StyleBoxTexture` state overrides. Result: `10` cases executed, `1` failing case with `28` expected state assertions failing, exit `100`.

### GREEN

After the minimal helper-routing changes, the same focused suite passed `10/10`, with `0` errors and `0` failures.

The unit and route-smoke assertions now verify:

- `normal`, `hover`, `pressed`, and `disabled` are `StyleBoxTexture` instances;
- each state points to the matching `four_state_button` selector in the active snapshot;
- the four state textures are distinct;
- shop offer cards and upgrade choice cards retain flat rarity-card styleboxes.

## Verification

- `tools/run_tests.ps1 -TestPath res://tests/unit/test_static_menu_consumers.gd`: `10/10` passed.
- `tools/run_tests.ps1 -TestPath res://tests/integration/full_static_assets_menu_v1_smoke.gd`: `1/1` passed; `FULL_STATIC_ASSETS_MENU_V1_OK captures=7`.
- `tools/run_tests.ps1 -TestPath res://tests/unit/test_brotato_structured_screens.gd`: `33/33` passed, including shop buy/lock/reroll state mutation, callback behavior, continue flow, and focus-restoration coverage.
- Godot 4.7 headless editor import: exit `0`.
- `git diff --check`: clean.

The Godot runs retain pre-existing non-equal-anchor warnings in shared screen chrome. Import also regenerated five untracked `.uid/.import` cache files; they were removed and are not part of this task.

## Files in this task

- `game/ui/shop_screen.gd`
- `game/ui/upgrade_screen.gd`
- `tests/unit/test_static_menu_consumers.gd`
- `tests/integration/full_static_assets_menu_v1_smoke.gd`
- `.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/task-2-report.md`
