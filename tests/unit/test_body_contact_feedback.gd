extends GdUnitTestSuite


const PLAYER_LAYER := 1
const ENEMY_LAYER := 1 << 1
const WORLD_LAYER := 1 << 7
const PLAYER_MASK := WORLD_LAYER
const ENEMY_MASK := ENEMY_LAYER | WORLD_LAYER
const FIXED_MOTION := Vector2(8.0, 0.0)


func before_test() -> void:
	_release_move_actions()


func after_test() -> void:
	_release_move_actions()


func test_player_crosses_real_enemy_but_world_wall_blocks_and_enemies_still_separate() -> void:
	var player := _player_actor()
	player.global_position = Vector2(-60.0, 0.0)
	var path_enemy := _enemy_actor(player, Vector2.ZERO)
	var wall := _world_wall(Vector2(80.0, 0.0))
	var crowd_enemy := _enemy_actor(player, Vector2(0.0, 80.0))
	var moving_enemy := _enemy_actor(player, Vector2(-40.0, 80.0))
	# The first signal resumes before the next physics step; the second guarantees
	# that newly added CharacterBody2D peers have completed one server sync.
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_int(player.collision_layer).is_equal(PLAYER_LAYER)
	assert_int(player.collision_mask).is_equal(PLAYER_MASK)
	for enemy: GogoEnemyActor in [path_enemy, crowd_enemy, moving_enemy]:
		assert_int(enemy.collision_layer).is_equal(ENEMY_LAYER)
		assert_int(enemy.collision_mask).is_equal(ENEMY_MASK)

	var wall_collision: KinematicCollision2D
	for _step in 24:
		var collision := player.move_and_collide(FIXED_MOTION)
		if collision != null:
			wall_collision = collision
			break
	assert_float(player.global_position.x).is_greater(20.0)
	assert_object(wall_collision).is_not_null()
	if wall_collision != null:
		assert_object(wall_collision.get_collider()).is_same(wall)

	var crowd_collision := moving_enemy.move_and_collide(Vector2(40.0, 0.0))
	assert_object(crowd_collision).is_not_null()
	if crowd_collision != null:
		assert_object(crowd_collision.get_collider()).is_same(crowd_enemy)
		assert_float(moving_enemy.global_position.distance_to(crowd_enemy.global_position)).is_greater_equal(
			GogoEnemyActor.BODY_RADIUS * 2.0
		)


func test_arena_clamp_still_bounds_player_and_clears_velocity() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.set_physics_process(false)
	world.arena_rect = Rect2(0.0, 0.0, 500.0, 500.0)
	var player := _player_actor()
	player.combat_world = world
	player.global_position = Vector2(480.0, 250.0)

	Input.action_press(&"move_right")
	player._physics_process(0.25)
	Input.action_release(&"move_right")

	assert_float(player.global_position.x).is_equal_approx(440.0, 0.001)
	assert_float(player.velocity.length()).is_zero()


func test_manual_contact_damage_keeps_34px_threshold_and_existing_cooldowns() -> void:
	var player := _player_actor()
	var enemy := _enemy_actor(player, Vector2(34.0, 0.0))
	var state := player.player_state

	enemy._physics_process(0.0)
	assert_float(state.current_health).is_equal(18.0)
	assert_float(player.damage_cooldown).is_equal_approx(0.35, 0.0001)
	assert_float(enemy.touch_cooldown).is_equal_approx(0.75, 0.0001)

	enemy._physics_process(0.0)
	assert_float(state.current_health).is_equal(18.0)
	player._physics_process(0.35)
	enemy._physics_process(0.35)
	assert_float(state.current_health).is_equal(18.0)

	player._physics_process(0.41)
	enemy._physics_process(0.41)
	assert_float(state.current_health).is_equal(16.0)

	enemy.global_position = Vector2(34.01, 0.0)
	enemy.touch_cooldown = 0.0
	player.damage_cooldown = 0.0
	enemy._physics_process(0.0)
	assert_float(state.current_health).is_equal(16.0)


func test_pickup_interaction_radius_tracks_visible_body_not_hurtbox_or_weapon_orbit() -> void:
	var player := _player_actor()
	assert_bool(player.has_method(&"pickup_interaction_radius")).is_true()
	if not player.has_method(&"pickup_interaction_radius"):
		return
	var contact_radius := float(player.call(&"pickup_interaction_radius"))
	assert_float(contact_radius).is_equal(60.0)
	assert_float(contact_radius).is_greater(GogoPlayerActor.PLAYER_BODY_RADIUS)

	var no_bounds: Array[Vector2i] = []
	var no_pivots: Array[Vector2i] = []
	player.cache_weapon_orbit_extent(160.0, no_bounds, no_pivots)
	assert_float(player.weapon_arena_clamp_margin()).is_equal(160.0)
	assert_float(float(player.call(&"pickup_interaction_radius"))).is_equal(contact_radius)


func _player_actor() -> GogoPlayerActor:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	var state := SessionPlayerState.new()
	state.max_health = 20.0
	state.current_health = 20.0
	state.final_stats = {
		&"movement_speed": 300.0,
		&"armor": 0.0,
		&"dodge": 0.0,
		&"pickup_range": 0.0,
	}
	run_state.players.append(state)
	session.run_state = run_state
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	player.session = session
	player.player_state = state
	add_child(player)
	player.set_physics_process(false)
	return player


func _enemy_actor(target: GogoPlayerActor, at: Vector2) -> GogoEnemyActor:
	var definition := GogoEnemyDefinition.new()
	definition.role = GogoEnemyDefinition.Role.CHASER
	definition.max_health = 10.0
	definition.movement_speed = 0.0
	definition.touch_damage = 2.0
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	enemy.configure(definition, target, GogoDifficultyDefinition.new())
	add_child(enemy)
	enemy.global_position = at
	enemy.set_physics_process(false)
	return enemy


func _world_wall(at: Vector2) -> StaticBody2D:
	var wall := auto_free(StaticBody2D.new()) as StaticBody2D
	wall.collision_layer = WORLD_LAYER
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 120.0)
	shape.shape = rectangle
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at
	return wall


func _release_move_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
