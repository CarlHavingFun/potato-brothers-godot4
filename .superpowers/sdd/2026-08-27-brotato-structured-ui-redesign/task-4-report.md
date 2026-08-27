# Task 4 Report — Structured Setup Selection Flow

Date: 2026-08-28

Worktree: `E:\01_gobro\.worktrees\full-static-assets-runtime`

Branch: `codex/full-static-assets-runtime`

Starting base: `df0b8c113b90281bfedb8ebd80be3ad8bc750519`

Commit: focused commit containing this report, message `feat: rebuild structured setup selection flow` (final SHA is reported in the parent-task handoff; from this branch it is `git rev-parse HEAD`).

## Outcome

Task 4 is complete.

- Character selection exposes exactly one real Niko option and uses the first texture from Niko's real `SpriteFrames` animation for both detail and roster previews.
- Weapon selection exposes all 12 canonical CS options from the content snapshot, with real nearest-filtered icons or readable fallbacks and a dense selected-weapon detail view.
- Difficulty selection exposes exactly the one real Standard difficulty, with the canonical badge fallback and all four canonical multipliers.
- The three screens share a low-border 1280x720 setup language: top-left back control, centered title/subtitle, dark translucent content regions, one-pixel selection outlines, light selected fills, and bottom option strips.
- Selection is immediate. Niko advances to weapon, weapon advances to difficulty, and Standard creates the session and advances to combat.
- Existing internal values and IDs, `selection_draft`, back routes, default zone, and session creation are preserved.
- No fake random, locked, placeholder character, weapon, or difficulty options were added.

## Canonical content covered

- Character: `character.niko:character/niko`
- Difficulty: `gogobro.core:difficulty/standard`
- Weapons:
  - `weapon.training_blade:weapon/training_blade`
  - `weapon.training_blaster:weapon/training_blaster`
  - `gogobro.preview:weapon/community_tapper`
  - `gogobro.preview:weapon/wood_stock_assault_rifle`
  - `gogobro.preview:weapon/heavy_bolt_sniper`
  - `gogobro.preview:weapon/suppressed_carbine`
  - `gogobro.preview:weapon/suppressed_tactical_pistol`
  - `gogobro.preview:weapon/heavy_hand_cannon`
  - `gogobro.preview:weapon/box_submachine_gun`
  - `gogobro.preview:weapon/compact_submachine_gun`
  - `gogobro.preview:weapon/bullpup_pdw`
  - `gogobro.preview:weapon/folding_stock_submachine_gun`

Tests compare the complete weapon ID set and the complete display-name set, require uniqueness, and check each option against its canonical definition.

## Files changed

- `game/ui/character_select_screen.gd`
- `game/ui/weapon_select_screen.gd`
- `game/ui/difficulty_select_screen.gd`
- `tests/unit/test_brotato_structured_screens.gd`
- `tests/unit/test_static_menu_consumers.gd`
- `tests/integration/full_static_assets_menu_v1_smoke.gd`
- `.superpowers/sdd/2026-08-27-brotato-structured-ui-redesign/task-4-report.md`

Stale assertions for the obsolete setup `ZoneThumbnail`, `Body`, and `WeaponCardGrid` structure were replaced with assertions for the real Task 4 hierarchy. Main-menu `ContentRoot/Body` checks remain intentionally unchanged because that route was not part of Task 4.

## TDD evidence

The first attempt to run `tools/run_tests.ps1` without an explicit Godot path failed before test discovery because Godot was not on `PATH`; this was environment setup, not counted as RED. All recorded cycles used:

`E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe`

### Initial layout and behavior RED

Command:

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/setup-layout-red-selected
```

Result: 32 cases discovered; the new setup assertions produced 2 errors and 26 failures because the old routes did not expose the required Task 4 nodes or behavior.

### Initial implementation GREEN

The first implementation run found a GDScript parse error caused by inferred `Variant` values from `Dictionary.get`; explicit `bool` and `StringName` typing fixed the root cause. The next run at `reports/setup-layout-green-2` passed 32/32.

### Preview-selected state RED/GREEN

- RED: `reports/setup-preview-red` — 33 cases, 2 expected failures because the Niko cell and default weapon preview were not visibly selected before committing the draft.
- GREEN: `reports/setup-layout-green` — 33/33 after adding preview selection without writing `selection_draft`.

### Localized weapon detail RED/GREEN

- RED: `reports/setup-localization-red` — the canonical weapon loop exposed raw internal tokens such as `ballistic`, `melee`, `pierce_exit`, and `critical`.
- GREEN: `reports/setup-localization-green` — 33/33 after mapping canonical values to readable Chinese labels while preserving the internal values.

### Deterministic low-border back control RED/GREEN

- RED: `reports/setup-back-red` — 7 cases, 3 failures because all three setup back buttons inherited authored `StyleBoxTexture` states.
- GREEN: `reports/setup-back-green` — 7/7 after replacing those states with flat one-pixel styles.
- A later uncached 1:1 screenshot inspection exposed an intermittent missing weapon-route back visual even though the node, rect, and style assertions passed. Additional RED passes (`reports/task4-back-layer-red`, `reports/task4-back-visual-red`, `reports/task4-back-sibling-red`, and `reports/task4-back-wrapper-final-red`) drove an explicit flat visual layer plus transparent top-layer hit target.
- Final GREEN: `reports/task4-back-wrapper-final-green` — 7/7, and the subsequent real windowed capture visibly shows the control on all three routes.

### Final focused GREEN

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -TestPath res://tests/unit/test_brotato_structured_screens.gd -ReportDir reports/task4-final-structured-ids
```

