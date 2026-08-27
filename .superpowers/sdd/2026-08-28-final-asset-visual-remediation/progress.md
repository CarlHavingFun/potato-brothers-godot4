# SDD ledger — plan: docs/superpowers/plans/2026-08-28-final-asset-visual-remediation.md

Baseline: `1fa622d`, isolated worktree `E:/01_gobro/.worktrees/full-static-assets-runtime`, 329/329 full suite passing. Task 4 setup flow and all prior UI tasks are reviewed clean.

## Preflight consistency matrix

| Scope | Producer / consumer relationship | Finding |
| --- | --- | --- |
| Task 1 self | Four repaired preview rasters, exact manifests, preview helmet factory, harmony evidence | Internally consistent; generated art stays candidate-only. |
| Task 2 self | Pivot-aware weapon ring, off-grid world composition, enemy palette, real capture | Internally consistent; gameplay IDs/stats/fire interfaces remain unchanged. |
| Task 3 self | Visible texture observer, three real UI consumers, compact main menu | Depends on Task 1's low-border HUD underlay. |
| Task 4 self | Full tests, captures, coverage, audit, two-game playtest | Consumes all prior tasks; no production edits unless a gate returns to its owner. |
| Tasks 1 → 3 | `combat_hud_shell` must be safe to display before it becomes a real HUD consumer | Run sequentially. |
| Tasks 1 ↔ 2 | Shared combat captures/tests but independent production files | Run sequentially to preserve one implementer and coherent evidence. |
| Tasks 2 → 4 | Final combat comparison requires repaired ring/world/palette | Aligned. |
| Tasks 3 → 4 | Final 70/70 report requires honest visible UI observations | Aligned. |

## Rulings

Ruling: all new rasters are development-preview candidates only. Approved shipping files, hashes, bindings, active candidate IDs, approval evidence, and gameplay mechanics are immutable — if wrong, rollback is limited to preview paths/manifests/factory.

Ruling: actual-size clarity, recognizable silhouette, clean edges, and family consistency are the visual gate; coarse pixels and large color blocks are not requirements — if wrong, regenerate one preview candidate without changing the contract.

Ruling: `combat_hud_shell` is repaired into separated top-left/top-center backing accents with transparent outer edges and no bottom inventory slots before becoming visible. Displaying the old connected viewport frame would contradict the user's low-border decision — if wrong, only the preview raster and HUD underlay integration change.

Ruling: the currently integrated 128×128 helmet receives a strict v2 `walk_down` runtime-parity check. Because the trusted `walk_left45` rig is 96×96 and the v2 RIGID contract requires an appearance source matching that frame size, a separately recorded 96×96 derivative of the same generated helmet identity receives the `walk_left45` compatibility check. Both checks must pass, but only `walk_down` is currently runtime-integrated. The 60-tuple all-item worn-appearance matrix is a separate release gate and is not claimed by this development-preview task — release remains blocked without that matrix, while current playable icon/runtime remediation remains honest.

Ruling: Tasks 1–3 execute sequentially because they share manifests and real-route capture tests; every task gets a fresh implementer, scoped reviewer, and fix/re-review loop.

## Completed and independently reviewed

Task 1: candidate raster identity and preview helmet parity implemented from base `1fa622d`.

- Five separate built-in ImageGen raster calls produced the Butterfly Knife, physical pre-aim jig, helmet icon, matching worn helmet, and low-border HUD underlay.
- Preview-only assets/manifests/factory are integrated; shipping art, hashes, approved bindings, IDs, and mechanics remain unchanged.
- `walk_down`: 128×128 actual preview-runtime parity, rig `rig_pass`, strict v2 `harmony_pass`.
- `walk_left45`: deterministic 96×96 candidate-only compatibility derivative, rig `rig_pass`, strict v2 `harmony_pass`; not runtime-integrated.
- Focused Godot gates pass, preview builder passes with 65 units and zero copies, harmony/install Python gates pass 142/142, and the final full Godot suite passes 331/331.
- Release appearance coverage remains 0/60 in this task; no matrix or release-readiness claim was added.
- Complete evidence: `.superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-1-report.md`.
- Commit `af9e310` received a fresh read-only actual-size review: **APPROVED**, with no Critical or Important findings. The only Minor note is that one preview test name still says “approved” even though its assertion correctly targets candidate-preview art.
- The reviewer independently confirmed that the legacy candidate-002 Python approval-binding failure predates Task 1 and that all implicated shipping/approval inputs are byte-for-byte unchanged from `1fa622d`.

Task 2: pivot-aware combat composition implemented from reviewed Task 1 HEAD and recorded in `.superpowers/sdd/2026-08-28-final-asset-visual-remediation/task-2-report.md`.

- Six-slot orbit geometry uses real display bounds and pivots, maintains Niko/neighbor gaps, and caches full orbit extent for live arena clamping.
- Seeded asymmetric props, rust/olive/amber procedural enemy colors, and capture-only 1280×720 evidence are integrated without gameplay/content/UI-consumer changes.
- Initial focused, integration, real-window, actual-size capture, and 334/334 full-suite gates passed; production commit `586df4b` contains the implementation.
- Scoped review found one Important test-only gap: the edge test bypassed the live physics-to-world clamp connection. It was replaced by six parameterized runtime cases (counts 1–6), each covering all four arena edges and every rotated pivot-aware weapon footprint.
- Mutation control with the old fixed `24px` margin failed all six parameter cases with 56 footprint violations; restoring the pivot-aware margin passed 25/25 focused cases. The temporary mutation is absent from the final diff.
- The post-review final full Godot regression passes 339/339 across 35 suites with zero errors, failures, flaky cases, skips, or orphans.
