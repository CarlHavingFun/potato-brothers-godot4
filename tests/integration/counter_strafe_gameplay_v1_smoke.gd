extends GdUnitTestSuite


const APP_SCENE := preload("res://game/app/app_root.tscn")
const STEP := 1.0 / 60.0


func after_test() -> void:
	_release_movement()


func test_real_niko_release_coasts_and_reverse_stops_sooner() -> void:
	var fixture := await _fixture()
	var player := fixture.player as GogoPlayerActor
	_run_right(player)
	var speed_before := player.velocity.x
	_release_movement()
	player._physics_process(STEP)
	assert_float(player.velocity.x).is_greater(0.0)
	assert_float(player.velocity.x).is_less(speed_before)
	var release_ticks := 1
	while player.velocity.x > 0.01 and release_ticks < 120:
		player._physics_process(STEP)
		release_ticks += 1
	assert_int(release_ticks).is_less(120)
	assert_float(player.velocity.length()).is_equal_approx(0.0, 0.01)
	_run_right(player)
	Input.action_release("move_right")
	Input.action_press("move_left")
	player._physics_process(STEP)
	assert_float(player.velocity.x).is_greater(0.0)
	var reverse_ticks := 1
	while player.velocity.x > 0.01 and reverse_ticks < 120:
		player._physics_process(STEP)
		reverse_ticks += 1
	assert_int(reverse_ticks).is_less(release_ticks)
	print("COUNTER_STRAFE_INPUT speed=%.2f release_ms=%.2f reverse_ms=%.2f" % [
		speed_before, release_ticks * STEP * 1000.0, reverse_ticks * STEP * 1000.0
	])
	_release_movement()


func test_real_glock_shot_is_less_stable_while_moving_and_recovers_after_stopping() -> void:
	var fixture := await _fixture()
	var player := fixture.player as GogoPlayerActor
	var idle := _shoot(fixture)
	assert_float(float(idle.angle)).is_equal_approx(0.0, 0.00001)
	await _capture(fixture, "01-idle-shot")
	_run_right(player)
	var moving := _shoot(fixture)
	assert_float(float(moving.angle)).is_greater(float(idle.angle) + 0.00001)
	assert_float(float(moving.kick)).is_greater(float(idle.kick))
	await _capture(fixture, "02-moving-shot")
	_release_movement()
	for _tick in 60:
		player._physics_process(STEP)
	var recovered := _shoot(fixture)
	assert_float(float(recovered.angle)).is_equal_approx(float(idle.angle), 0.00001)
	assert_float(float(recovered.kick)).is_equal_approx(float(idle.kick), 0.001)
	assert_vector((fixture.weapon as GogoWeaponInstance).position).is_equal(Vector2(0, 48))
	await _capture(fixture, "03-stopped-shot")
	print("COUNTER_STRAFE_SHOT idle_deg=%.5f moving_deg=%.5f recovered_deg=%.5f kick_px=%.1f/%.1f/%.1f" % [
		rad_to_deg(float(idle.angle)), rad_to_deg(float(moving.angle)), rad_to_deg(float(recovered.angle)),
		float(idle.kick), float(moving.kick), float(recovered.kick)
	])


func test_run_and_gun_modifier_reaches_live_shot_without_reducing_run_speed() -> void:
	var fixture := await _fixture()
	var player := fixture.player as GogoPlayerActor
	_run_right(player)
	var unmodified := _shoot(fixture)
	var speed_before := player.velocity.length()
	# A real pipeline modifier models the interface future obtainable items use.
	# It is not a shipped item and does not mutate canonical item definitions.
	player.player_state.final_stats = GogoStatPipeline.new().rebuild(
		player.player_state.base_stats,
		{&"equipment": [{&"moving_recoil_control": 50.0}]}
	)
	_run_right(player)
	var controlled := _shoot(fixture)
	assert_float(player.velocity.length()).is_equal_approx(speed_before, 0.001)
	assert_float(float(controlled.angle)).is_greater(0.0)
	assert_float(float(controlled.angle)).is_less(float(unmodified.angle))
	assert_float(float(controlled.kick)).is_less(float(unmodified.kick))
	print("COUNTER_STRAFE_CONTROL speed=%.2f uncontrolled_deg=%.5f controlled_deg=%.5f kick_px=%.1f/%.1f" % [
		player.velocity.length(), rad_to_deg(float(unmodified.angle)), rad_to_deg(float(controlled.angle)),
		float(unmodified.kick), float(controlled.kick)
	])
	_release_movement()


