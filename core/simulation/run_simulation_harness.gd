class_name RunSimulationHarness
extends RefCounted


var catalog: ContentCatalog
var run_seed: int


func _init(content_catalog: ContentCatalog = null, seed_value: int = 0) -> void:
	catalog = content_catalog
	run_seed = seed_value


func simulate(target_wave: int, run_mode: int, difficulty: int = 1) -> Dictionary:
	if catalog == null or target_wave < 1 or not RunMode.is_valid(run_mode):
		return {}
	if run_mode == RunMode.STANDARD and target_wave > 20:
		return {}
	var run := RunState.new(run_seed)
	run.run_mode = run_mode
	run.difficulty = clampi(difficulty, 1, 5)
	run.phase = RunPhase.COMBAT
	_assign_representative_loadout(run)
	var director := WaveDirector.new(catalog, run_seed)
	var endless_generator := EndlessWaveGenerator.new(catalog, run_seed)
	var wave_records: Array[Dictionary] = []
	var boss_waves: Array[Dictionary] = []
	for wave_number: int in range(1, target_wave + 1):
		var wave := _wave_for(wave_number, run.difficulty, endless_generator)
		if wave == null:
			return {}
		var record := _simulate_wave(wave, director, run.difficulty)
		wave_records.append(record)
		var bosses: Array = record.get("bosses", [])
		if not bosses.is_empty():
			boss_waves.append({"wave": wave_number, "bosses": bosses.duplicate()})
			run.boss_kill_count += bosses.size()
		run.wave = wave_number
		run.highest_wave_reached = wave_number
		run.endless_cycle = wave.endless_cycle
		run.elapsed_seconds += wave.duration
		run.kill_count += maxi(1, roundi((12.0 + wave_number * 2.0) * wave.spawn_density_multiplier))
		if wave_number == 20:
			run.standard_victory_recorded = true
		if run_mode == RunMode.STANDARD and wave_number == 20:
			run.phase = RunPhase.VICTORY
		else:
			run.phase = RunPhase.SHOP
	run.rng_states["simulation_wave"] = target_wave
	var checkpoint := run.to_dict()
	var serialized_events := JSON.stringify(wave_records)
	return {
		"checkpoint": checkpoint,
		"event_hash": serialized_events.sha256_text(),
		"boss_waves": boss_waves,
		"wave_records": wave_records,
	}


func _assign_representative_loadout(run: RunState) -> void:
	var characters := catalog.get_characters()
	if not characters.is_empty():
		run.character_id = characters.front().get_stable_id(catalog.pack_id)
	var weapons := catalog.get_weapons()
	if not weapons.is_empty():
		run.starting_weapon_id = weapons.front().get_stable_id(catalog.pack_id)


func _wave_for(
	wave_number: int,
	difficulty: int,
	endless_generator: EndlessWaveGenerator
) -> WaveDef:
	if wave_number >= 21:
		return endless_generator.generate(wave_number, difficulty)
	for wave: WaveDef in catalog.get_waves():
		if wave != null and wave.wave_number == wave_number:
			return wave
	return null


func _simulate_wave(wave: WaveDef, director: WaveDirector, difficulty_level: int) -> Dictionary:
	var priority_ids: Array[String] = []
	var boss_ids: Array[String] = []
	var elite_ids: Array[String] = []
	var priority_limit := director.priority_spawn_limit(wave, difficulty_level)
	for priority_index: int in priority_limit:
		var enemy_id := director.select_enemy_id(wave, priority_index, difficulty_level)
		if enemy_id.is_empty():
			continue
		priority_ids.append(String(enemy_id))
		var enemy := catalog.get_enemy(enemy_id)
		if enemy != null and &"boss" in enemy.tags:
			boss_ids.append(String(enemy_id))
		elif enemy != null and &"elite" in enemy.tags:
			elite_ids.append(String(enemy_id))
	var sample_ids: Array[String] = []
	for sample_index: int in 3:
		var enemy_id := director.select_enemy_id(
			wave, priority_limit + sample_index, difficulty_level
		)
		if not enemy_id.is_empty():
			sample_ids.append(String(enemy_id))
	return {
		"wave": wave.wave_number,
		"cycle": wave.endless_cycle,
		"tags": wave.tags.map(func(tag: StringName): return String(tag)),
		"priority": priority_ids,
		"bosses": boss_ids,
		"elites": elite_ids,
		"sample": sample_ids,
		"density": snappedf(wave.spawn_density_multiplier, 0.0001),
		"encounter": String(director.encounter_kind(wave.wave_number, difficulty_level)),
	}
