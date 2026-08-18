extends GdUnitTestSuite


const WAVE_RULES := preload("res://core/directors/core_wave_rules.gd")


func test_standard_wave_durations_match_the_reference_baseline() -> void:
	var expected: Array[float] = [
		20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0,
		60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 60.0,
		60.0, 60.0, 60.0, 90.0,
	]
	for index in expected.size():
		assert_float(WAVE_RULES.duration_for_wave(index + 1)).is_equal(expected[index])
	assert_float(WAVE_RULES.duration_for_wave(21, 999.0)).is_equal(60.0)


func test_special_event_windows_scale_from_none_to_three() -> void:
	assert_array(WAVE_RULES.special_event_windows(1)).is_empty()
	assert_array(WAVE_RULES.special_event_windows(2)).is_equal([Vector2i(11, 12)])
	assert_array(WAVE_RULES.special_event_windows(3)).is_equal([Vector2i(11, 12)])
	assert_array(WAVE_RULES.special_event_windows(4)).is_equal([
		Vector2i(11, 12), Vector2i(14, 15), Vector2i(17, 18),
	])
	assert_array(WAVE_RULES.special_event_windows(5)).is_equal([
		Vector2i(11, 12), Vector2i(14, 15), Vector2i(17, 18),
	])
	assert_str(WAVE_RULES.special_event_kind(0, 0.59)).is_equal("elite")
	assert_str(WAVE_RULES.special_event_kind(0, 0.60)).is_equal("horde")
	assert_str(WAVE_RULES.special_event_kind(2, 0.99)).is_equal("elite")


func test_material_drop_and_harvesting_rules_are_bounded() -> void:
	assert_float(WAVE_RULES.material_drop_chance(4)).is_equal(1.0)
	assert_float(WAVE_RULES.material_drop_chance(5)).is_equal_approx(0.925, 0.0001)
	assert_float(WAVE_RULES.material_drop_chance(20)).is_equal_approx(0.70, 0.0001)
	assert_float(WAVE_RULES.material_drop_chance(100)).is_equal(0.50)
	assert_bool(WAVE_RULES.harvesting_grows_after_wave(19)).is_true()
	assert_bool(WAVE_RULES.harvesting_grows_after_wave(20)).is_false()
	assert_float(WAVE_RULES.final_boss_base_health_multiplier(4)).is_equal(1.0)
	assert_float(WAVE_RULES.final_boss_base_health_multiplier(5)).is_equal(0.75)


func test_material_drop_roll_is_deterministic_without_consuming_shared_rng() -> void:
	var first: Array[bool] = []
	var second: Array[bool] = []
	for kill_index in 100:
		first.append(WAVE_RULES.should_drop_material(771, 20, kill_index + 1))
		second.append(WAVE_RULES.should_drop_material(771, 20, kill_index + 1))
	assert_array(first).is_equal(second)
	assert_bool(first.has(true)).is_true()
	assert_bool(first.has(false)).is_true()
