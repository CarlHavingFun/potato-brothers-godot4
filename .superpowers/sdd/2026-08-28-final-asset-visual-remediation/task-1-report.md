# Task 1 report — candidate raster identity and preview helmet parity

Date: 2026-08-28

Baseline: `1fa622d13ab6e9fb972af7ad077430219208646f`

Scope: development-preview assets and preview-only runtime wiring. No shipping asset, approval record, gameplay value, content ID, pivot, anchor, selector, or active binding was changed.

## Outcome

Task 1 is implemented and verified. Five distinct rasters were generated with built-in ImageGen in five separate calls, then deterministically cleaned/aligned with the `generate2dsprite` workflow. The four preview families are now:

- `warmup_shiv`: unmistakable open CS-style Butterfly Knife with two separated handles and two visible pivots.
- `pre_aim_drills`: a physical optic-adjustment/training jig with clamp, cradle, and adjustment hardware; not a reticle.
- `smoke_shell_helmet`: one shared olive shell / amber visor / twin charcoal-filter identity across icon and worn candidates.
- `combat_hud_shell`: two disconnected top backing accents only; transparent outer edge, no connected viewport frame, and no bottom inventory-slot frame.

Actual-size clarity, silhouette, edge cleanliness, and family cohesion were the gate. No coarse-pixel or large-flat-block requirement was imposed.

## TDD evidence

RED was established before implementation:

- `tools/run_tests.ps1 ... -TestPath res://tests/unit/test_static_candidate_preview_manifest.gd -ReportDirectory res://reports/art-remediation-red-manifest`
  - expected failures: old candidate paths/hashes and old connected HUD structure.
- `tools/run_tests.ps1 ... -TestPath res://tests/unit/test_static_candidate_preview_runtime.gd -ReportDirectory res://reports/art-remediation-red-runtime`
  - expected failure: preview item still resolved the shipping appearance instead of the new preview-only worn texture.

Focused GREEN after implementation:

| Gate | Result | Evidence |
| --- | --- | --- |
| preview manifest | 8/8 pass | `reports/art-remediation-green-manifest/report_1/results.xml` |
| preview runtime | 9/9 pass | `reports/art-remediation-green-runtime-2/report_1/results.xml` |
| helmet install/isolation | 4/4 pass | `reports/art-remediation-green-helmet/report_1/results.xml` |
| redraw contract | 12/12 pass | `reports/art-remediation-green-redraw/report_1/results.xml` |
| HUD consumers | 3/3 pass | `reports/art-remediation-green-ui-consumers/report_1/results.xml` |
| item redraw integration | 4/4 pass | `reports/art-remediation-green-item-integration/report_1/results.xml` |
| full Godot suite | 331/331 pass | `reports/art-remediation-full-2/report_1/results.xml` |
| harmony/install Python gates | 142/142 pass | `uv run --with pytest --with pillow python -m pytest ...` |
| preview builder | pass, 65 units, copied 0 | manifest SHA `60AB3E4169C4B1377076793F9CA3A2D2464D6D614823F62A8B3B159AAE80537A` |

The first full run exposed three stale expectations in `test_static_item_redraw_integration.gd` for helmet candidate-004. Updating that contract test to candidate-005 produced the final 331/331 pass.

## ImageGen and candidate provenance

Each source raster came from one separate built-in ImageGen call. No CLI generator or hand-authored substitute was used.

| Raster | Built-in output | Inbox candidate raw | Raw SHA-256 |
| --- | --- | --- | --- |
| Butterfly Knife | `C:/Users/18421/.codex/generated_images/01a044cb-40be-7dd1-8345-9a9411593483/exec-8adc9f9e-a943-4323-b07e-dd88ef035f77.png` | `GOGOBRO_ASSET_INBOX/02_static_assets/weapons/warmup_shiv/candidate-003/raw/warmup-shiv-butterfly-knife-imagegen.png` | `01AD2329909EB08D975A473DC6B27665F937F9A35774CD7285F81FA327BDEBD8` |
| physical pre-aim jig | `C:/Users/18421/.codex/generated_images/01a044cb-40be-7dd1-8345-9a9411593483/exec-67a42917-082e-48bd-b08b-2a338fdde5a7.png` | `GOGOBRO_ASSET_INBOX/02_static_assets/upgrades/pre_aim_drills/candidate-002/raw/pre-aim-drills-imagegen.png` | `5E7E30798448FA0D4028BEDDFC8C46E30AEE9827012F16DE1D95F5A3454F2FB6` |
| helmet icon | `C:/Users/18421/.codex/generated_images/01a044cb-40be-7dd1-8345-9a9411593483/exec-b9b53f42-b1e9-49a7-b5cf-f53abf6a2328.png` | `GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-005/raw/smoke-shell-helmet-icon-imagegen.png` | `E7EF8AFF75CCF536CA8D80D698FA9BC490A0F2BC690DA46F06DB4184C028C91D` |
| helmet worn source | `C:/Users/18421/.codex/generated_images/01a044cb-40be-7dd1-8345-9a9411593483/exec-802bc35b-1985-4198-be46-a102bbc47400.png` | `GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-005/raw/smoke-shell-helmet-appearance-imagegen.png` | `2C11C955ED424B6B9E97D35F735D728AF122242C0075D744272ED8F80CB2CA23` |
| HUD underlay | `C:/Users/18421/.codex/generated_images/01a044cb-40be-7dd1-8345-9a9411593483/exec-1bf47bc1-f18a-43f5-b463-7a8307420884.png` | `GOGOBRO_ASSET_INBOX/02_static_assets/ui_brand/combat_hud_shell/candidate-002/raw/combat-hud-shell-imagegen.png` | `5E8F777EA338DE54941171BF2C26A05FE71E2A68A6B9FA25025950C55F4B728A` |