func test_faster_build_has_more_moving_instability_at_its_own_full_speed() -> void:
	var fixture := await _fixture()
	var player := fixture.player as GogoPlayerActor
	_run_right(player)
	var slow_speed := player.velocity.length()
	var slow_shot := _shoot(fixture)
	player.player_state.final_stats[&"movement_speed"] = slow_speed * 2.0
	_run_right(player)
	var fast_shot := _shoot(fixture)
	var fast_speed := player.velocity.length()
	assert_float(player.velocity.length()).is_greater(slow_speed)
	assert_float(float(fast_shot.angle)).is_greater(float(slow_shot.angle))
	assert_float(float(fast_shot.kick)).is_greater(float(slow_shot.kick))
	# A plateau above the old 352.5 px/s cutoff must not erase the added
	# instability of still-faster real builds. These shots use the live weapon.
	player.player_state.final_stats[&"movement_speed"] = slow_speed * 3.0
	_run_right(player)
	var faster_shot := _shoot(fixture)
	assert_float(player.velocity.length()).is_greater(fast_speed)
	assert_float(float(faster_shot.angle)).is_greater(float(fast_shot.angle) + 0.00001)
	assert_float(float(faster_shot.kick)).is_greater(float(fast_shot.kick))
	print("COUNTER_STRAFE_SPEED speeds=%.2f/%.2f/%.2f angles_deg=%.5f/%.5f/%.5f kick_px=%.1f/%.1f/%.1f" % [
		slow_speed, fast_speed, player.velocity.length(),
		rad_to_deg(float(slow_shot.angle)), rad_to_deg(float(fast_shot.angle)), rad_to_deg(float(faster_shot.angle)),
		float(slow_shot.kick), float(fast_shot.kick), float(faster_shot.kick)
	])
	_release_movement()


func test_live_reverse_braking_reaches_zero_before_direction_changes_at_large_step() -> void:
	var fixture := await _fixture()
	var player := fixture.player as GogoPlayerActor
	player.player_state.final_stats = GogoStatPipeline.new().rebuild(
		player.player_state.base_stats,
		{&"equipment": [{&"counter_strafe_brake": 200.0}]}
	)
	_run_right(player)
	var before := player.velocity.x
	Input.action_release("move_right")
	Input.action_press("move_left")
	player._physics_process(0.05)
	var braking := player.velocity.x
	# At the new 300px/s base, 5400px/s² for 50ms removes 270px/s.
	# A remaining 30px/s must still cause shot instability, not snap to rest.
	assert_float(braking).is_equal_approx(30.0, 0.001)
	var braking_shot := _shoot(fixture)
	assert_float(float(braking_shot.angle)).is_greater(0.0)
	player._physics_process(STEP)
	assert_float(player.velocity.x).is_equal_approx(0.0, 0.001)
	var stopped_shot := _shoot(fixture)
	assert_float(float(stopped_shot.angle)).is_equal_approx(0.0, 0.00001)
	player._physics_process(STEP)
	assert_float(player.velocity.x).is_less(0.0)
	print("COUNTER_STRAFE_REVERSE high_brake_pct=200 before=%.2f after_50ms=%.2f zero_next_tick_then_negative=%.2f stopped_angle_deg=%.5f" % [
		before, braking, player.velocity.x, rad_to_deg(float(stopped_shot.angle))
	])
	_release_movement()


