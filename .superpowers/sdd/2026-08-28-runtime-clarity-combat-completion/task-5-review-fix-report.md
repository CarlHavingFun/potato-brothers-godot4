# Task 5 Review Fix Report

**Date:** 2026-08-28

**Review base:** `3b83ac17f13388d67cce55efc03b754eb2fbfc40`

**Branch:** `codex/full-static-assets-runtime`

## Important 1: suppressed-shot audibility

The synthesized source already distinguishes the suppressed shot from the rifle:

- peak ratio: `-8.587 dB`
- RMS ratio: `-10.327 dB`

The presenter previously added another `-8 dB`, yielding an end-to-end RMS ratio of `-18.327 dB`. The fix removes that duplicate mapper attenuation: rifle and suppressed profiles now both use a `0 dB` per-event offset. The shared AudioService effects gain therefore preserves the authored source ratio.

The presenter test now measures PCM16 RMS from the real source WAVs, combines it with the real selected voice gains, and enforces an end-to-end window of `[-14, -8] dB`. It also retains the same-tick distinct-voice assertions. The Python builder test independently enforces the same source RMS window plus the existing peak requirement.

## Important 2: real upstream smoke paths

The combat smoke no longer calls `world.melee_contact.emit` or `player.damage_taken.emit`.

For melee coverage it temporarily creates a real `GogoWeaponInstance`, configures it with the real player owner/world, and places it beside a real registered active enemy. Calling the weapon's normal physics attack path exercises:

`weapon target acquisition → enemy damage reservation → weapon melee_contact → CombatWorld handler/hitstop → world melee_contact → CombatScreen audio presenter → reserved damage commit`

Evidence includes the real allocated weapon ID, active enemy ID, weapon melee sequence, signal sequence, exact enemy health delta, and observed/cleared local hitstop. The probe is not added to `WeaponOrbit`, is freed immediately, and the smoke reasserts that the original six-weapon capture layout remains unchanged.

For player-hit coverage the smoke sets dodge and cooldown deterministically, preserves/restores RNG state and the prior dodge/cooldown values, ensures nonlethal health, and calls the real `GogoPlayerActor.take_damage`. Evidence includes the emitted sequence, actual health delta, ledger remaining health, and observed/cleared player-hit hitstop.

The debug ledger records only the metadata needed for this proof: contact source/target IDs and sequence, plus player damage/remaining health and sequence. Smoke coverage requires these entries to match independently captured real upstream signals and state transitions; it does not infer evidence from the ledger itself.

## TDD evidence

- I1 RED: the old presenter produced `-18.327 dB` end-to-end RMS and failed the `-14 dB` clarity floor; metadata assertions also failed because upstream fields were absent.
- I1 GREEN: equal rifle/suppressed mapper gain preserves `-10.327 dB`; focused presenter suite passed `5/5`.
- I2 RED: after deleting both manual emits, the smoke ledger contained 74 entries but lacked `melee_contact` and `player_damage_taken`; the combat smoke failed `1/2` as expected with zero runtime errors.
- I2 GREEN: the real melee/player paths restored complete event coverage; the final focused combat smoke passed `2/2` with 33 shots and 24 contacts.

## Verification

| Command | Result |
| --- | --- |
| `python tests/python/test_build_combat_sfx_v1.py` | `3/3` passed |
| focused `test_combat_audio_presenter.gd` | `5/5` passed |
| focused `full_static_assets_combat_v1_smoke.gd` | `2/2` passed |
| full `res://tests` | `379/379` passed across 39 suites; 0 errors/failures/flaky/skipped/orphans |

No WAV bytes or hashes changed. Task 7 artifacts were not modified.