Each candidate root contains its raw input, deterministic pipeline output/provenance, curated output, and actual-size review material. `generate2dsprite` was used only for chroma cleanup, connected-component extraction, alignment, nearest scaling, alpha normalization, and QC; it did not invent the art.

## Installed preview artifacts

| Preview artifact | Candidate source | SHA-256 | Actual-size evidence |
| --- | --- | --- | --- |
| `game/assets/gogobro_static_preview/weapons/warmup_shiv.png` | `.../warmup_shiv/candidate-003/curated/warmup-shiv-butterfly-knife-64x64.png` | `C68E43AEC6CA95337D3338318279BB3DEAA744EC2B1B34469EC1C1D49FA2922E` | 64×64, bbox `[2,25,62,38]`, `review/warmup-shiv-review-6x.png` |
| `game/assets/gogobro_static_preview/upgrades/pre_aim_drills.png` | `.../pre_aim_drills/candidate-002/curated/pre_aim_drills-icon-64x64.png` | `2BB496AB5B31BE7063F4281C2D3784AE473EDB9A1027D789872BF50D03AF1180` | 64×64, bbox `[10,6,53,58]`, `review/pre-aim-drills-review-6x.png` |
| `game/assets/gogobro_static_preview/items/smoke_shell_helmet.png` | `.../smoke_shell_helmet/candidate-005/curated/smoke_shell_helmet-icon-64x64.png` | `AC3ACB1118DEFA21907EE7323BC4D07B8DEE53FCCCABDD94CD26DA73686680DE` | 64×64 logical icon, bbox `[12,12,51,53]`, icon 1×/6× review |
| `game/assets/gogobro_static_preview/items/smoke_shell_helmet_appearance.png` | `.../smoke_shell_helmet/candidate-005/curated/smoke_shell_helmet-appearance-128x128.png` | `5DF0153E38B9D258EADB19EE1DCD4BC0A87DEA1C0AD0D02D18247C5787DFD55F` | 128×128 runtime source, strict walk_down actual-size sheet |
| `game/assets/gogobro_static_preview/ui/combat_hud_shell.png` | `.../combat_hud_shell/candidate-002/curated/combat_hud_shell-logical-320x180.png` | `8212E0C9708A6DD7EE4FB8F669033F63D18B15A387CC50E6034D9AF3BDE2E74A` | 320×180, bbox `[8,9,196,29]`, transparent outer 3 px and entire bottom half |

All final rasters have binary alpha and zero RGB in transparent pixels. The accepted detailed AK preview and Niko mother frame were inspected before generation, and every final 1×/6× review was inspected after cleanup.

## Helmet runtime and harmony scope

The preview factory preserves the exact tuple:

`head / head_shell / RIGID / depth 40 / render_scale 0.625 / rendered pivot [36,48] / local offset [0,0]`.

| Animation | Source | SHA-256 | Result | Correct evidence claim |
| --- | --- | --- | --- | --- |
| `walk_down` | 128×128 preview appearance | `5df0153e...7dfd55f` | rig `rig_pass`; strict v2 `harmony_pass` | actual preview-runtime parity |
| `walk_left45` | deterministic candidate-only 96×96 derivative | `fe466179...f4bdf328` | rig `rig_pass`; strict v2 `harmony_pass` | trusted-animation compatibility candidate; not runtime-integrated |

Evidence paths:

- `reports/art-remediation/smoke_shell_helmet/candidate-005/rig-walk_down/`
- `reports/art-remediation/smoke_shell_helmet/candidate-005/rig-walk_left45/`
- `reports/art-remediation/smoke_shell_helmet/candidate-005/v2-walk_down-scaled/`
- `reports/art-remediation/smoke_shell_helmet/candidate-005/v2-walk_left45-96/`

The preflight's original single-128-source command was corrected because strict RIGID v2 and the trusted left45 rig require the appearance source to match the 96×96 frame. The 96×96 derivative is retained only in candidate provenance and is not referenced by the preview factory.

## Isolation evidence

- Shipping helmet icon remains `9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC`.
- Shipping helmet appearance remains `B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A`.
- `git diff 1fa622d -- game/assets/gogobro_static game/content/assets/gogobro_static_runtime_bindings_v1.json game/content/assets/gogobro_static_assets_v1.json tools/assets/approved_candidate_bindings_v1.json tests/fixtures/gogobro_static_item_mechanics_baseline_v1.json` is empty.
- `SmokeShellHelmetFactory` is unchanged; only `SmokeShellHelmetPreviewFactory` loads the new worn preview raster.

## Limitations and separate gates

- This task does not approve or promote any preview candidate to shipping.
- It does not integrate `walk_left45` into runtime appearance selection.
- It does not create or claim the broader 60-tuple playable-character × visible-item × trusted-animation release matrix. That release gate remains explicitly **0/60 evidenced** here.
- The legacy `tests/python/test_smoke_shell_helmet_candidate_002.py` suite is not green against the current baseline registry: after 13 passes, `test_package_owned_binding_matches_the_user_approved_candidate` detects candidate-002 metadata pinned to an older registry snapshot/hash. This task intentionally did not rewrite immutable approval evidence. The current strict harmony/install Python gates pass 142/142, and the complete Godot suite passes 331/331.
