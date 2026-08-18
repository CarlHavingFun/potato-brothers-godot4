extends Node2D
class_name Spawner

signal on_wave_completed
signal on_run_victory

@export var spawn_area_size := Vector2(1000, 500)

@onready var spawn_timer: Timer = $SpawnTimer
@onready var wave_timer: Timer = $WaveTimer

var wave_index := 1
var current_wave_definition: WaveDef
var current_wave_data: WaveData
var spawned_enemies: Array[Enemy] = []
var rng := RandomNumberGenerator.new()
var wave_director: WaveDirector
var boss_spawned := false
var priority_spawns_emitted := 0
var expected_priority_spawns := 0
var endless_generator: EndlessWaveGenerator


func find_wave_definition() -> WaveDef:
	if (
		Global.current_run != null
		and Global.current_run.run_mode == RunMode.ENDLESS
		and wave_index > 20
	):
		if endless_generator == null:
			endless_generator = EndlessWaveGenerator.new(
				Content.catalog, Global.current_run.random_seed
			)
		return endless_generator.generate(wave_index, Global.current_run.difficulty)
	for definition: WaveDef in Content.catalog.get_waves():
		if definition == null:
			continue
		if definition.wave_number == wave_index:
			return definition
		if definition.data != null and definition.data.is_valid_index(wave_index):
			return definition
	return null


func find_wave_data() -> WaveData:
	var definition := find_wave_definition()
	return definition.data if definition != null else null

func start_wave() -> void:
	current_wave_definition = find_wave_definition()
	current_wave_data = current_wave_definition.data if current_wave_definition != null else null
	if current_wave_definition == null:
		printerr("No valid wave.")
		spawn_timer.stop()
		wave_timer.stop()
		return
	boss_spawned = false
	priority_spawns_emitted = 0
	var wave_seed := (
		(Global.current_run.random_seed if Global.current_run != null else 0)
		+ wave_index * 1_000_003
	)
	rng.seed = wave_seed
	wave_director = WaveDirector.new(Content.catalog, wave_seed)
	var difficulty_level := Global.current_run.difficulty if Global.current_run != null else 1
	expected_priority_spawns = wave_director.priority_spawn_limit(
		current_wave_definition, difficulty_level
	)
	wave_timer.wait_time = current_wave_definition.duration
	wave_timer.start()
	
	set_spawn_timer()


func set_spawn_timer() -> void:
	var base_wait_time := 1.0
	if current_wave_definition != null and not current_wave_definition.spawns.is_empty():
		base_wait_time = current_wave_definition.fixed_spawn_time
	elif current_wave_data != null:
		match current_wave_data.spawn_type:
			WaveData.SpawnType.FIXED:
				base_wait_time = current_wave_data.fixed_spawn_time
			WaveData.SpawnType.RANDOM:
				base_wait_time = rng.randf_range(
					current_wave_data.min_spawn_time,
					current_wave_data.max_spawn_time
				)
	var difficulty_level := Global.current_run.difficulty if Global.current_run != null else 1
	var difficulty := Content.catalog.get_difficulty(difficulty_level)
	var density := difficulty.spawn_density_multiplier if difficulty != null else 1.0
	if current_wave_definition != null:
		density *= current_wave_definition.spawn_density_multiplier
	if wave_director != null:
		density *= wave_director.encounter_density_multiplier(wave_index, difficulty_level)
	spawn_timer.wait_time = base_wait_time / maxf(0.01, density)
	
	if spawn_timer.is_stopped():
		spawn_timer.start()


func get_random_spawn_position() -> Vector2:
	var candidate := Vector2.ZERO
	for attempt in 12:
		candidate = Vector2(
			rng.randf_range(-spawn_area_size.x, spawn_area_size.x),
			rng.randf_range(-spawn_area_size.y, spawn_area_size.y)
		)
		var arena := get_parent()
		if not arena is Arena or arena.ecology.is_spawn_position_safe(candidate):
			return candidate
	return candidate


func spawn_enemy() -> void:
	var enemy_definition := _get_random_enemy_definition()
	# Preserve the synchronous rejection path: callers and timers rely on an
	# invalid wave stopping immediately, before the spawn animation coroutine.
	if enemy_definition == null and current_wave_data == null:
		spawn_timer.stop()
		return
	await _spawn_enemy_definition(enemy_definition, get_random_spawn_position())
	set_spawn_timer()


func _spawn_enemy_definition(enemy_definition: EnemyDef, spawn_pos: Vector2) -> Enemy:
	var enemy_scene: PackedScene
	if enemy_definition != null:
		enemy_scene = enemy_definition.scene
	elif current_wave_data != null:
		enemy_scene = current_wave_data.get_random_unit_scene() as PackedScene
	else:
		spawn_timer.stop()
		return null
	if enemy_scene == null:
		spawn_timer.stop()
		return null
	if enemy_scene:
		var spawn_anim := Global.SPAWN_EFFECT_SCENE.instantiate()
		get_parent().add_child(spawn_anim)
		spawn_anim.global_position = spawn_pos
		await spawn_anim.anim_player.animation_finished
		spawn_anim.queue_free()
		
		var enemy_instance := enemy_scene.instantiate() as Enemy
		enemy_instance.definition = enemy_definition
		enemy_instance.reinforcement_requested.connect(_on_reinforcement_requested)
		if enemy_definition != null:
			Global.discover_content(enemy_definition.get_stable_id(Content.catalog.pack_id))
		enemy_instance.stats = build_enemy_stats_for_wave(
			enemy_definition.stats if enemy_definition != null else enemy_instance.stats,
			wave_index,
			Global.current_run.difficulty if Global.current_run != null else 1,
			enemy_definition.tags if enemy_definition != null else [] as Array[StringName],
			endless_generator.scaling if endless_generator != null and wave_index > 20 else null
		)
		enemy_instance.global_position = spawn_pos
		get_parent().add_child(enemy_instance)
		spawned_enemies.append(enemy_instance)
		return enemy_instance
	return null


