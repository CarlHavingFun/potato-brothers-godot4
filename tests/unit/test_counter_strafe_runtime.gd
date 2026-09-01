extends GdUnitTestSuite


const MOVE_DELTA := 1.0 / 60.0


func before_test() -> void:
	_release_move_actions()


func after_test() -> void:
	_release_move_actions()


func test_release_and_reverse_input_brake_without_instant_stop_or_flip() -> void:
	var player := _player_with_stats(220.0)
	Input.action_press(&"move_right")
	player._physics_process(0.25)
	assert_float(player.velocity.x).is_equal_approx(220.0, 0.001)

	Input.action_release(&"move_right")
	player._physics_process(MOVE_DELTA)
	assert_float(player.velocity.x).is_greater(0.0)
	assert_float(player.velocity.x).is_less(220.0)

	player.velocity = Vector2(220.0, 0.0)
	Input.action_press(&"move_left")
	player._physics_process(MOVE_DELTA)
	assert_float(player.velocity.x).is_greater(0.0)
	assert_float(player.velocity.x).is_less(220.0)


func test_counter_strafe_brake_stat_stops_real_input_motion_sooner() -> void:
	var baseline := _player_with_stats(220.0)
	var counter_strafer := _player_with_stats(220.0, {&"counter_strafe_brake": 100.0})
	var baseline_frames := _frames_to_stop(baseline, 220.0)
	var counter_strafe_frames := _frames_to_stop(counter_strafer, 220.0)
	assert_int(counter_strafe_frames).is_less(baseline_frames)
	assert_int(counter_strafe_frames).is_greater(1)


func test_diagonal_real_input_does_not_exceed_movement_speed() -> void:
	var player := _player_with_stats(220.0)
	Input.action_press(&"move_right")
	Input.action_press(&"move_up")
	player._physics_process(MOVE_DELTA)
	assert_float(player.velocity.length()).is_less_equal(220.001)


func test_ranged_real_projectiles_and_recoil_increase_with_actual_player_speed() -> void:
	var stationary := _ranged_weapon_for(_player_with_stats(220.0))
	var moving_owner := _player_with_stats(220.0)
	Input.action_press(&"move_right")
	moving_owner._physics_process(0.25)
	var moving := _ranged_weapon_for(moving_owner)

	var stationary_angle := _fire_single_projectile_angle(stationary)
	var stationary_kick := _peak_visual_kick(stationary)
	var moving_angle := _fire_single_projectile_angle(moving)
	var moving_kick := _peak_visual_kick(moving)

	assert_float(absf(moving_angle)).is_greater(absf(stationary_angle) + 0.01)
	assert_float(moving_kick).is_greater(stationary_kick)


func test_fixed_235_speed_reference_sets_the_full_movement_spread() -> void:
	var owner := _player_with_stats(235.0)
	Input.action_press(&"move_right")
	owner._physics_process(0.25)
	var weapon := _ranged_weapon_for(owner)
	assert_float(absf(_fire_single_projectile_angle(weapon))).is_equal_approx(deg_to_rad(3.0), 0.0001)


func test_moving_recoil_control_reduces_real_projectile_and_kick_penalty() -> void:
	var unassisted_owner := _player_with_stats(220.0)
	var controlled_owner := _player_with_stats(220.0, {&"moving_recoil_control": 75.0})
	for player: GogoPlayerActor in [unassisted_owner, controlled_owner]:
		Input.action_press(&"move_right")
		player._physics_process(0.25)
		Input.action_release(&"move_right")
	var unassisted := _ranged_weapon_for(unassisted_owner)
	var controlled := _ranged_weapon_for(controlled_owner)

	var unassisted_angle := absf(_fire_single_projectile_angle(unassisted))
	var unassisted_kick := _peak_visual_kick(unassisted)
	var controlled_angle := absf(_fire_single_projectile_angle(controlled))
	var controlled_kick := _peak_visual_kick(controlled)

	assert_float(controlled_angle).is_less(unassisted_angle)
	assert_float(controlled_kick).is_less(unassisted_kick)


func test_stationary_ranged_shot_keeps_its_authored_spread_and_kick() -> void:
	var owner := _player_with_stats(220.0)
	var weapon := _ranged_weapon_for(owner)
	var angle := _fire_single_projectile_angle(weapon)
	var kick := _peak_visual_kick(weapon)
	assert_float(angle).is_equal_approx(0.0, 0.001)
	assert_float(kick).is_equal_approx(25.0, 0.001)


