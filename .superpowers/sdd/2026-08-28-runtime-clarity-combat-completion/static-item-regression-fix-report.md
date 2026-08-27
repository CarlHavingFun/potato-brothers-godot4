# Static Item Regression Fix Report

## Outcome

The five post-Task6 failures were stale pre-promotion test baselines, not a production runtime or appearance-layer regression. The fix updates only the exact approved icon hashes, the helmet shipping-icon dimensions, and the normalized shipping-manifest hash asserted by the two affected suites. Production media, manifests, registry data, mechanics, appearance metadata, and runtime validation were not changed.

## Root cause and contract audit

- `test_smoke_shell_helmet_install.gd` still expected the pre-promotion candidate-002 shipping icon (`9D5D...9BEC`, 256x256). Task6 intentionally promoted the accepted candidate-005 icon (`AC3A...80DE`, 64x64).
- `test_static_item_redraw_integration.gd` already knew the accepted preview identities, but its separate shipping assertions still expected the pre-promotion ballistic-liner and smoke-shell-helmet bytes. It also retained the pre-Task6 normalized whole-manifest hash.
- Task6 approval explicitly names the four overlap replacements as `ballistic_liner`, `service_pistol`, `smoke_shell_helmet`, and `warmup_shiv`, with accepted preview bytes winning in shipping.
- Registry, shipping manifest, and approval evidence agree for both affected items: 64x64 source/atlas/display geometry, scale 1.0, pivot (32, 32), nearest filtering, and no mipmaps.
- The helmet's wearable appearance is a separate unchanged 128x128 texture. Its appearance definition, rigid head-shell contract, render scale/pivot, all eight walk-frame anchors, and runtime resolution passed before the baseline edit.
- The 30-item mechanics baseline passed during the original failing reproduction and after the fix; IDs and gameplay were not altered.

## TDD evidence

RED on commit `bd867b0`:

- `test_smoke_shell_helmet_install.gd`: 4 cases, exactly 2 failures (old icon SHA-256 and old 256x256 size).
- `test_static_item_redraw_integration.gd`: 4 cases, exactly 3 failures (old ballistic-liner shipping SHA-256, old helmet shipping SHA-256, and old normalized manifest SHA-256).

GREEN after the minimal baseline migration:

- Helmet focused suite: 4/4 passed.
- Static-item redraw focused suite: 4/4 passed.
- Exact-byte and normalized-whole-manifest integrity checks remain in place; no assertion was weakened or removed.

## Verification

- Static shipping builder test: 1/1 passed and verified `pending=0`, the exact 65+5 release union, four overlap replacements, and registry/manifest/approval parity.
- Static asset registry suite: 14/14 passed.
- Static asset runtime service suite: 29/29 passed, including byte hash, decoded RGBA8 hash, pixel-size, atlas-bounds, display-scale, pivot, approval-evidence, and binding-integrity rejection tests.
- Native OpenGL shipping visual smoke: exited 0 with `STATIC_SHIPPING_RUNTIME_VISUAL_V1_OK`.
- Full `res://tests`: 36/36 suites and 357/357 cases passed with 0 errors, failures, flaky cases, skips, or orphans.
- `git diff --check` passed for the two modified tests and this report.

## Scope and concerns

Only these paths belong to this fix:

- `tests/unit/test_smoke_shell_helmet_install.gd`
- `tests/unit/test_static_item_redraw_integration.gd`
- `.superpowers/sdd/2026-08-28-runtime-clarity-combat-completion/static-item-regression-fix-report.md`

The concurrent modification to `tests/unit/test_combat_runtime_correctness.gd` is unrelated and intentionally excluded from staging and commit. No static-item concern remains. The full suite still emits existing Godot UI anchor warnings, but they are unrelated to these baselines and did not produce test failures.
