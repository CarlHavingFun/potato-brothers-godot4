# Task 3 report — honest visible UI consumers and compact menu actions

Date: 2026-08-28

Baseline: `7f876dcf9daf935315567bb536e20f8f530d97e3`

Scope: static UI observation semantics, coverage validation, real Diagnostic/Difficulty/Combat-HUD consumers, compact Main Menu geometry, one deterministic candidate-only zone-thumbnail derivative, route smoke evidence, and related tests. No gameplay ID/value, shipping raster, approval record, runtime binding, or Task 1/2 combat behavior changed.

## Outcome

- Ordinary handle observations now explicitly record `visible_texture: false`.
- `observe_visible_texture(...)` accepts only a non-null handle/texture whose exact texture object is assigned to an in-tree, currently visible `CanvasItem`, with an allowed `res://` consumer scene and non-empty node provenance.
- Coverage hard-rejects non-visible records for `nine_slice_panel`, `combat_hud_shell`, and `zone_thumbnail` as `texture_not_visibly_displayed`.
- Real routes now own all three visible records: one Diagnostic principal panel, one Difficulty map thumbnail, and one full-size HUD texture node using Task 1's preview-only low-border underlay.
- `MetricPalette` pixel sampling and the synthetic generic audit screen were removed from coverage evidence.
- Main Menu actions now occupy one centered `320x104` stack with two `320x48` buttons and an 8px gap while preserving all four authored texture states and routes.
- TextureRect observations now verify the claimed integer scale against the size actually rendered by their stretch mode; nine-slice `1x1` semantics remain an explicit authored-pixel/tile contract.
- `zone_thumbnail` now resolves a new non-approved `candidate-002` 256x144 nearest-neighbor derivative and is truly rendered at 1x in its existing 256x144 route rect.
- Diagnostic details use a clipped `ScrollContainer`; the title remains outside the panel content flow and the Return button remains pinned at the bottom of the same single 736x352 panel.

## TDD and root-cause evidence

Focused RED was observed before production edits:

| Gate | Expected RED | Evidence |
| --- | --- | --- |
| visible coverage rejection | all three `visible_texture:false` records were still accepted; six assertion failures, zero errors | `reports/ui-coverage-red/report_1/results.xml` |
| observer API | `observe_visible_texture` method absent; one assertion failure, zero errors | `reports/ui-visible-observer-red/report_1/results.xml` |
| menu routes | `MenuActions`, real `ZoneThumbnail`, and Diagnostic `PrincipalSurface` absent; three failures, zero errors | `reports/ui-menu-red-clean/report_1/results.xml` |
| HUD route | `BrotatoHUD/Shell` absent; two failures, zero errors | `reports/ui-hud-red-clean/report_1/results.xml` |

The confirmed causes were: audit normalization ignored rendered visibility; `nine_slice_panel` and `zone_thumbnail` were only synthesized in tests; HUD sampled one shell pixel into flat colors; main-menu buttons were direct children of the 1216px-wide body; and HUD configuration occurred before `add_child`, so visibility evidence needed an in-tree `_ready()` retry.

Focused GREEN:

| Gate | Result | Evidence |
| --- | --- | --- |
| coverage/observer semantics | 7/7 pass | `reports/ui-coverage-green-final/report_1/results.xml` |
| menu/difficulty/diagnostic routes | 10/10 pass | `reports/ui-diagnostic-scroll-green-1/report_1/results.xml` |
| HUD visible shell and fallback | 3/3 pass | `reports/ui-hud-green-final/report_1/results.xml` |
| existing HUD contract regression | 6/6 pass | `reports/ui-hud-regression-green/report_1/results.xml` |
| windowed menu + combat routes | 2/2 pass | `reports/report_140/results.xml` |
| direct button stability route | pass | `BUTTON_STABILITY_V2_SMOKE_OK` |
| final full Godot suite | 343/343 pass across 35 suites; zero errors/failures/flaky/skips/orphans | `reports/ui-remediation-full-final/report_1/results.xml` |

