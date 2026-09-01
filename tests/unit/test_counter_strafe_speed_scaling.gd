extends GdUnitTestSuite


const STEP := 1.0 / 60.0


func test_300_speed_has_perceptibly_crisp_default_release_and_reverse_windows() -> void:
	# User playtesting rejected the previous 16/8-frame tuning as still feeling
	# like the older build. Keep release controllable, but make an intentional
	# opposite input reach zero inside the sub-100 ms window at 60 Hz.
	assert_int(_frames_to_stop(300.0, Vector2.ZERO, 0.0)).is_equal(8)
	assert_int(_frames_to_stop(300.0, Vector2.LEFT, 0.0)).is_equal(5)


func test_faster_builds_do_not_silently_make_counter_strafing_slower() -> void:
	assert_int(_frames_to_stop(600.0, Vector2.ZERO, 0.0)).is_equal(8)
	assert_int(_frames_to_stop(600.0, Vector2.LEFT, 0.0)).is_equal(5)


func test_counter_strafe_upgrade_still_improves_both_braking_windows() -> void:
	assert_int(_frames_to_stop(300.0, Vector2.ZERO, 25.0)).is_equal(7)
	assert_int(_frames_to_stop(300.0, Vector2.LEFT, 25.0)).is_equal(4)


func test_default_counter_strafe_is_crisp_but_not_an_instant_direction_flip() -> void:
	var velocity := Vector2(300.0, 0.0)
	velocity = GogoMovementCombatRuntime.move_toward_velocity(
		velocity,
		Vector2.LEFT,
		300.0,
		STEP,
		0.0
	)
	assert_float(velocity.x).is_greater(0.0)
	for _frame in 4:
		velocity = GogoMovementCombatRuntime.move_toward_velocity(
			velocity,
			Vector2.LEFT,
			300.0,
			STEP,
			0.0
		)
	assert_vector(velocity).is_equal(Vector2.ZERO)
	velocity = GogoMovementCombatRuntime.move_toward_velocity(
		velocity,
		Vector2.LEFT,
		300.0,
		STEP,
		0.0
	)
	assert_float(velocity.x).is_less(0.0)


func _frames_to_stop(speed: float, direction: Vector2, brake_percent: float) -> int:
	var velocity := Vector2(speed, 0.0)
	for frame in 60:
		velocity = GogoMovementCombatRuntime.move_toward_velocity(
			velocity,
			direction,
			speed,
			STEP,
			brake_percent
		)
		if velocity.is_zero_approx():
			return frame + 1
	return 60
