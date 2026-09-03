# Main merge red-gate closeout — 2026-09-03

## Baseline and remediation

The recorded preflight baseline was **638 cases, 8 errors, 96 failures, 0
skips, and 0 orphans**. Its JUnit report is
`reports/main-merge-preflight-20260903/report_1/results.xml`.

The remediation and follow-up commits through the pre-closeout head were:

- `b6ab95d` — `docs: plan main merge red gate remediation`
- `4cde2cf` — `fix: restore approved weapon and import contracts`
- `8dcdf1a` — `test: align combat contracts with accepted runtime`
- `ff921cb` — `fix: repair isolated selection and profile contracts`
- `e5ba07f` — `test: refresh accepted static asset evidence`
- `c7a2223` — `test: preserve shared legacy profile directory`

## Rendered-only headless waivers

The generic runner is headless. These four dedicated rendered-only cases are
therefore explicit GdUnit skips, rather than timeouts or false visual results.
The installed GdUnit scanner names the accepted per-case skip parameter
`_do_skip`; each case retains its exact `_skip_reason`.

| Focused report | Test case | Cases | Errors | Failures | Skips | Orphans | Explicit reason |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `reports/main-merge-final-20260903/focused-native-960-character/report_2/results.xml` | `test_native_960_character_same_page_flow_waits_for_root_observation_ack` | 1 | 0 | 0 | 1 | 0 | `requires the windowed 960x540 visual/root-observer runner` |
| `reports/main-merge-final-20260903/focused-native-960-hud/report_1/results.xml` | `test_native_960_combat_hud_layout_waits_for_root_observation_ack` | 1 | 0 | 0 | 1 | 0 | `requires the windowed 960x540 visual/root-observer runner` |
| `reports/main-merge-final-20260903/focused-task-zone-native-960/report_1/results.xml` | `test_release_summary_and_test_only_multi_task_input_render_at_native_960` | 1 | 0 | 0 | 1 | 0 | `requires the windowed 960x540 visual runner` |
| `reports/main-merge-final-20260903/focused-weapon-quality/report_1/results.xml` | `test_capture_only_native960_weapon_action_menu_ready_for_root_observation` | 31 | 0 | 0 | 1 | 0 | `requires the windowed 960x540 visual/root-observer runner` |

Each focused run was serial, emitted `ISOLATION_GUARD_OK`, and had zero
matching Godot/GOGOBRO processes before and after invocation. The weapon suite
executed its other 30 ordinary logic cases; only the capture-only menu case was
skipped.

## Final generic gate

The post-cleanup complete headless invocation was:

```text
tools/run_tests.ps1 -TestPath res://tests -ReportDirectory res://reports/main-merge-final-20260903-clean
```

It emitted `ISOLATION_GUARD_OK`, was run serially with zero matching
Godot/GOGOBRO processes before and after, and wrote
`reports/main-merge-final-20260903-clean/report_1/results.xml`.

Result: **654 cases, 0 errors, 0 failures, 4 skips, 0 orphans, 0 flaky**. The
16 additional cases relative to the stale 638-case baseline are included in
the actual discovery count. The four skips are exactly the cases and reasons in
the table above; no ordinary logic test is suite-wide skipped.

## Task 4 generator checks

Both non-mutating checks were rerun on the final pre-closeout head:

- `python tools/assets/build_static_candidate_preview.py --check` — exit 0;
  65 units; manifest SHA-256
  `A9DCE4E6C6A0B7B82EDDF97A64FEE2C2FCA1A0A8DC7DCAFE11850804B3C605B9`;
  coverage SHA-256
  `3D7A580E1036C6556265F0BF40EC8EA67573AAD21443FD12F0253D4F320762E5`.
- `python tools/build_static_shipping_install.py` — exit 0; 70 active,
  0 inactive, 0 pending; registry SHA-256
  `B690FFFFD6744B2E6A3CEB4319DB070D53C4FFD4D107C66BA95A329F92A352AA`.

## Separate rendered lane evidence

The following existing rendered evidence paths were verified to exist. They
are separate from the headless gate: **headless skips are not rendered proof**.
The 1280×720 character, HUD, and weapon-menu images remain accurately labeled
as 1280×720 evidence, not as 960×540 captures.

- Character selection, 1280×720:
  `reports/final-integration-20260902/native-roster-1280-final/synthetic-profile/Roaming/GOGOBRO/hud-native-1280-visual-regression-v1/hud-character-select-1280x720.png`
- Combat HUD, 1280×720:
  `reports/final-integration-20260902/native-roster-1280-final/synthetic-profile/Roaming/GOGOBRO/hud-native-1280-visual-regression-v1/hud-combat-1280x720.png`
- Task-zone current summary, 960×540:
  `reports/final-integration-20260902/native-task-960-final/synthetic-profile/Roaming/GOGOBRO/task-zone-native-960-v1/task-current-summary-release-960x540.png`
- Weapon menu, 1280×720:
  `reports/final-integration-20260902/native-menu-1280-final/synthetic-profile/Roaming/GOGOBRO/full-static-assets-menu-v1/weapon-select-1280x720.png`