The first full run correctly exposed two stale assertions in `test_brotato_combat_hud.gd` that still required the removed no-Shell/pixel-sampled-color behavior. Updating that contract to require the new real Shell plus fixed metric fallback produced the focused 6/6 and final 343/343 passes.

## Exact visible observation provenance

The final real windowed coverage report is `70/70`, complete, with no unresolved or required-visual failures.

| Asset | Scene | Node | Source | Texture | Display scale | Visible |
| --- | --- | --- | --- | --- | --- | --- |
| `nine_slice_panel` | `res://game/ui/diagnostic_screen.gd` | `Diagnostic/PrincipalSurface` | development preview | 64x64 | 1x1 | true |
| `combat_hud_shell` | `res://game/ui/brotato_combat_hud.gd` | `BrotatoHUD/Shell` | development preview | 320x180 | 4x4 | true |
| `zone_thumbnail` | `res://game/ui/difficulty_select_screen.gd` | `SelectedDifficultyDetail/ZoneThumbnail` | development preview | 256x144 | 1x1 | true |

Coverage JSON:

- `E:/01_gobro/.worktrees/full-static-assets-runtime/reports/ui-task3-captures/AppData/GOGOBRO/full-static-assets-combat-v1/gogobro-static-coverage-v1.json`
- SHA-256 `4318BC870A492E45D1F3B7997EF00BF309CED4D2DE24326D7D6E21371B4A025E`

## Real 1280x720 captures and actual-size review

| Route | Capture | SHA-256 | 1x finding |
| --- | --- | --- | --- |
| Main Menu | `reports/ui-task3-captures/AppData/GOGOBRO/full-static-assets-menu-v1/menu-1280x720.png` | `B2C8FA76D70C1095B28F9E7306DBACBBA1CB891EC2C90ACF8AEDD9DF9F49EA0B` | two centered 320x48 authored buttons; no viewport-width rails or outer frame |
| Difficulty | `reports/ui-task3-captures/AppData/GOGOBRO/full-static-assets-menu-v1/difficulty-select-1280x720.png` | `8D163554E330D9A0F3ED7407283DB9E72184A4D43F381437BF177606B6AE35D5` | the 256x144 candidate renders at a true 1x, remains legible and unframed, and is clear of name/multiplier text |
| Diagnostic | `reports/ui-task3-captures/AppData/GOGOBRO/full-static-assets-menu-v1/diagnostic-1280x720.png` | `D079C8868BADB536211D820BE4283967C6C5A2B519A2369764E8C7F809F19911` | 28 details remain clipped and scrollable inside one 736x352 panel; the scrollbar and pinned Return action are visible |
| Combat | `reports/ui-task3-captures/AppData/GOGOBRO/full-static-assets-combat-v1/combat-1280x720.png` | `656DD274A996DA61E378C70510F46ACDE7F05F7C2C5C3C074370DC199E69591C` | Task 1 shell remains visible as two separated top accents, subordinate to metrics, with no connected viewport frame or lower slots |

The repeated L-shaped elements at the arena edges in the combat capture are the existing world boundary tiles, not the HUD shell. The runtime Shell texture was independently matched to Task 1's preview artifact SHA-256 `8212E0C9708A6DD7EE4FB8F669033F63D18B15A387CC50E6034D9AF3BDE2E74A`.

## Invariants and limitations

- Shipping assets, approval evidence, manifests/bindings, all content/gameplay IDs and values, Niko-only/12-weapon/one-difficulty contracts, and Task 1/2 presentation behavior remain unchanged.
- Candidate-only UI handles still retain flat/native fallbacks when unavailable.
- No hidden/offscreen/gallery-only consumer was added.
- Existing anchor-size warnings from `GogoScreenBase.build_screen_chrome()` remain visible in route logs and predate this task; they do not change capture geometry or test results.
- The strict 60-tuple item appearance release matrix remains a separate release gate and is not claimed by this UI task.

## Scoped-review provenance closure

The first scoped review found one Important false-positive: the original observer validated only a broadly allowed scene string and a non-empty node string, so a bare visible `TextureRect` could impersonate a real route.

