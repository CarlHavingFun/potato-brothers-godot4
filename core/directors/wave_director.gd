class_name WaveDirector
extends RefCounted


const STREAM_OFFSET := 0x57415645

var catalog: ContentCatalog
var rng := RandomNumberGenerator.new()


func _init(content_catalog: ContentCatalog = null, run_seed: int = 0) -> void:
	catalog = content_catalog
	rng.seed = run_seed ^ STREAM_OFFSET


func select_enemy_id(wave: WaveDef, priority_state: Variant = false) -> StringName:
	if wave == null or catalog == null:
		return &""
	var priority_count := (
		int(priority_state)
		if priority_state is int
		else (1 if bool(priority_state) else 0)
	)
	var priority_spawns: Array[WaveSpawnDef] = []
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn != null and spawn.is_priority_spawn() and catalog.get_enemy(spawn.enemy_id) != null:
			priority_spawns.append(spawn)
	priority_spawns.sort_custom(func(first: WaveSpawnDef, second: WaveSpawnDef) -> bool:
		return String(first.enemy_id) < String(second.enemy_id)
	)
	var priority_limit := mini(wave.priority_spawn_count, priority_spawns.size())
	if priority_count < priority_limit:
		if priority_limit == 1 and priority_spawns.size() > 1:
			return priority_spawns[rng.randi_range(0, priority_spawns.size() - 1)].enemy_id
		return priority_spawns[priority_count].enemy_id
	var candidates: Array[WaveSpawnDef] = []
	var weights := PackedFloat32Array()
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn == null or spawn.is_priority_spawn():
			continue
		if catalog.get_enemy(spawn.enemy_id) == null:
			continue
		candidates.append(spawn)
		weights.append(maxf(0.01, spawn.weight))
	if candidates.is_empty():
		return &""
	return candidates[rng.rand_weighted(weights)].enemy_id


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