func _fixture() -> Dictionary:
	_release_movement()
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(viewport)
	var app := APP_SCENE.instantiate() as AppKernel
	viewport.add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(app.boot_result != null and app.boot_result.is_ok()).is_true()
	var content := app.content_snapshot
	var static_snapshot := app.static_asset_service.active_snapshot()
	viewport.remove_child(app)
	app.free()
	var config := SessionConfig.new()
	config.seed = 30830
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	session.static_asset_snapshot = static_snapshot
	assert_int(session.start(config, content)).is_equal(OK)
	var world := CombatWorld.new()
	viewport.add_child(world)
	var wave := GogoWaveDefinition.new()
	wave.content_id = &"test.counter_strafe:wave/isolated"
	wave.duration_seconds = 120.0
	assert_int(world.start_wave(session, wave)).is_equal(OK)
	world.set_physics_process(false)
	var player := world.player_actor
	player.set_physics_process(false)
	player.global_position = Vector2(640, 372)
	var weapon := player.weapon_orbit.get_child(0) as GogoWeaponInstance
	weapon.set_physics_process(false)
	assert_object(weapon.weapon_visual_root).is_not_null()
	assert_int(weapon.stats.projectile_count).is_equal(1)
	var enemy := GogoEnemyActor.new()
	enemy.configure(
		content.definition(&"gogobro.core:enemy/drifter", &"enemy") as GogoEnemyDefinition,
		player,
		content.definition(config.difficulty_id, &"difficulty") as GogoDifficultyDefinition,
		world,
		world.allocate_runtime_instance_id(&"enemy")
	)
	world.enemy_layer.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + Vector2(200, 0)
	enemy.current_health = 10000.0
	assert_bool(world.register_active_enemy(enemy)).is_true()
	return {"world": world, "player": player, "weapon": weapon, "enemy": enemy, "session": session, "viewport": viewport}


func _run_right(player: GogoPlayerActor) -> void:
	_release_movement()
	Input.action_press("move_right")
	for _tick in 30:
		player._physics_process(STEP)


func _shoot(fixture: Dictionary) -> Dictionary:
	var world := fixture.world as CombatWorld
	var weapon := fixture.weapon as GogoWeaponInstance
	var player := fixture.player as GogoPlayerActor
	var enemy := fixture.enemy as GogoEnemyActor
	for child in world.projectile_layer.get_children():
		child.free()
	world.feedback_presenter.clear_feedback()
	enemy.global_position = player.global_position + Vector2(200, 0)
	var expected_direction := (enemy.global_position - weapon.global_position).normalized()
	(fixture.session as GameSession).rng.seed = 91531
	weapon.cooldown_remaining = 0.0
	weapon._physics_process(STEP)
	assert_int(world.projectile_layer.get_child_count()).is_equal(1)
	var projectile := world.projectile_layer.get_child(0) as GogoProjectile
	projectile.set_physics_process(false)
	var angle := absf(expected_direction.angle_to(projectile.direction))
	weapon._physics_process(GogoWeaponInstance.RECOIL_OUT_SECONDS)
	return {"angle": angle, "kick": weapon.weapon_visual_root.position.length()}


func _release_movement() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)


func _capture(fixture: Dictionary, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var world := fixture.world as CombatWorld
	# The fixture advances the actor manually; update its real camera before the
	# first rendered frame as well, rather than capturing the previous arena center.
	world.player_camera.clear_visual_impulses()
	world.player_camera._physics_process(0.0)
	world.player_camera.force_update_scroll()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var viewport := fixture.viewport as SubViewport
	var player_screen_position := viewport.get_canvas_transform() * world.player_actor.global_position
	assert_bool(Rect2(64, 64, 1152, 592).has_point(player_screen_position)).is_true()
	var directory := "user://counter-strafe-gameplay-v1"
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))).is_equal(OK)
	var captured := viewport.get_texture().get_image()
	assert_bool(captured != null and not captured.is_empty()).is_true()
	if captured != null and not captured.is_empty():
		assert_int(captured.save_png(directory.path_join(label + ".png"))).is_equal(OK)