The fix was completed through a new RED/GREEN cycle:

- RED: a real Difficulty route thumbnail with the exact target texture was incorrectly accepted when it claimed `res://game/ui/diagnostic_screen.gd`, and when it claimed `SelectedDifficultyDetail/FakeThumbnail`; both false calls created records. Evidence: `reports/ui-provenance-red/report_1/results.xml` (three failures, zero errors).
- GREEN: `observe_visible_texture()` now walks the actual CanvasItem ancestor chain, requires the claimed scene path to equal a real ancestor script `resource_path`, and requires the claimed node path to equal a named suffix ending at the CanvasItem. Evidence: `reports/ui-provenance-green-1/report_1/results.xml` (7/7 pass).
- The positive observer test now uses the actual scripted Difficulty route and its real `SelectedDifficultyDetail/ZoneThumbnail`; no bare synthetic positive claimant remains.
- Diagnostic's route root is named `Diagnostic`, making `Diagnostic/PrincipalSurface` an actual ancestor path without changing geometry or rendering.
- Focused menu/HUD suites remain 9/9 and 3/3, windowed real-route integration remains 2/2 with 70/70 coverage, and the post-fix full suite remains 343/343 across 35 suites with zero errors/failures/flaky/skips/orphans. Evidence: `reports/ui-provenance-full-final/report_1/results.xml`.

## Final whole-branch review closure

The whole-branch review found two further Important defects: the zone image was a 512x288 texture compressed into a 256x144 rect while claiming 1x, and unbounded Diagnostic details could overflow the fixed panel.

- RED scale evidence: `reports/ui-scale-red/report_1/results.xml` records the real routed half-size TextureRect being accepted and writing a visible record (two failures, zero errors).
- RED Diagnostic evidence: `reports/ui-diagnostic-scroll-red/report_1/results.xml` records absent `DetailsScroll` and pinned `ReturnButton` nodes (two failures, zero errors).
- RED candidate evidence: `reports/ui-zone-candidate-red/report_1/results.xml` records candidate-001 path plus wrong 512x288 pixel/display geometry and 256x144 pivot (ten assertions, zero errors).
- Candidate QC: source `candidate-001/curated/zone_thumbnail-512x288.png` SHA-256 `BBEB5E11F0AFFDA04DD525461E264A8FEF831A9126039A78512E79E45AC2A65F` was converted with deterministic nearest-neighbor 2:1 resampling. The new non-approved `candidate-002/curated/zone_thumbnail-256x144.png` and installed preview are byte-identical at SHA-256 `6856B72C4594AFB44E2F82CA050F879E5C45FDFEDC02FFC2D1B13D4CB0D32531`; pixel comparison against an independent nearest resize has no difference bounding box.
- Candidate manifest/evidence now record source candidate-002, pixel/display 256x144, pivot 128x72, nearest filtering, no mipmaps, and `candidate_preview_only`. `python tools/assets/build_static_candidate_preview.py --check --source-root E:\\01_gobro` passes all 65 units.
- GREEN evidence: scale/provenance 7/7 (`reports/ui-scale-green-1/report_1/results.xml`), menu/Diagnostic 10/10 (`reports/ui-diagnostic-scroll-green-1/report_1/results.xml`), candidate manifest 9/9 (`reports/ui-zone-candidate-green-1/report_1/results.xml`), HUD 3/3 (`reports/ui-task3-hud-scale-green/report_1/results.xml`), and preview runtime 9/9 (`reports/ui-task3-zone-runtime-green/report_1/results.xml`).
- Fresh isolated windowed menu integration passes 1/1 (`reports/report_145/results.xml`) and combat integration passes 2/2 (`reports/report_147/results.xml`). The latter emits complete 70/70 coverage with no rejected observations, unresolved IDs, or required visual failures.
- Final full regression passes 346/346 across 35 suites with zero errors, failures, flaky tests, skips, or orphans: `reports/ui-task3-full-final/report_1/results.xml`.
