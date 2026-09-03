# Main Merge Red-Gate Remediation Design

## Goal

Turn the `f1a52d3` full-suite result from 8 errors / 96 failures into an evidence-backed merge gate: fix production regressions, update obsolete tests to the accepted runtime contracts, and explicitly skip only tests that require a rendered 960×540 window or an external root-observer handshake when the generic runner is headless.

## Binding decisions

1. Restore the approved 12-weapon damage/cooldown matrix. Commit `86f2289` changed 21 values without a rebalance decision; the existing archetype tests and balance documents remain authoritative.
2. Set `process/fix_alpha_border=false` on the four training-ground shipping PNG imports. Shipping RGBA8 evidence must preserve transparent RGB.
3. Keep the accepted runtime migration: `SessionPlayerState.weapon_inventory` is authoritative, `weapon_ids` is a detached projection, initial materials are 20, enemy XP/supply share one ordered pickup bundle, and melee contact occurs after windup.
4. Keep the accepted visible-quality changes: the full-screen combat shell stays hidden, the HUD uses compact local backplates and `MaterialIcon`, and static-only feedback must not silently fall back to procedural art.
5. Keep the accepted content changes: `training_1` is named `重甲头盔`, pre-aim drills use candidate-003, rebound fire bottle uses candidate-002, and the counter-strafe base stop remains fast enough that a 50 ms probe can saturate at zero.
6. The generic test runner must start through `tests/helpers/isolated_gdunit_entry.gd`. Profile tests validate the generic isolated APPDATA/LOCALAPPDATA/user directory, not an obsolete task6 receipt.
7. The three native visual suites and the one capture-only weapon-menu case are not generic headless tests. In headless mode they must appear as explicit GdUnit skips with a reason; their rendered lane remains a separate acceptance gate.

## Root-cause matrix

| Domain | Verdict | Evidence |
|---|---|---|
| 12-weapon balance | Production regression | `86f2289` changed 21 values while balance references and archetype tests retained the approved matrix. |
| Four training-ground `.png.import` files | Production regression | They alone use `fix_alpha_border=true`; 88 other shipping sidecars use `false`. |
| HUD/reward/feedback/pause tests | Obsolete fixtures/contracts | They predate authoritative inventory, 20 initial materials, bundled pickups, static-only feedback, melee windup, and the local-backplate HUD. |
| Selection/profile/upgrade tests | Test defects/stale probes | Pointer helper omits `global_position`; profile guard is task6-specific; 50 ms braking probe saturates both paths. |
| Static preview baselines | Stale generated evidence/tests | Accepted candidates changed but coverage evidence and constants were not regenerated. |
| Native 960/capture-only tests | Wrong environment | Generic runner is headless; these tests require real window pixels and, for three cases, an external observer ACK. |

## Acceptance

- Focused suites for every changed domain pass with zero errors/failures/orphans.
- Static preview/shipping generators pass their read-only checks.
- The complete generic GdUnit suite passes with zero errors/failures/orphans; only the four documented rendered-only cases may be skipped.
- The existing rendered acceptance evidence remains linked in the closeout report, and no headless result is presented as rendered proof.
- After a green branch, `main` may be fast-forwarded only after its dirty worktree is preserved recoverably.
