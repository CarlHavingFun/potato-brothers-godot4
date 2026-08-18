extends GdUnitTestSuite


const DEFAULT_BOUNDS := preload("res://core/world/default_arena_bounds.tres")


func test_player_and_spawn_positions_share_the_same_playable_bounds() -> void:
	assert_vector(DEFAULT_BOUNDS.clamp_player_position(Vector2(5000.0, 5000.0))).is_equal(
		Vector2(966.0, 466.0)
	)
	assert_vector(DEFAULT_BOUNDS.clamp_spawn_position(Vector2(-5000.0, -5000.0))).is_equal(
		Vector2(-920.0, -420.0)
	)


func test_camera_center_accounts_for_viewport_and_shake_without_exposing_visual_void() -> void:
	var center := DEFAULT_BOUNDS.clamp_camera_center(
		Vector2(5000.0, 5000.0), Vector2(1920.0, 1080.0), Vector2(18.0, 12.0)
	)
	assert_vector(center).is_equal(Vector2(302.0, 108.0))
	var visible_half := Vector2(960.0, 540.0)
	var visual_rect := DEFAULT_BOUNDS.visual_rect()
	assert_bool(visual_rect.has_point(center + visible_half + Vector2(17.9, 11.9))).is_true()
	assert_bool(visual_rect.has_point(center - visible_half - Vector2(17.9, 11.9))).is_true()


func test_player_constraint_stops_outward_velocity_on_both_axes() -> void:
	var player := auto_free(
		load("res://scenes/unit/players/player_well_rounded.tscn").instantiate()
	) as Player
	add_child(player)
	await await_idle_frame()
	player.global_position = Vector2(1200.0, -700.0)
	player.velocity = Vector2(500.0, -500.0)

	assert_bool(player.constrain_to_arena()).is_true()
	assert_vector(player.global_position).is_equal(Vector2(966.0, -466.0))
	assert_vector(player.velocity).is_equal(Vector2.ZERO)


func test_spawner_unregisters_enemy_as_soon_as_it_exits_the_tree() -> void:
	var spawner := _new_spawner()
	var enemy := load(
		"res://scenes/unit/enemy/enemy_chaser_slow.tscn"
	).instantiate() as Enemy
	add_child(enemy)
	await await_idle_frame()
	spawner._register_enemy(enemy)
	assert_int(spawner.get_active_enemy_count()).is_equal(1)

	enemy.queue_free()
	await await_idle_frame()

	assert_int(spawner.get_active_enemy_count()).is_zero()


func test_spawner_uses_standard_wave_duration_and_active_enemy_cap() -> void:
	var spawner := _new_spawner()
	spawner.wave_index = 1
	spawner.start_wave()
	assert_float(spawner.wave_timer.wait_time).is_equal(20.0)

	var enemies: Array[Enemy] = []
	for _index: int in range(100):
		var enemy := Enemy.new()
		enemies.append(enemy)
		spawner._spawned_enemies.append(enemy)
	spawner.spawn_enemy()
	assert_int(spawner.get_active_enemy_count()).is_equal(100)
	for enemy: Enemy in enemies:
		enemy.free()
	spawner._spawned_enemies.clear()


func test_difficulty_five_boss_base_health_is_reduced_before_difficulty_scaling() -> void:
	var source := UnitStats.new()
	source.health = 100
	source.damage = 10.0
	source.speed = 100
	source.gold_drop = 1
	var result := Spawner.build_enemy_stats_for_wave(
		source, 1, 5, [&"boss"] as Array[StringName]
	)
	var difficulty := Content.catalog.get_difficulty(5)

	assert_int(result.health).is_equal(difficulty.scale_elite_health(75))


func _new_spawner() -> Spawner:
	var spawner: Spawner = auto_free(Spawner.new())
	var spawn_timer := Timer.new()
	spawn_timer.name = "SpawnTimer"
	spawner.add_child(spawn_timer)
	var wave_timer := Timer.new()
	wave_timer.name = "WaveTimer"
	spawner.add_child(wave_timer)
	add_child(spawner)
	return spawner
