# Task 5 Report: Pooled Combat Audio and Event Routing

**Date:** 2026-08-28

**Integration base:** `6569ff4eff2e00d81991eafb204e15dbeb533f57`

**Worktree:** `E:\01_gobro\.worktrees\full-static-assets-runtime`

**Branch:** `codex/full-static-assets-runtime`

## Result

- Added `GogoCombatAudioPresenter` as the typed mapping boundary from canonical combat signals to the pooled `GogoAudioService`.
- `CombatScreen` is the sole composition root: it injects `AppKernel.audio_service`, connects each world/player signal with an `is_connected` guard, and relies on Godot scene teardown to disconnect receivers.
- The combat model remains independent of `AppKernel`; no Task 3 or Task 4 combat-world/reward behavior was changed.
- The integration smoke reads a test-visible audio ledger and proves all six event classes, all four shot profiles, and all four contact variants. It does not assert physical speaker output.

## Event mapping

| Canonical event | Variant | WAV |
| --- | --- | --- |
| `weapon_fired` | `rapid` | `rapid_shot.wav` |
| `weapon_fired` | `rifle` | `rifle_shot.wav` |
| `weapon_fired` | `heavy` | `heavy_shot.wav` |
| `weapon_fired` | `suppressed` | `suppressed_shot.wav` |
| projectile/melee contact | `normal` | `impact_normal.wav` |
| projectile/melee contact | `critical` | `impact_critical.wav` |
| projectile/melee contact | `pierce_exit` | `impact_normal.wav`, pitched up |
| projectile/melee contact | `explosion` | `impact_explosion.wav` |
| `enemy_defeated` | `enemy_down` | `enemy_down.wav` |
| player `damage_taken` | `player_hit` | `player_hit.wav` |
| `pickup_collected` | experience/supply | `pickup.wav` |

The source `suppressed_shot.wav` peak is `-8.587 dB` and its RMS is `-10.327 dB` relative to `rifle_shot.wav`. The presenter applies equal per-event gain to the two profiles, and `GogoAudioService` applies the same effects-setting gain to both. The complete source → mapper → service chain therefore preserves the authored `-10.327 dB` RMS distinction: at least 8 dB quieter while remaining above the `-14 dB` clarity floor.

## TDD evidence

1. RED: `test_combat_audio_presenter.gd` ran four cases before production code existed; all four failed for the missing presenter/screen route, with zero discovery/runtime errors.
2. Mapping GREEN: after adding only the presenter, the mapping/validation/voice cases passed and the CombatScreen route case remained the sole expected failure.
3. Routing GREEN: after adding the composition-root wiring, all four cases passed.
4. Lifecycle coverage: added a fifth case proving receiver connections disappear automatically when the screen/presenter subtree is freed; `5/5` passed with zero errors, failures, flaky tests, skips, or orphans.
5. Integration smoke: `2/2` passed; the real six-weapon route produced 33 shots and 22 contacts and the ledger covered every required class and variant.

Godot WAV preloads initially failed because this new worktree did not yet contain `.godot/imported/*.sample`. Running Godot once with `--import` regenerated the local cache from the already tracked `.wav.import` sidecars. No generated cache files are part of the commit.

## Verification

| Command | Result |
| --- | --- |
| `python tests/python/test_build_combat_sfx_v1.py` | `3/3` passed; includes two-build byte identity and WAV/source-volume validation |
| focused `test_combat_audio_presenter.gd` | `5/5` passed, 0 errors/failures/flaky/skipped/orphans |
| focused `full_static_assets_combat_v1_smoke.gd` | `2/2` passed, 0 errors/failures/flaky/skipped/orphans |
| `res://tests/unit` | `376/376` passed across 37 suites, 0 errors/failures/flaky/skipped/orphans |
| `res://tests` final regression | `379/379` passed across 39 suites, 0 errors/failures/flaky/skipped/orphans |

## Reproducible WAV SHA-256

| WAV | SHA-256 |
| --- | --- |
| `enemy_down.wav` | `1238d0ba2d421e943e108e8f03a3c72c576d44bb6be1ae79e326be58da9034a7` |
| `heavy_shot.wav` | `dfd576090eb3250ff9210d29e49388c2473ff1789eeea07c4b70956076f25a02` |
| `impact_critical.wav` | `5dcc9b88a8150f4e90e81e4fe63d7396e94d4473b23f03c091a4a7baa03d22ba` |
| `impact_explosion.wav` | `b2f388292ecda8ee7d4ee4427590ee298c456e22500d3034681a24965af92ca7` |
| `impact_normal.wav` | `553ecedc1ace5162bffc0cf93fffc78389e52e8222fbe541363d30c03af05f41` |
| `pickup.wav` | `548c6c56dc79502d655686f3e273ac417b4b287ae1af39a927b49d48e156f51f` |
| `player_hit.wav` | `ce74ea5d409c5fbda9e374235d102a571c983d1f42904f32b54e79f2eb5b57a8` |
| `rapid_shot.wav` | `5ffd1305a2d73eaaf93f5ced56cc4aa493cf1be24895a51fd188dbb07e16bf2c` |
| `rifle_shot.wav` | `6b7e5734268b1523734dbd1449db09a0d61216ccb86ef3ed3a6fc9ecfa9e460f` |
| `suppressed_shot.wav` | `2719d254a2d09e8d76eb51236e6a7ab8b2fff78da31345ef2d03c398a81015d4` |

The authoritative machine-readable report remains `game/assets/audio/combat/combat_sfx_v1.sha256.json` from the audio-base commit.

## Review and hygiene

- Local senior-review checklist: no critical, important, or minor findings after checking plan alignment, typed signal signatures, composition boundaries, teardown behavior, optional gain/pitch flow, same-tick pooling, and Task 3/4 compatibility.
- Godot-generated preview `.import` files and unrelated/test `.gd.uid` files were removed from the worktree. The new production presenter UID is retained because this repository consistently tracks UIDs for newly added production GDScript resources.
