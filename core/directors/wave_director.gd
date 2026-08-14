class_name WaveDirector
extends RefCounted


const STREAM_OFFSET := 0x57415645

var catalog: ContentCatalog
var rng := RandomNumberGenerator.new()


func _init(content_catalog: ContentCatalog = null, run_seed: int = 0) -> void:
	catalog = content_catalog
	rng.seed = run_seed ^ STREAM_OFFSET


func select_enemy_id(wave: WaveDef, boss_already_spawned: bool) -> StringName:
	if wave == null or catalog == null:
		return &""
	if not boss_already_spawned:
		for spawn: WaveSpawnDef in wave.spawns:
			if spawn != null and spawn.is_boss and catalog.get_enemy(spawn.enemy_id) != null:
				return spawn.enemy_id
	var candidates: Array[WaveSpawnDef] = []
	var weights := PackedFloat32Array()
	for spawn: WaveSpawnDef in wave.spawns:
		if spawn == null or (spawn.is_boss and boss_already_spawned):
			continue
		if catalog.get_enemy(spawn.enemy_id) == null:
			continue
		candidates.append(spawn)
		weights.append(maxf(0.01, spawn.weight))
	if candidates.is_empty():
		return &""
	return candidates[rng.rand_weighted(weights)].enemy_id


func is_final_wave(wave_number: int) -> bool:
	if catalog == null:
		return false
	var final_wave := 0
	for wave: WaveDef in catalog.get_waves():
		if wave != null:
			final_wave = maxi(final_wave, wave.wave_number)
	return final_wave > 0 and wave_number >= final_wave
