extends GdUnitTestSuite


func test_percent_movement_and_attack_speed_modifiers_change_final_runtime_stats_once() -> void:
	var pipeline := GogoStatPipeline.new()
	var result := pipeline.rebuild(
		{
			&"max_health": 10.0,
			&"movement_speed": 235.0,
			&"damage_multiplier": 1.0,
			&"attack_speed": 1.0,
		},
		{
			&"equipment": [{
				&"movement_speed_multiplier": 0.06,
				&"attack_speed_multiplier": 0.05,
			}],
		}
	)
	assert_float(float(result.get(&"movement_speed", 0.0))).is_equal_approx(249.1, 0.0001)
	assert_float(float(result.get(&"attack_speed", 0.0))).is_equal_approx(1.05, 0.0001)


func test_ranged_flat_damage_and_range_bonus_reach_weapon_runtime() -> void:
	var definition := GogoWeaponDefinition.new()
	definition.content_id = &"test:weapon/rifle"
	definition.display_name = "Test Rifle"
	definition.mode = GogoWeaponDefinition.Mode.RANGED
	definition.damage = 10.0
	definition.cooldown_seconds = 1.0
	definition.attack_range = 100.0
	var player := SessionPlayerState.new()
	player.final_stats = {
		&"damage_multiplier": 1.1,
		&"attack_speed": 1.25,
		&"attack_range_bonus": 30.0,
		&"ranged_damage": 4.0,
	}
	var runtime := WeaponRuntimeService.new().build_instance(definition, player)
	assert_object(runtime).is_not_null()
	if runtime == null:
		return
	assert_float(runtime.damage).is_equal_approx(15.0, 0.0001)
	assert_float(runtime.cooldown_seconds).is_equal_approx(0.8, 0.0001)
	assert_float(runtime.attack_range).is_equal_approx(130.0, 0.0001)
