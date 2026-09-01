extends GdUnitTestSuite


const STEP := 1.0 / 60.0


func before_test() -> void:
	_release_all_input()


func after_test() -> void:
	_release_all_input()


func test_keyboard_and_gamepad_bindings_are_present_with_the_same_deadzone() -> void:
	assert_float(InputMap.action_get_deadzone(&"move_left")).is_equal_approx(0.2, 0.0001)
	assert_float(InputMap.action_get_deadzone(&"move_right")).is_equal_approx(0.2, 0.0001)
	assert_bool(_has_key_binding(&"move_left", KEY_A)).is_true()
	assert_bool(_has_key_binding(&"move_right", KEY_D)).is_true()
	assert_bool(_has_axis_binding(&"move_left", -1.0)).is_true()
	assert_bool(_has_axis_binding(&"move_right", 1.0)).is_true()


func test_raw_keyboard_and_gamepad_use_the_same_five_tick_counter_strafe_window() -> void:
	for source in [&"keyboard", &"gamepad"]:
		_release_all_input()
		var player := _player_with_speed(300.0)
		if source == &"keyboard":
			_parse_key(KEY_D, true)
		else:
			_parse_left_stick_x(1.0)
		Input.flush_buffered_events()
		for _tick in 30:
			player._physics_process(STEP)
		assert_float(player.velocity.x).is_equal_approx(300.0, 0.001)

		if source == &"keyboard":
			_parse_key(KEY_D, false)
			_parse_key(KEY_A, true)
		else:
			_parse_left_stick_x(-1.0)
		Input.flush_buffered_events()
		for _tick in 4:
			player._physics_process(STEP)
		assert_float(player.velocity.x).is_greater(0.0)
		player._physics_process(STEP)
		assert_float(player.velocity.x).is_equal_approx(0.0, 0.001)
		player._physics_process(STEP)
		assert_float(player.velocity.x).is_less(0.0)
		player.free()


func test_left_stick_below_deadzone_releases_instead_of_triggering_full_reverse_brake() -> void:
	var player := _player_with_speed(300.0)
	player.velocity = Vector2(300.0, 0.0)
	_parse_left_stick_x(-0.19)
	Input.flush_buffered_events()
	player._physics_process(STEP)
	var expected_release := GogoMovementCombatRuntime.move_toward_velocity(
		Vector2(300.0, 0.0),
		Vector2.ZERO,
		300.0,
		STEP,
		0.0
	)
	assert_bool(player.velocity.is_equal_approx(expected_release)).is_true()


func _player_with_speed(speed: float) -> GogoPlayerActor:
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	var state := SessionPlayerState.new()
	state.final_stats = {&"movement_speed": speed}
	player.player_state = state
	add_child(player)
	player.set_physics_process(false)
	return player


func _has_key_binding(action: StringName, physical_keycode: Key) -> bool:
	return InputMap.action_get_events(action).any(func(event: InputEvent) -> bool:
		return event is InputEventKey and (event as InputEventKey).physical_keycode == physical_keycode
	)


func _has_axis_binding(action: StringName, value: float) -> bool:
	return InputMap.action_get_events(action).any(func(event: InputEvent) -> bool:
		return (
			event is InputEventJoypadMotion
			and (event as InputEventJoypadMotion).axis == JOY_AXIS_LEFT_X
			and is_equal_approx((event as InputEventJoypadMotion).axis_value, value)
		)
	)


func _release_all_input() -> void:
	for action in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	_parse_key(KEY_A, false)
	_parse_key(KEY_D, false)
	_parse_left_stick_x(0.0)
	Input.flush_buffered_events()


func _parse_key(physical_keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _parse_left_stick_x(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
