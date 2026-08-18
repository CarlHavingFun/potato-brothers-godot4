class_name CoreWaveRules
extends RefCounted


## Neutral, data-facing baseline for the standard twenty-wave ruleset.
## Presentation packs must never expose the provenance of these values.
const MAX_ACTIVE_ENEMIES := 100
const STANDARD_FINAL_WAVE := 20
const MATERIAL_STREAM_OFFSET := 0x4D41544C
const STANDARD_DURATIONS: Array[float] = [
	0.0,
	20.0, 25.0, 30.0, 35.0, 40.0,
	45.0, 50.0, 55.0,
	60.0, 60.0, 60.0, 60.0, 60.0, 60.0,
	60.0, 60.0, 60.0, 60.0, 60.0,
	90.0,
]
const SPECIAL_EVENT_WINDOWS: Array[Vector2i] = [
	Vector2i(11, 12),
	Vector2i(14, 15),
	Vector2i(17, 18),
]


static func duration_for_wave(wave_number: int, fallback: float = 60.0) -> float:
	if wave_number >= 1 and wave_number < STANDARD_DURATIONS.size():
		return STANDARD_DURATIONS[wave_number]
	return 60.0 if wave_number > STANDARD_FINAL_WAVE else maxf(0.1, fallback)


static func special_event_windows(difficulty_level: int) -> Array[Vector2i]:
	var count := 0
	match clampi(difficulty_level, 1, 5):
		2, 3:
			count = 1
		4, 5:
			count = 3
	var result: Array[Vector2i] = []
	for index in count:
		result.append(SPECIAL_EVENT_WINDOWS[index])
	return result


static func special_event_kind(window_index: int, unit_roll: float) -> StringName:
	# The last high-danger event is always an elite. Earlier events use a
	# deterministic 60/40 elite/horde split supplied by the run RNG.
	if window_index >= SPECIAL_EVENT_WINDOWS.size() - 1:
		return &"elite"
	return &"elite" if clampf(unit_roll, 0.0, 1.0) < 0.60 else &"horde"


static func material_drop_chance(wave_number: int) -> float:
	if wave_number <= 4:
		return 1.0
	return maxf(0.50, 1.0 - 0.015 * float(maxi(0, wave_number)))


static func should_drop_material(run_seed: int, wave_number: int, kill_index: int) -> bool:
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = (
		run_seed
		^ MATERIAL_STREAM_OFFSET
		^ (maxi(1, wave_number) * 1_000_003)
		^ (maxi(1, kill_index) * 97_409)
	)
	return roll_rng.randf() < material_drop_chance(wave_number)


static func harvesting_grows_after_wave(wave_number: int) -> bool:
	return wave_number >= 1 and wave_number < STANDARD_FINAL_WAVE


static func final_boss_base_health_multiplier(difficulty_level: int) -> float:
	return 0.75 if difficulty_level >= 5 else 1.0
