extends GdUnitTestSuite


func after_test() -> void:
	Global.end_run()


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


func test_enemy_hazard_uses_player_armor_and_damaged_effect_pipeline() -> void:
	Global.begin_run(4041, null, 0)
	Global.current_run.player_stats.set_stat(StatId.ARMOR, 15.0)
	Global.current_run.player_stats.set_stat(StatId.DODGE, 0.0)
	var damaged_effect := EffectDef.new()
	damaged_effect.effect_id = &"effect/test/hazard_damaged_event"
	damaged_effect.trigger_events = [GameplayEvent.Type.DAMAGED]
	damaged_effect.operations = [EffectOperationDef.extra_damage(2.0)]
	assert_bool(Global.gameplay_effects.register_effect(damaged_effect)).is_true()

	var player: Player = auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	var enemy_definition: EnemyDef = Content.catalog.get_enemy(&"enemy/hazard_weaver")
	assert_object(enemy_definition).is_not_null()
	if enemy_definition == null:
		return
	var enemy: Enemy = auto_free(enemy_definition.scene.instantiate() as Enemy) as Enemy
	enemy.definition = enemy_definition
	add_child(enemy)
	enemy.global_position = Vector2.ZERO
	player.global_position = Vector2.ZERO
	enemy.role_profile.hazard_damage = 10.0
	enemy.role_profile.effect_radius = 100.0
	var health_before := player.health_component.current_health

	enemy._execute_role_action()

	# 15 armor halves 10 raw damage; the DAMAGED effect then contributes 2.
	assert_float(player.health_component.current_health).is_equal_approx(
		health_before - 7.0,
		0.001
	)


func test_charger_slam_uses_the_typed_player_damage_pipeline() -> void:
	Global.begin_run(4042, null, 0)
	Global.current_run.player_stats.set_stat(StatId.ARMOR, 15.0)
	Global.current_run.player_stats.set_stat(StatId.DODGE, 0.0)
	var player: Player = auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	var charger: Enemy = auto_free(load(
		"res://scenes/unit/enemy/enemy_charger.tscn"
	).instantiate() as Enemy) as Enemy
	add_child(charger)
	charger.global_position = Vector2.ZERO
	player.global_position = Vector2.ZERO
	var behavior := charger.get_node("ChargeBehavior") as ChargeBehavior
	behavior.slam_target = Vector2.ZERO
	var health_before := player.health_component.current_health
	var raw_damage := charger.stats.damage * 1.2

	behavior._execute_slam()

	assert_float(player.health_component.current_health).is_equal_approx(
		health_before - Global.combat_resolver.damage_after_armor(raw_damage, 15.0),
		0.001
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
