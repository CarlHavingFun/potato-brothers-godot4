extends GdUnitTestSuite


func test_role_profile_exposes_all_special_enemy_responsibilities() -> void:
	var rules := EnemyRoleRules.new()
	var tags: Array[StringName] = [
		&"healer", &"buffer", &"spawner", &"flanker", &"hazard",
		&"resource_disrupt", &"debuffer",
	]
	var profile := rules.profile_for(tags)

	assert_float(profile.heal_amount).is_greater(0.0)
	assert_float(profile.ally_speed_bonus).is_greater(0.0)
	assert_bool(profile.can_spawn_reinforcements).is_true()
	assert_float(profile.flank_angle).is_not_equal(0.0)
	assert_float(profile.hazard_damage).is_greater(0.0)
	assert_int(profile.material_steal).is_equal(1)
	assert_float(profile.slow_multiplier).is_less(1.0)


func test_role_profile_combines_tags_deterministically_without_unbounded_values() -> void:
	var rules := EnemyRoleRules.new()
	var first := rules.profile_for([&"buffer", &"healer", &"tank", &"buffer"])
	var second := rules.profile_for([&"healer", &"buffer", &"tank"])

	assert_dict(first.to_dict()).is_equal(second.to_dict())
	assert_float(first.ally_speed_bonus).is_less_equal(0.35)
	assert_float(first.heal_amount).is_less_equal(20.0)


func test_enemy_role_actions_follow_windup_attack_recovery_semantics() -> void:
	assert_int(Enemy.next_behavior_state(Enemy.BehaviorState.APPROACH)).is_equal(
		Enemy.BehaviorState.WINDUP
	)
	assert_int(Enemy.next_behavior_state(Enemy.BehaviorState.WINDUP)).is_equal(
		Enemy.BehaviorState.ATTACK
	)
	assert_int(Enemy.next_behavior_state(Enemy.BehaviorState.ATTACK)).is_equal(
		Enemy.BehaviorState.RECOVER
	)
	assert_int(Enemy.next_behavior_state(Enemy.BehaviorState.RECOVER)).is_equal(
		Enemy.BehaviorState.APPROACH
	)


func test_elite_components_gain_a_second_phase_and_distinct_attacks() -> void:
	assert_int(ChargeBehavior.phase_for_health(49.0, 100.0, true, 1)).is_equal(2)
	assert_int(ChargeBehavior.phase_for_health(49.0, 100.0, false, 1)).is_equal(1)
	assert_int(ChargeBehavior.charge_chain_count(1, 1)).is_equal(1)
	assert_int(ChargeBehavior.charge_chain_count(2, 5)).is_equal(3)
	assert_int(ChargeBehavior.attack_pattern_for(0, 2)).is_equal(
		ChargeBehavior.AttackPattern.CHAIN
	)
	assert_int(ChargeBehavior.attack_pattern_for(1, 2)).is_equal(
		ChargeBehavior.AttackPattern.SLAM
	)
	assert_int(ChargeBehavior.attack_pattern_for(2, 2)).is_equal(
		ChargeBehavior.AttackPattern.CHARGE
	)

	assert_int(ShootingBehavior.phase_for_health(39.0, 100.0, true, 1)).is_equal(2)
	assert_int(ShootingBehavior.phase_for_health(39.0, 100.0, false, 1)).is_equal(1)
	assert_int(ShootingBehavior.attack_pattern_for(0, 1)).is_equal(
		ShootingBehavior.AttackPattern.SPREAD
	)
	assert_int(ShootingBehavior.attack_pattern_for(1, 2)).is_equal(
		ShootingBehavior.AttackPattern.RADIAL
	)
