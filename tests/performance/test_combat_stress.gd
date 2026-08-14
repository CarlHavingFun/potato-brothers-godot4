extends GdUnitTestSuite


func test_stress_scene_uses_the_phase_one_acceptance_load() -> void:
	var script: Script = load("res://tests/performance/combat_stress.gd")
	assert_int(script.get_script_constant_map().get("ENEMY_COUNT", 0)).is_equal(250)
	assert_int(script.get_script_constant_map().get("PROJECTILE_COUNT", 0)).is_equal(200)
	assert_float(script.get_script_constant_map().get("MINIMUM_AVERAGE_FPS", 0.0)).is_equal(55.0)
	assert_bool(ResourceLoader.exists("res://tests/performance/combat_stress.tscn")).is_true()
