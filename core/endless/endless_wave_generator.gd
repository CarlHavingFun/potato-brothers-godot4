class_name EndlessWaveGenerator
extends RefCounted


const STREAM_OFFSET := 0x454E444C

var catalog: ContentCatalog
var run_seed: int
var scaling: EndlessScalingDef


func _init(
	content_catalog: ContentCatalog = null,
	seed_value: int = 0,
	scaling_definition: EndlessScalingDef = null
) -> void:
	catalog = content_catalog
	run_seed = seed_value
	scaling = scaling_definition if scaling_definition != null else EndlessScalingDef.new()


func generate(wave_number: int, difficulty: int) -> WaveDef:
	if catalog == null or wave_number < 21:
		return null
	var cycle := floori(float(wave_number - 21) / 5.0) + 1
	var cycle_position := ((wave_number - 21) % 5) + 1
	var wave := WaveDef.new()
	wave.content_id = StringName("wave/endless/%03d" % wave_number)
	wave.presentation_id = &"wave.endless"
	wave.wave_number = wave_number
	wave.duration = 60.0
	wave.fixed_spawn_time = 0.8
	wave.endless_cycle = cycle
	wave.spawn_density_multiplier = scaling.density_multiplier(wave_number)
	wave.tags = [&"endless"]
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ STREAM_OFFSET ^ (wave_number * 1_000_003) ^ (difficulty * 97_409)
	var normal_count := clampi(3 + floori(float(difficulty) / 2.0), 3, 5)
	for enemy: EnemyDef in _pick_normal_enemies(rng, normal_count):
		wave.spawns.append(_spawn_for(enemy, 1.0, false, false))
	if cycle_position <= 3:
		wave.tags.append(&"mixed")
	elif cycle_position == 4:
		wave.tags.append(&"high_pressure")
		wave.tags.append(&"horde" if cycle % 2 == 1 else &"specialist")
		for spawn: WaveSpawnDef in wave.spawns:
			spawn.weight *= 1.5
	else:
		var boss_wave := cycle % 2 == 0
		if boss_wave:
			wave.tags.append(&"boss_wave")
			var bosses := _sorted_enemies_with_tag(&"boss")
			var boss_count := mini(2 if wave_number >= 50 else 1, bosses.size())
			var start_index := maxi(0, floori(float(cycle) / 2.0) - 1)
			for index in boss_count:
				var boss: EnemyDef = bosses[(start_index + index) % bosses.size()]
				wave.spawns.push_front(_spawn_for(boss, 1.0, true, false))
			wave.priority_spawn_count = boss_count
		else:
			wave.tags.append(&"elite_wave")
			var elites := _sorted_enemies_with_tag(&"elite")
			if not elites.is_empty():
				var elite_index := floori(float(cycle - 1) / 2.0) % elites.size()
				wave.spawns.push_front(_spawn_for(elites[elite_index], 1.0, false, true))
				wave.priority_spawn_count = 1
	return wave


func _pick_normal_enemies(rng: RandomNumberGenerator, count: int) -> Array[EnemyDef]:
	var pool: Array[EnemyDef] = []
	for enemy: EnemyDef in catalog.get_enemies():
		if enemy != null and &"normal" in enemy.tags and &"boss" not in enemy.tags and &"elite" not in enemy.tags:
			pool.append(enemy)
	pool.sort_custom(func(first: EnemyDef, second: EnemyDef) -> bool:
		return String(first.content_id) < String(second.content_id)
	)
	var result: Array[EnemyDef] = []
	while not pool.is_empty() and result.size() < count:
		result.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return result


func _sorted_enemies_with_tag(tag: StringName) -> Array[EnemyDef]:
	var result: Array[EnemyDef] = []
	for enemy: EnemyDef in catalog.get_enemies():
		if enemy != null and tag in enemy.tags:
			result.append(enemy)
	result.sort_custom(func(first: EnemyDef, second: EnemyDef) -> bool:
		return String(first.content_id) < String(second.content_id)
	)
	return result


func _spawn_for(enemy: EnemyDef, weight: float, boss: bool, elite: bool) -> WaveSpawnDef:
	var spawn := WaveSpawnDef.new()
	spawn.enemy_id = enemy.get_stable_id(catalog.pack_id)
	spawn.weight = weight
	spawn.is_boss = boss
	spawn.is_elite = elite
	return spawn