func test_melee_running_contact_and_pose_ignore_ranged_movement_penalty() -> void:
	var owner := _player_with_stats(235.0)
	Input.action_press(&"move_right")
	owner._physics_process(0.25)
	Input.action_release(&"move_right")
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	add_child(weapon)
	add_child(enemy)
	var enemy_definition := GogoEnemyDefinition.new()
	enemy_definition.max_health = 100.0
	enemy_definition.xp_value = 0
	enemy_definition.material_value = 0
	enemy.configure(enemy_definition, null, GogoDifficultyDefinition.new())
	enemy.global_position = owner.global_position + Vector2(80.0, 0.0)
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.MELEE
	stats.cooldown_seconds = 0.5
	stats.attack_range = 92.0
	stats.damage = 7.0
	stats.feedback_profile_id = &"heavy"
	weapon.configure(stats, owner)
	weapon._physics_process(0.0)
	weapon._physics_process(weapon.debug_melee_seconds_until_contact() + 0.001)
	assert_float(enemy.current_health).is_equal_approx(93.0, 0.001)
	assert_float(weapon._melee_visual_position.length()).is_greater(0.0)


func test_movement_spread_uses_owner_velocity_not_weapon_socket_position() -> void:
	var owner := _player_with_stats(220.0)
	owner.velocity = Vector2(220.0, 0.0)
	var near_weapon := _ranged_weapon_for(owner)
	var offset_weapon := _ranged_weapon_for(owner)
	offset_weapon.global_position = Vector2(160.0, 48.0)
	assert_float(_fire_single_projectile_angle(near_weapon)).is_equal_approx(
		_fire_single_projectile_angle(offset_weapon),
		0.001
	)


func test_arena_clamp_clears_real_input_velocity_at_the_boundary() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.arena_rect = Rect2(0.0, 0.0, 500.0, 500.0)
	var player := _player_with_stats(235.0)
	player.combat_world = world
	# move_and_slide consumes the engine physics tick rather than this direct test
	# call's delta, so begin outside the legal clamp edge to exercise the real
	# post-move arena correction deterministically.
	player.global_position = Vector2(480.0, 250.0)
	Input.action_press(&"move_right")
	player._physics_process(0.25)
	assert_float(player.velocity.length()).is_zero()
	assert_float(player.global_position.x).is_less_equal(440.001)


func test_session_change_clears_carried_movement_velocity() -> void:
	var first_session := _session_with_player()
	var next_session := _session_with_player()
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	player.session = first_session
	player.velocity = Vector2(235.0, 0.0)
	player.configure(next_session, null)
	assert_vector(player.velocity).is_equal(Vector2.ZERO)


func test_extreme_stat_values_cap_real_braking_and_movement_penalty() -> void:
	var capped_brake := _player_with_stats(235.0, {&"counter_strafe_brake": 200.0})
	var excessive_brake := _player_with_stats(235.0, {&"counter_strafe_brake": 999.0})
	assert_int(_frames_to_stop(capped_brake, 235.0)).is_equal(
		_frames_to_stop(excessive_brake, 235.0)
	)

	var capped_control := _player_with_stats(235.0, {&"moving_recoil_control": 80.0})
	var excessive_control := _player_with_stats(235.0, {&"moving_recoil_control": 999.0})
	for player: GogoPlayerActor in [capped_control, excessive_control]:
		Input.action_press(&"move_right")
		player._physics_process(0.25)
		Input.action_release(&"move_right")
	var capped_weapon := _ranged_weapon_for(capped_control)
	var excessive_weapon := _ranged_weapon_for(excessive_control)
	assert_float(_fire_single_projectile_angle(capped_weapon)).is_equal_approx(
		_fire_single_projectile_angle(excessive_weapon),
		0.0001
	)
	assert_float(_peak_visual_kick(capped_weapon)).is_equal_approx(
		_peak_visual_kick(excessive_weapon),
		0.001
	)


func test_higher_actual_speeds_keep_increasing_ranged_spread_and_bounded_kick() -> void:
	var angles: Array[float] = []
	var kicks: Array[float] = []
	for speed in [235.0, 470.0, 705.0]:
		var owner := _player_with_stats(speed)
		owner.velocity = Vector2(speed, 0.0)
		var weapon := _ranged_weapon_for(owner)
		angles.append(absf(_fire_single_projectile_angle(weapon)))
		kicks.append(_peak_visual_kick(weapon))
	assert_float(angles[0]).is_less(angles[1])
	assert_float(angles[1]).is_less(angles[2])
	# Pixel kick is intentionally rounded, so a nearby speed can quantize to the
	# same pixel. These spaced samples must still increase and remain bounded.
	assert_float(kicks[0]).is_less(kicks[1])
	assert_float(kicks[1]).is_less(kicks[2])
	assert_float(kicks[2]).is_less_equal(50.0)


