# Task 5 Audio Base Report

**Date:** 2026-08-28
**Branch:** `codex/combat-audio-base`
**Base:** `2d1054e1db920f3750f8ab9e63071fe724e4dd20`

## Delivered scope

- Added `tools/assets/build_combat_sfx_v1.py`, a standard-library-only deterministic synthesizer. It accepts no sample inputs and uses authored oscillators, envelopes, and a fixed xorshift noise source.
- Added ten original combat WAV files plus a canonical SHA-256 JSON report under `game/assets/audio/combat/`.
- Upgraded `GogoAudioService` to one `Music` player and twelve deterministic `SFX` voices. The legacy `effects_player` points at voice 1, and the original one-argument `play_effect(stream)` call remains valid.
- Added optional per-call `volume_db` and `pitch_scale`. Effects settings are combined with the per-call volume offset.
- Allocation prefers the lowest-index idle voice. Saturation steals the smallest activation serial, with stable voice-index ordering. Two same-tick calls therefore use separate voices while capacity remains.
- Added only builder/audio-service tests. This base intentionally does not add `combat_audio_presenter.gd` or modify `combat_screen.gd` / combat smoke; those remain for the signal-routing integration task.

## TDD evidence

### RED

- `python tests/python/test_build_combat_sfx_v1.py`: 2 failures because the requested builder did not exist.
- `tools/run_tests.ps1 ... -TestPath res://tests/unit/test_audio_service.gd`: 6 cases executed, 5 expected failures, 0 errors. Failures identified the missing twelve-voice pool.
- A later suppressed-profile test failed at `-5.065 dB`, proving the required minimum 8 dB distinction was not yet met.

### GREEN / regression

- `python tests/python/test_build_combat_sfx_v1.py`: 3/3 passed.
- focused `test_audio_service.gd`: 6/6 passed, 0 errors, 0 failures, 0 flaky, 0 skipped, 0 orphans.
- `full_static_assets_menu_v1_smoke.gd`: 1/1 passed, 0 errors, 0 failures, 0 orphans; the real `app_root.tscn` booted with the upgraded service. Existing Control anchor warnings remained unchanged.
- `Godot_v4.7.1-stable_win64_console.exe --headless --editor --path . --import --quit`: exited 0 and imported all ten WAV sources.

## Determinism and format

The final builder was run twice against the shipping directory. All 21 files in that directory (10 WAVs, 10 required `.wav.import` sidecars, and the JSON report) were byte-identical across runs. No `.uid` or unrelated `.import` file is included.

Every WAV is mono, little-endian PCM16 at 44,100 Hz, shorter than 350 ms, bounded below 0.95 full scale, and exactly zero at its first and last sample. The first/last 32-sample windows remain within 0.03 full scale. `suppressed_shot.wav` is 75.011 ms versus 150 ms for `rifle_shot.wav`, with a peak difference of approximately -8.59 dB.

## Final WAV SHA-256

| File | Duration ms | Peak | SHA-256 |
|---|---:|---:|---|
| `enemy_down.wav` | 240.000 | 0.820002 | `1238d0ba2d421e943e108e8f03a3c72c576d44bb6be1ae79e326be58da9034a7` |
| `heavy_shot.wav` | 220.000 | 0.899991 | `dfd576090eb3250ff9210d29e49388c2473ff1789eeea07c4b70956076f25a02` |
| `impact_critical.wav` | 130.000 | 0.839991 | `5dcc9b88a8150f4e90e81e4fe63d7396e94d4473b23f03c091a4a7baa03d22ba` |
| `impact_explosion.wav` | 300.000 | 0.899991 | `b2f388292ecda8ee7d4ee4427590ee298c456e22500d3034681a24965af92ca7` |
| `impact_normal.wav` | 90.000 | 0.779992 | `553ecedc1ace5162bffc0cf93fffc78389e52e8222fbe541363d30c03af05f41` |
| `pickup.wav` | 180.000 | 0.719993 | `548c6c56dc79502d655686f3e273ac417b4b287ae1af39a927b49d48e156f51f` |
| `player_hit.wav` | 160.000 | 0.839991 | `ce74ea5d409c5fbda9e374235d102a571c983d1f42904f32b54e79f2eb5b57a8` |
| `rapid_shot.wav` | 90.000 | 0.779992 | `5ffd1305a2d73eaaf93f5ced56cc4aa493cf1be24895a51fd188dbb07e16bf2c` |
| `rifle_shot.wav` | 150.000 | 0.860012 | `6b7e5734268b1523734dbd1449db09a0d61216ccb86ef3ed3a6fc9ecfa9e460f` |
| `suppressed_shot.wav` | 75.011 | 0.319987 | `2719d254a2d09e8d76eb51236e6a7ab8b2fff78da31345ef2d03c398a81015d4` |

Canonical report SHA-256: `fc5d4fc3cc57bc826791f85393aa2f530d1bdc7c5f59fa34abf66353def96f1d`.
