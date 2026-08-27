# Task 2 report — pivot-aware combat composition

Date: 2026-08-28

Baseline: `8acd5bf02b95d43904f7a8f785360dc5470d1b88`

Scope: combat presentation geometry, decorative world composition, procedural enemy body palette, and capture-only evidence layout. No content ID, weapon/item/enemy mechanic, static raster, candidate/shipping manifest, approval record, or Task 3 UI consumer file changed.

## Outcome

- Six weapon sockets remain evenly spaced and target-facing, but their ring now uses each texture's pivot-to-farthest-corner footprint. For six 96x64 weapons at pivot `[38,40]`, the orbit radius is about `152.9113px` instead of the audited `56px`.
- The ring enforces a `76px` Niko clear radius (60px rendered Niko radius plus 16px gap) and a 12px neighbor gap using rotation-invariant enclosing circles.
- The complete orbit extent (ring radius plus largest footprint) is cached and used as the player's arena clamp margin, preventing the enlarged ring from clipping at live arena edges.
- Runtime props now use seeded, asymmetric perimeter/scatter anchors with deterministic jitter, center rejection, and minimum separation. Capture composition uses a separate asymmetric real-route anchor set with HUD/center/rectangle rejection.
- Procedural enemy bodies now map CHASER/SHOOTER/CHARGER to rust `b86d52`, olive `9aa75a`, and amber `d68a3a` with a dark outline.
- Only the capture snapshot is 1280x720. The normal `GogoZoneDefinition` default remains 2048x1536.

## TDD evidence

Focused RED was observed before production edits:

| Gate | Expected RED | Evidence |
| --- | --- | --- |
| combat correctness | 20 cases, 3 failures: footprint API absent, orbit extent/clamp API absent, role palette API absent | `reports/combat-presentation-red-2/report_1/results.xml` |
| world presenter | 8 cases, 2 failures: normal off-grid count `0 < 8`; capture lattice residues `1 < 4` | `reports/world-presentation-red-2/report_1/results.xml` |

Focused GREEN:

| Gate | Result | Evidence |
| --- | --- | --- |
| combat correctness | 20/20 pass | `reports/combat-presentation-green-3/report_1/results.xml` |
| world presenter | 8/8 pass | `reports/world-presentation-green/report_1/results.xml` |
| preview runtime compatibility | 9/9 pass | `reports/combat-preview-runtime-green-2/report_1/results.xml` |
| full Godot suite | 334/334 pass, 0 errors/failures/flaky/skipped/orphans | `reports/combat-remediation-full-2/report_1/results.xml` |

The first whole-suite run exposed a capture-only race: continued hit impulses could shift the camera by an integer pixel after safe world rectangles were selected. The fixture now freezes camera physics only after real fire/contact evidence has been collected and impulses have been cleared. The next full run passed 334/334; production camera behavior is unchanged.

## Real windowed combat evidence

Windowed OpenGL real-route capture passed:

- `full_static_assets_combat_v1_smoke.gd`: 1/1 pass, 30 live shots, 27 live contacts.
- Impact kinds observed: `normal`, `critical`, `pierce_exit`, `explosion`.
- Mechanical coverage retained: 70/70, complete, zero unresolved rows, zero required-visual failures in the current schema.
- World evidence: 16 total records; 13 foreground `Props/*`; 13/13 foreground positions are off the 64px grid and all pass HUD, center, containment, and rectangle-overlap checks.
- `static_candidate_preview_combat_v1_smoke.gd`: direct windowed SceneTree run passed with six Glock instances, 12 shots and 7 impacts.

Fresh artifacts:

| Artifact | SHA-256 |
| --- | --- |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/full-static-assets-combat-v1/combat-1280x720.png` | `5C305EBE921E834B7402EB47C17FD4A41E2CF79C3312C18CC7973B378058F62C` |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/full-static-assets-combat-v1/pause-1280x720.png` | `4E510A9DCF1051D6D88A0F0C7D1C0556569B92A1ADDE115848CA188CB1EBF189` |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/full-static-assets-combat-v1/gogobro-static-coverage-v1.json` | `A6B15845E47123A31BF8CC933F411E263958D5F8E22799BBA62430B2BB59D562` |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/static-candidate-preview-combat-v1/fire-1280x720.png` | `5AC13761FACD754D892463DABBE5AAF4EFEE7346FFB2E52C9BC3E34D4B86722C` |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/static-candidate-preview-combat-v1/impact-1280x720.png` | `FAE74858C209BBD4CAA26903543A36C29073CF5E9C61F7564D8BE8F83B60B12A` |
| `C:/Users/18421/AppData/Roaming/GOGOBRO/static-candidate-preview-combat-v1/report.json` | `33923AE1AA293B81F3A8B3AD63394E6895EB65376C6B29A8D6EBB354464E53D3` |

## Actual-size visual inspection

The fresh 1280x720 combat PNG was inspected at original pixels. The floor and boundary cover the route without gray margins. Niko's face and torso remain unobstructed. All six distinct target-facing weapon silhouettes have visible gaps from Niko and one another. Props read as sparse perimeter/scatter accents rather than a 64px or 96px evidence board. Rust chasers sit within the charcoal/olive/orange world family. The candidate fire/impact frames retain muzzle flashes, recoil, projectiles, hit bursts, and visible separation in a duplicated six-Glock loadout.

## Gameplay invariants

- All 12 weapon IDs, modes, damage, cooldown, range, projectile speed/count/spread, knockback, price, feedback profiles, damage kinds, and impact kinds remain unchanged; the full suite's 5/5 weapon-archetype tests pass.
- Weapon visual pivots and muzzle/contact anchors remain unchanged; `weapon_instance.gd` is byte-for-byte untouched.
- Automatic target acquisition and firing interfaces remain unchanged.
- Enemy IDs, health, movement speed, touch damage, XP, materials, and roles remain unchanged in production; only procedural drawing colors changed.
- Production zone/content files are untouched; normal arena remains 2048x1536.

## Limitations and separate gates

- This task retains the existing mechanical 70/70 report but does not claim to fix the separate 67/70 visible UI-consumer audit. `nine_slice_panel`, `combat_hud_shell`, and `zone_thumbnail` remain Task 3.
- The integrated screenshot exercises rust chasers; olive shooter and amber charger swatches are locked by pure role-mapping tests and will receive broader final-route comparison in Task 4.
- The capture-only enemy evidence ring was moved from 180px to 330px because the old ring sat inside the new weapon/muzzle footprint. This does not change live enemy spawning or combat balance.
- Camera physics is frozen only after all required live events occur, solely to keep the evidence transform stable while the screenshot is written.