Result: 33/33, 0 errors, 0 failures, 0 skipped, 0 orphans.

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -TestPath res://tests/unit/test_static_menu_consumers.gd -ReportDir reports/task4-back-wrapper-final-green
```

Result: 7/7, 0 errors, 0 failures, 0 skipped, 0 orphans.

The focused coverage includes exact node paths, Niko-only count, real first-frame preview, complete canonical ID/name sets, weapon mode/damage/cooldown/range/projectile-speed/knockback/damage-kind/impact-kind details, Standard-only difficulty and multipliers, nearest filtering, readable fallbacks, selected and preview-selected states, one-pixel border budget, native-frame fit, back routes, draft persistence, session creation, and combat routing.

## Real-route integration and captures

Command:

```powershell
cmd.exe /c "addons\gdUnit4\runtest.cmd --godot_binary E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe -c -a res://tests/integration/full_static_assets_menu_v1_smoke.gd"
```

Final result: 1/1 passed in a real windowed OpenGL run on NVIDIA hardware. The test clicks the actual Niko, Glock-18, and Standard buttons; validates the draft and route after each click; validates session creation; and continues through the real combat/shop/upgrade route.

Manifest:

`C:\Users\18421\AppData\Roaming\GOGOBRO\full-static-assets-menu-v1\route-captures-v1.json`

Task 4 captures and SHA-256:

- `character-select-1280x720.png` — `797a3845ff97e503653910f084f8f745248956dcb56b7d425bffebf413361905`
- `weapon-select-1280x720.png` — `1257769976f95efe132def20f47aa542e9e306a578d7fd03c48d16a4508c9dbc`
- `difficulty-select-1280x720.png` — `a933fa73e851a8507f0fc733186180b99a4d21a1bf042f63d6a6f47f5b31ab45`

All three were copied to unique paths and inspected at original 1280x720 resolution to avoid image-preview caching.

### 1:1 inspection findings

- Character: top-left back and centered title are visible; the large Niko silhouette is recognizable with clean nearest-filtered edges; stats are readable; exactly one light-selected 72px Niko cell appears in the bottom strip; no giant page slab or nested border wall.
- Weapon: top-left back is visible in the final uncached image; the Niko summary, selected weapon silhouette, and dense canonical detail are readable; all 12 weapon cells fit across the bottom strip with recognizable icons and clean nearest-filtered edges; the preview-selected cell uses the light fill.
- Difficulty: top-left back is visible; Niko, Glock-18, and Standard badge summaries are clear; all four 100% multipliers are readable; exactly one light-selected Standard badge cell appears in the bottom strip.
- Across all three screens, the illustrated magenta-derived GOGOBRO background remains visible and the layout does not force coarse pixels or large artificial color blocks.

## Full-suite verification

Final command after the exact canonical-ID assertions were added:

```powershell
tools\run_tests.ps1 -GodotBinary 'E:\01_gobro\.tools\godot-4.7.1\Godot_v4.7.1-stable_win64.exe' -ReportDirectory res://reports/task4-full-final-ids
```

Result: 35/35 suites, 329/329 cases, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans; 38.483 seconds. Exit code 0.

Report: `reports/task4-full-final-ids/report_1/index.html`

`git diff --check` also completed with no whitespace errors.

## Self-review

- Confirmed the change list is limited to the three Task 4 routes, their focused unit/consumer coverage, the actual menu-route integration smoke, and this report.
- Confirmed the setup screens do not use obsolete `ZoneThumbnail`, `WeaponCardGrid`, or setup `Body` paths.
- Confirmed no temporary diagnostic prints remain; the integration test's existing `FULL_STATIC_ASSETS_MENU_V1_OK` success print is intentional.
- Confirmed icon rendering uses `CanvasItem.TEXTURE_FILTER_NEAREST` and meaningful real display sizes.
- Confirmed fallbacks remain readable when a content or global texture is absent.
- Confirmed no gameplay numbers, canonical IDs, default zone behavior, or session configuration code was changed.
- Confirmed no candidate, shipping, approval, or promotion state file was modified.
- Confirmed the isolated worktree and branch will be preserved for the parent task; no merge, push, or cleanup was performed here.

## Known non-blocking console noise

- Godot emits the pre-existing `Nodes with non-equal opposite anchors will have their size overridden after _ready()` warning from `screen_base.gd` during UI construction.
- The windowed GdUnit launcher emits a remote-debugger port `0` connection warning before running successfully.

Neither warning caused a test failure, leak, orphan, capture failure, or visual defect. No open Task 4 concern remains.
