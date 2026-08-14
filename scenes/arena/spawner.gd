extends Node2D
class_name Spawner

signal on_wave_completed

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


func find_wave_definition() -> WaveDef:
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
	var wave_seed := (
		(Global.current_run.random_seed if Global.current_run != null else 0)
		+ wave_index * 1_000_003
	)
	rng.seed = wave_seed
	wave_director = WaveDirector.new(Content.catalog, wave_seed)
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
	spawn_timer.wait_time = base_wait_time / maxf(0.01, density)
	
	if spawn_timer.is_stopped():
		spawn_timer.start()


func get_random_spawn_position() -> Vector2:
	var random_x := rng.randf_range(-spawn_area_size.x, spawn_area_size.x)
	var random_y := rng.randf_range(-spawn_area_size.y, spawn_area_size.y)
	return Vector2(random_x, random_y)


func spawn_enemy() -> void:
	var enemy_definition := _get_random_enemy_definition()
	var enemy_scene: PackedScene
	if enemy_definition != null:
		enemy_scene = enemy_definition.scene
	elif current_wave_data != null:
		enemy_scene = current_wave_data.get_random_unit_scene() as PackedScene
	else:
		spawn_timer.stop()
		return
	if enemy_scene == null:
		spawn_timer.stop()
		return
	if enemy_scene:
		var spawn_pos := get_random_spawn_position()
		
		var spawn_anim := Global.SPAWN_EFFECT_SCENE.instantiate()
		get_parent().add_child(spawn_anim)
		spawn_anim.global_position = spawn_pos
		await spawn_anim.anim_player.animation_finished
		spawn_anim.queue_free()
		
		var enemy_instance := enemy_scene.instantiate() as Enemy
		enemy_instance.stats = build_enemy_stats_for_wave(
			enemy_definition.stats if enemy_definition != null else enemy_instance.stats,
			wave_index,
			Global.current_run.difficulty if Global.current_run != null else 1
		)
		enemy_instance.global_position = spawn_pos
		get_parent().add_child(enemy_instance)
		spawned_enemies.append(enemy_instance)
	
	set_spawn_timer()


func _get_random_enemy_definition() -> EnemyDef:
	if current_wave_definition == null or current_wave_definition.spawns.is_empty():
		return null
	if wave_director == null:
		wave_director = WaveDirector.new(Content.catalog, rng.seed)
	var enemy_id := wave_director.select_enemy_id(current_wave_definition, boss_spawned)
	if enemy_id.is_empty():
		return null
	for spawn: WaveSpawnDef in current_wave_definition.spawns:
		if spawn != null and spawn.enemy_id == enemy_id and spawn.is_boss:
			boss_spawned = true
			break
	return Content.catalog.get_enemy(enemy_id)


static func build_enemy_stats_for_wave(definition: UnitStats, wave: int, difficulty_level: int) -> UnitStats:
	if definition == null:
		return null
	var result := definition.duplicate(true) as UnitStats
	var completed_waves := maxi(0, wave - 1)
	result.health = roundi(definition.health + definition.health_increase_per_wave * completed_waves)
	result.damage = definition.damage + definition.damage_increase_per_wave * completed_waves
	var difficulty := Content.catalog.get_difficulty(clampi(difficulty_level, 1, 5))
	if difficulty != null:
		result.health = difficulty.scale_health(result.health)
		result.damage = difficulty.scale_damage(result.damage)
		result.speed = roundi(difficulty.scale_speed(result.speed))
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
	if not current_wave_data or wave_timer.is_stopped():
		spawn_timer.stop()
		return
	
	spawn_enemy()


func _on_wave_timer_timeout() -> void:
	Global.enter_phase(RunPhase.UPGRADE)
	Global.get_harvesting_coins()
	on_wave_completed.emit()
	spawn_timer.stop()
	clear_enemies()