func _on_reinforcement_requested(source: Enemy) -> void:
	if not is_instance_valid(source) or wave_timer.is_stopped():
		return
	var reinforcement := Content.catalog.get_enemy(&"enemy/swarm_mite")
	if reinforcement == null:
		return
	var angle := rng.randf_range(0.0, TAU)
	var position_near_source := source.global_position + Vector2.RIGHT.rotated(angle) * 90.0
	_spawn_enemy_definition(reinforcement, position_near_source)


func _get_random_enemy_definition() -> EnemyDef:
	if current_wave_definition == null or current_wave_definition.spawns.is_empty():
		return null
	if wave_director == null:
		wave_director = WaveDirector.new(Content.catalog, rng.seed)
	var difficulty_level := Global.current_run.difficulty if Global.current_run != null else 1
	if expected_priority_spawns <= 0:
		expected_priority_spawns = wave_director.priority_spawn_limit(
			current_wave_definition, difficulty_level
		)
	var enemy_id := wave_director.select_enemy_id(
		current_wave_definition,
		priority_spawns_emitted,
		difficulty_level
	)
	if enemy_id.is_empty():
		return null
	if (
		priority_spawns_emitted < expected_priority_spawns
		and wave_director.is_priority_enemy_id(
			current_wave_definition, enemy_id, difficulty_level
		)
	):
		var priority_definition := Content.catalog.get_enemy(enemy_id)
		boss_spawned = priority_definition != null and &"boss" in priority_definition.tags
		priority_spawns_emitted += 1
	return Content.catalog.get_enemy(enemy_id)


static func build_enemy_stats_for_wave(
	definition: UnitStats,
	wave: int,
	difficulty_level: int,
	enemy_tags: Array[StringName] = [],
	endless_scaling: EndlessScalingDef = null
) -> UnitStats:
	if definition == null:
		return null
	var result := definition.duplicate(true) as UnitStats
	var completed_waves := maxi(0, wave - 1)
	result.health = roundi(definition.health + definition.health_increase_per_wave * completed_waves)
	result.damage = definition.damage + definition.damage_increase_per_wave * completed_waves
	var difficulty := Content.catalog.get_difficulty(clampi(difficulty_level, 1, 5))
	if difficulty != null:
		result.health = (
			difficulty.scale_elite_health(result.health)
			if (&"elite" in enemy_tags or &"boss" in enemy_tags)
			else difficulty.scale_health(result.health)
		)
		result.damage = difficulty.scale_damage(result.damage)
		result.speed = roundi(difficulty.scale_speed(result.speed))
		result.gold_drop = difficulty.scale_material_drop(result.gold_drop)
	if endless_scaling != null and wave > 20:
		result.health = roundi(result.health * endless_scaling.health_multiplier(wave))
		result.damage *= endless_scaling.damage_multiplier(wave)
		result.speed = roundi(result.speed * endless_scaling.speed_multiplier(wave))
		result.gold_drop = maxi(1, floori(
			result.gold_drop * endless_scaling.material_drop_multiplier(wave)
		))
	return result


func clear_enemies() -> void:
	if spawned_enemies.size() > 0:
		for enemy: Enemy in spawned_enemies:
			if is_instance_valid(enemy):
				enemy.destroy_enemy()
	
	spawned_enemies.clear()


func get_wave_text() -> String:
	return "Wave %s" % wave_index


func get_wave_timer_text() -> String:
	return str(max(0, int(wave_timer.time_left)))


func _on_spawn_timer_timeout() -> void:
	if (current_wave_definition == null and current_wave_data == null) or wave_timer.is_stopped():
		spawn_timer.stop()
		return
	
	spawn_enemy()


func _on_wave_timer_timeout() -> void:
	complete_wave()


func complete_wave() -> bool:
	if Global.current_run == null or Global.current_run.phase != RunPhase.COMBAT:
		return false
	var director := wave_director
	if director == null:
		director = WaveDirector.new(Content.catalog, Global.current_run.random_seed)
	var final_wave := director.is_final_wave(wave_index, Global.current_run.run_mode)
	var next_phase := RunPhase.VICTORY if final_wave else RunPhase.UPGRADE
	if not Global.enter_phase(next_phase):
		return false
	if is_instance_valid(spawn_timer):
		spawn_timer.stop()
	if is_instance_valid(wave_timer):
		wave_timer.stop()
	clear_enemies()
	Global.current_run.highest_wave_reached = maxi(
		Global.current_run.highest_wave_reached, wave_index
	)
	Global.current_run.endless_cycle = (
		current_wave_definition.endless_cycle if current_wave_definition != null else 0
	)
	if final_wave:
		on_run_victory.emit()
	else:
		if Global.current_run.run_mode == RunMode.ENDLESS and wave_index == 20:
			Global.record_standard_victory_once()
		if Global.current_run.run_mode == RunMode.ENDLESS:
			Global.record_endless_progress()
		Global.get_harvesting_coins()
		on_wave_completed.emit()
	return true


func complete_boss_victory() -> bool:
	if wave_index < 20:
		return false
	if Global.current_run != null and Global.current_run.run_mode == RunMode.ENDLESS:
		return false
	if priority_spawns_emitted < expected_priority_spawns:
		return false
	for enemy: Enemy in spawned_enemies:
		if (
			is_instance_valid(enemy)
			and enemy.definition != null
			and &"boss" in enemy.definition.tags
			and enemy.health_component.current_health > 0.0
		):
			return false
	return complete_wave()
