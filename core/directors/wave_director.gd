class_name WaveDirector
extends RefCounted


const WAVE_RULES := preload("res://core/directors/core_wave_rules.gd")
const STREAM_OFFSET := 0x57415645
const SCHEDULE_OFFSET := 0x454E434F
const ELITE_IDS: Array[StringName] = [&"enemy/iron_maw", &"enemy/volt_stalker"]

var catalog: ContentCatalog
var rng := RandomNumberGenerator.new()
var _run_seed := 0
var _schedule_cache: Dictionary = {}


func _init(content_catalog: ContentCatalog = null, run_seed: int = 0) -> void:
	catalog = content_catalog
	_run_seed = run_seed
	rng.seed = run_seed ^ STREAM_OFFSET


func select_enemy_id(
	wave: WaveDef,
	priority_state: Variant = false,
	difficulty_level: int = 1
) -> StringName:
	if wave == null or catalog == null:
		return &""
	var priority_count := (
		int(priority_state)
		if priority_state is int
		else (1 if bool(priority_state) else 0)
	)
	var priority_ids := _priority_enemy_ids(wave, difficulty_level)
	var priority_limit := priority_spawn_limit(wave, difficulty_level)
	if priority_count < priority_limit:
		if priority_limit == 1 and priority_ids.size() > 1:
			return priority_ids[rng.randi_range(0, priority_ids.size() - 1)]
		return priority_ids[priority_count]

	var candidates: Array[WaveSpawnDef] = []
	var horde_candidates: Array[WaveSpawnDef] = []
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn == null or spawn.is_priority_spawn():
			continue
		var enemy := catalog.get_enemy(spawn.enemy_id)
		if enemy == null:
			continue
		candidates.append(spawn)
		if _is_horde_enemy(enemy):
			horde_candidates.append(spawn)
	if encounter_kind(wave.wave_number, difficulty_level) == &"horde" \
	and not horde_candidates.is_empty():
		candidates = horde_candidates
	if candidates.is_empty():
		return &""
	var weights := PackedFloat32Array()
	for spawn: WaveSpawnDef in candidates:
		weights.append(maxf(0.01, spawn.weight))
	return candidates[rng.rand_weighted(weights)].enemy_id


func encounter_schedule(difficulty_level: int) -> Dictionary:
	var normalized_level := clampi(difficulty_level, 1, 5)
	if _schedule_cache.has(normalized_level):
		return (_schedule_cache[normalized_level] as Dictionary).duplicate(true)
	var schedule: Dictionary = {20: &"boss"}
	var event_windows: Array[Vector2i] = WAVE_RULES.special_event_windows(normalized_level)
	if not event_windows.is_empty():
		var schedule_rng := RandomNumberGenerator.new()
		schedule_rng.seed = (
			_run_seed ^ SCHEDULE_OFFSET ^ (normalized_level * 1_000_033)
		)
		for window_index in event_windows.size():
			var window: Vector2i = event_windows[window_index]
			var event_wave := schedule_rng.randi_range(window.x, window.y)
			var event_kind: StringName = WAVE_RULES.special_event_kind(
				window_index, schedule_rng.randf()
			)
			schedule[event_wave] = event_kind
	_schedule_cache[normalized_level] = schedule.duplicate(true)
	return schedule


func encounter_kind(wave_number: int, difficulty_level: int) -> StringName:
	if wave_number > 20:
		return &"standard"
	return StringName(encounter_schedule(difficulty_level).get(wave_number, &"standard"))


func encounter_waves(kind: StringName, difficulty_level: int) -> Array[int]:
	var result: Array[int] = []
	for raw_wave_number: Variant in encounter_schedule(difficulty_level).keys():
		var wave_number := int(raw_wave_number)
		if encounter_kind(wave_number, difficulty_level) == kind:
			result.append(wave_number)
	result.sort()
	return result


func encounter_density_multiplier(wave_number: int, difficulty_level: int) -> float:
	return 1.45 if encounter_kind(wave_number, difficulty_level) == &"horde" else 1.0


func priority_spawn_limit(wave: WaveDef, difficulty_level: int = 1) -> int:
	if wave == null:
		return 0
	if wave.wave_number > 20:
		return mini(wave.priority_spawn_count, _explicit_priority_ids(wave).size())
	match encounter_kind(wave.wave_number, difficulty_level):
		&"boss":
			var difficulty := DifficultyDef.for_level(clampi(difficulty_level, 1, 5))
			var desired := difficulty.final_boss_count() if difficulty != null else 1
			return mini(desired, _explicit_priority_ids(wave, true, false).size())
		&"elite":
			return 1 if not _planned_elite_ids(wave.wave_number, difficulty_level).is_empty() else 0
	return 0


func is_priority_enemy_id(
	wave: WaveDef,
	enemy_id: StringName,
	difficulty_level: int = 1
) -> bool:
	return enemy_id in _priority_enemy_ids(wave, difficulty_level)


func is_final_wave(wave_number: int, run_mode: int = RunMode.STANDARD) -> bool:
	if run_mode == RunMode.ENDLESS:
		return false
	if catalog == null:
		return false
	var final_wave := 0
	for wave: WaveDef in catalog.get_waves():
		if wave != null:
			final_wave = maxi(final_wave, wave.wave_number)
	return final_wave > 0 and wave_number >= final_wave


func _priority_enemy_ids(wave: WaveDef, difficulty_level: int) -> Array[StringName]:
	if wave.wave_number > 20:
		return _explicit_priority_ids(wave)
	match encounter_kind(wave.wave_number, difficulty_level):
		&"boss":
			return _explicit_priority_ids(wave, true, false)
		&"elite":
			return _planned_elite_ids(wave.wave_number, difficulty_level)
	return [] as Array[StringName]


func _planned_elite_ids(wave_number: int, difficulty_level: int) -> Array[StringName]:
	var elite_waves := encounter_waves(&"elite", difficulty_level)
	var event_index := elite_waves.find(wave_number)
	if event_index < 0:
		return [] as Array[StringName]
	var first_index := 0
	if difficulty_level > 1:
		first_index = int(abs(_run_seed ^ SCHEDULE_OFFSET)) % ELITE_IDS.size()
	var selected_id := ELITE_IDS[(first_index + event_index) % ELITE_IDS.size()]
	return [selected_id] as Array[StringName] if catalog.get_enemy(selected_id) != null else [] as Array[StringName]


func _explicit_priority_ids(
	wave: WaveDef,
	include_bosses: bool = true,
	include_elites: bool = true
) -> Array[StringName]:
	var result: Array[StringName] = []
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn == null or catalog.get_enemy(spawn.enemy_id) == null:
			continue
		if (spawn.is_boss and include_bosses) or (spawn.is_elite and include_elites):
			result.append(spawn.enemy_id)
	result.sort_custom(func(first: StringName, second: StringName) -> bool:
		return String(first) < String(second)
	)
	return result


static func _is_horde_enemy(enemy: EnemyDef) -> bool:
	if enemy == null:
		return false
	if &"swarm" in enemy.tags or &"chaser_fast" in enemy.tags:
		return true
	return enemy.behavior != null and enemy.behavior.role_id == &"swarm"
