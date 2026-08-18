extends GdUnitTestSuite


func after_test() -> void:
	Global.end_run()


func test_dash_uses_the_gobro_single_charge_timing_baseline() -> void:
	var player := auto_free(load("res://scenes/unit/players/player_well_rounded.tscn").instantiate()) as Player
	add_child(player)
	await await_idle_frame()

	assert_float(player.dash_duration).is_equal_approx(0.18, 0.001)
	assert_float(player.dash_invulnerability_duration).is_equal_approx(0.12, 0.001)
	assert_float(player.dash_cooldown).is_equal_approx(2.5, 0.001)
	assert_int(player.max_dash_charges).is_equal(1)
	assert_int(player.dash_charges).is_equal(1)


func test_invulnerability_ends_before_dash_and_charge_returns_on_cooldown() -> void:
	var player := auto_free(load("res://scenes/unit/players/player_well_rounded.tscn").instantiate()) as Player
	add_child(player)
	await await_idle_frame()
	player.move_dir = Vector2.RIGHT

	player.start_dash()
	assert_bool(player.is_dashing).is_true()
	assert_int(player.dash_charges).is_zero()
	player._on_dash_invulnerability_timer_timeout()
	assert_bool(player.is_dashing).is_true()
	player._on_dash_timer_timeout()
	assert_bool(player.is_dashing).is_false()
	player._on_dash_cooldown_timer_timeout()
	assert_int(player.dash_charges).is_equal(1)


func test_dash_invulnerability_rejects_collision_and_scripted_hits() -> void:
	Global.begin_run(5041, null, 0)
	Global.current_run.player_stats.set_stat(StatId.ARMOR, 0.0)
	Global.current_run.player_stats.set_stat(StatId.DODGE, 0.0)
	var player := auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate()) as Player
	var source := auto_free(Node2D.new()) as Node2D
	add_child(player)
	add_child(source)
	Global.player = player
	player.move_dir = Vector2.RIGHT
	player.start_dash()
	var health_before := player.health_component.current_health
	var collision_hit := auto_free(HitboxComponent.new()) as HitboxComponent
	collision_hit.setup(3.0, false, 0.0, source, source)

	player._on_hurtbox_component_on_damaged(collision_hit)
	player.receive_typed_damage(
		3.0,
		source,
		[&"arena", &"hazard"] as Array[StringName]
	)

	assert_float(player.health_component.current_health).is_equal(health_before)
	player.dash_invulnerability_timer.stop()
	player.receive_typed_damage(3.0, source)
	assert_float(player.health_component.current_health).is_equal(health_before - 3.0)