func test_opposite_input_never_crosses_zero_in_one_update_at_supported_cadences() -> void:
	for initial_speed in [5.0, 20.0, 235.0]:
		for brake in [0.0, 200.0]:
			for delta in [1.0 / 120.0, 1.0 / 60.0, 1.0 / 30.0, 0.05, 0.20]:
				var player := _player_with_stats(235.0, {&"counter_strafe_brake": brake})
				player.velocity = Vector2(initial_speed, 0.0)
				Input.action_press(&"move_left")
				player._physics_process(delta)
				Input.action_release(&"move_left")
				assert_float(player.velocity.x).is_greater_equal(0.0)


func test_opposite_input_counter_strafe_stat_reaches_real_zero_sooner() -> void:
	var frames_by_brake: Array[int] = []
	for brake in [0.0, 100.0, 200.0]:
		var player := _player_with_stats(235.0, {&"counter_strafe_brake": brake})
		player.velocity = Vector2(235.0, 0.0)
		Input.action_press(&"move_left")
		var stop_frame := -1
		var crossed_zero := false
		for frame in 60:
			player._physics_process(MOVE_DELTA)
			if player.velocity.x < 0.0:
				crossed_zero = true
				break
			if is_zero_approx(player.velocity.x):
				stop_frame = frame + 1
				break
		Input.action_release(&"move_left")
		assert_bool(crossed_zero).is_false()
		if not crossed_zero:
			assert_int(stop_frame).is_greater(0)
			frames_by_brake.append(stop_frame)
	if frames_by_brake.size() == 3:
		assert_int(frames_by_brake[1]).is_less(frames_by_brake[0])
		assert_int(frames_by_brake[2]).is_less(frames_by_brake[1])


func test_real_physics_boundary_crossing_clears_velocity_before_next_ranged_shot() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.arena_rect = Rect2(0.0, 0.0, 500.0, 500.0)
	var player := _player_with_stats(235.0)
	player.combat_world = world
	player.global_position = Vector2(439.0, 250.0)
	player.velocity = Vector2(235.0, 0.0)
	player.set_physics_process(true)
	Input.action_press(&"move_right")
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release(&"move_right")
	player.set_physics_process(false)
	assert_float(player.global_position.x).is_equal_approx(440.0, 0.001)
	assert_float(player.global_position.x).is_greater(439.0)
	assert_float(player.velocity.length()).is_zero()
	var weapon := _ranged_weapon_for(player)
	assert_float(_fire_single_projectile_angle(weapon)).is_equal_approx(0.0, 0.001)
	assert_float(_peak_visual_kick(weapon)).is_equal_approx(25.0, 0.001)


func _player_with_stats(speed: float, extra_stats: Dictionary = {}) -> GogoPlayerActor:
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	var state := SessionPlayerState.new()
	state.final_stats = {&"movement_speed": speed}
	for key: StringName in extra_stats:
		state.final_stats[key] = extra_stats[key]
	player.player_state = state
	add_child(player)
	player.set_physics_process(false)
	return player


func _session_with_player() -> GameSession:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	run_state.players.append(SessionPlayerState.new())
	session.run_state = run_state
	return session


func _ranged_weapon_for(owner: GogoPlayerActor) -> GogoWeaponInstance:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	owner.combat_world = world
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	add_child(weapon)
	weapon.static_asset_snapshot_override = _weapon_visual_snapshot()
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.static_asset_id = &"service_pistol"
	stats.projectile_count = 1
	stats.projectile_speed = 500.0
	stats.damage = 1.0
	stats.spread_degrees = 0.0
	stats.feedback_profile_id = &"rifle"
	weapon.configure(stats, owner)
	return weapon


func _fire_single_projectile_angle(weapon: GogoWeaponInstance) -> float:
	var world := weapon.owner_actor.combat_world
	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	var projectile := world.projectile_layer.get_child(-1) as GogoProjectile
	return projectile.direction.angle()


func _peak_visual_kick(weapon: GogoWeaponInstance) -> float:
	weapon.recoil_active = true
	weapon.recoil_elapsed = GogoWeaponInstance.RECOIL_OUT_SECONDS
	weapon._update_visual_feedback()
	return absf(weapon.weapon_visual_root.position.x)


func _frames_to_stop(player: GogoPlayerActor, initial_speed: float) -> int:
	player.velocity = Vector2(initial_speed, 0.0)
	for frame in 60:
		player._physics_process(MOVE_DELTA)
		if player.velocity.length() <= 0.001:
			return frame + 1
	return 60


func _release_move_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)


func _weapon_visual_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color8(58, 66, 74, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"service_pistol|world_sprite|",
		"asset_id": &"service_pistol",
		"role": &"world_sprite",
		"selector": &"",
		"display_size_px": Vector2i(128, 128),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(32, 64),
		"anchors_px": {"muzzle": Vector2i(112, 48)},
		"atlas_rect_px": Rect2i(0, 0, 128, 128),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"counter_strafe_fixture",
		70,
		{&"service_pistol": &"ready"},
		{"service_pistol|world_sprite|": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot
