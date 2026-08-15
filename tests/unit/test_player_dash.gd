extends GdUnitTestSuite


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
