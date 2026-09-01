extends GdUnitTestSuite


const STEP := 1.0 / 60.0


func test_300_speed_preserves_the_approved_release_and_reverse_windows() -> void:
	assert_int(_frames_to_stop(300.0, Vector2.ZERO, 0.0)).is_equal(16)
	assert_int(_frames_to_stop(300.0, Vector2.LEFT, 0.0)).is_equal(8)


func test_faster_builds_do_not_silently_make_counter_strafing_slower() -> void:
	assert_int(_frames_to_stop(600.0, Vector2.ZERO, 0.0)).is_equal(16)
	assert_int(_frames_to_stop(600.0, Vector2.LEFT, 0.0)).is_equal(8)


func test_counter_strafe_upgrade_still_improves_both_braking_windows() -> void:
	assert_int(_frames_to_stop(300.0, Vector2.ZERO, 25.0)).is_equal(13)
	assert_int(_frames_to_stop(300.0, Vector2.LEFT, 25.0)).is_equal(7)


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
