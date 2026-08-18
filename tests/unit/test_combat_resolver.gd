extends GdUnitTestSuite


const COMBAT_RESOLVER_PATH := "res://core/services/combat_resolver.gd"


func test_armor_uses_the_reference_positive_and_negative_curves() -> void:
	assert_bool(ResourceLoader.exists(COMBAT_RESOLVER_PATH)).is_true()
	if not ResourceLoader.exists(COMBAT_RESOLVER_PATH):
		return
	var resolver: RefCounted = load(COMBAT_RESOLVER_PATH).new()

	assert_float(resolver.call("damage_after_armor", 30.0, 15.0)).is_equal_approx(15.0, 0.001)
	assert_float(resolver.call("damage_after_armor", 30.0, 0.0)).is_equal(30.0)
	assert_float(resolver.call("damage_after_armor", 30.0, -15.0)).is_equal_approx(45.0, 0.001)
	assert_float(resolver.call("damage_after_armor", 30.0, -100.0)).is_equal_approx(
		30.0 * 215.0 / 115.0,
		0.001
	)


func test_hit_resolver_fallback_uses_the_same_armor_curve() -> void:
	var resolver := HitResolver.new()

	assert_float(resolver.call("_damage_after_armor", 30.0, 15.0)).is_equal_approx(15.0, 0.001)
	assert_float(resolver.call("_damage_after_armor", 30.0, -15.0)).is_equal_approx(45.0, 0.001)
	assert_float(resolver.call("_damage_after_armor", 30.0, -100.0)).is_equal_approx(
		30.0 * 215.0 / 115.0,
		0.001
	)


func test_each_weapon_scaling_stat_changes_only_its_matching_damage_channel() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.DAMAGE: 20.0,
		StatId.MELEE_DAMAGE: 5.0,
		StatId.RANGED_DAMAGE: 7.0,
		StatId.ELEMENTAL_DAMAGE: 11.0,
		StatId.ENGINEERING: 13.0,
	})

	assert_float(resolver.weapon_damage(10.0, stats, StatId.MELEE_DAMAGE)).is_equal_approx(18.0, 0.001)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.RANGED_DAMAGE)).is_equal_approx(20.4, 0.001)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.ELEMENTAL_DAMAGE)).is_equal_approx(25.2, 0.001)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.ENGINEERING)).is_equal(23.0)


func test_damage_scaling_accepts_any_non_damage_primary_stat() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.DAMAGE: 20.0,
		StatId.MAX_HEALTH: 20.0,
		StatId.RANGE: 40.0,
		StatId.LUCK: 30.0,
		StatId.ARMOR: 5.0,
	})

	var damage := resolver.weapon_damage_with_coefficients(10.0, stats, {
		StatId.MAX_HEALTH: 0.10,
		StatId.RANGE: 0.05,
		StatId.LUCK: 0.10,
		StatId.ARMOR: 0.20,
	})

	assert_float(damage).is_equal_approx(21.6, 0.001)


func test_attack_speed_range_crit_life_steal_and_defense_are_bounded() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.ATTACK_SPEED: 100.0,
		StatId.CRITICAL_CHANCE: 15.0,
		StatId.RANGE: 40.0,
		StatId.LIFE_STEAL: 25.0,
		StatId.DODGE: 90.0,
	})

	assert_float(resolver.attack_cooldown(1.0, stats)).is_equal_approx(0.5, 0.001)
	stats.set_stat(StatId.ATTACK_SPEED, -100.0)
	assert_float(resolver.attack_cooldown(1.0, stats)).is_equal_approx(2.0, 0.001)
	stats.set_stat(StatId.ATTACK_SPEED, 5000.0)
	assert_float(resolver.attack_cooldown(1.0, stats)).is_equal_approx(1.0 / 12.0, 0.001)
	assert_float(resolver.attack_range(150.0, stats)).is_equal(190.0)
	assert_float(resolver.critical_chance(0.05, stats)).is_equal_approx(0.20, 0.001)
	assert_float(resolver.life_steal_chance(0.10, stats)).is_equal_approx(0.35, 0.001)
	assert_float(resolver.dodge_chance(stats)).is_equal_approx(0.60, 0.001)


func test_health_movement_recovery_luck_and_harvesting_have_runtime_values() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.MAX_HEALTH: 25.0,
		StatId.RECOVERY: 3.0,
		StatId.MOVE_SPEED: 20.0,
		StatId.LUCK: 12.0,
		StatId.HARVESTING: 8.0,
	})

	assert_float(resolver.max_health(stats)).is_equal(25.0)
	assert_float(resolver.recovery_per_second(stats)).is_equal_approx(0.378, 0.001)
	assert_float(resolver.recovery_amount(stats)).is_equal_approx(1.134, 0.001)
	assert_float(resolver.movement_speed(stats)).is_equal(540.0)
	assert_float(resolver.luck(stats)).is_equal(12.0)
	assert_int(resolver.harvesting_materials(stats)).is_equal(8)


func test_life_steal_is_globally_rate_limited_to_ten_procs_per_second() -> void:
	var resolver := CombatResolver.new(81)
	var stats := PlayerStats.new({StatId.LIFE_STEAL: 100.0})

	assert_bool(resolver.try_life_steal(0.0, stats, 1.0)).is_true()
	assert_bool(resolver.try_life_steal(0.0, stats, 1.099)).is_false()
	assert_bool(resolver.try_life_steal(0.0, stats, 1.1)).is_true()


func test_harvesting_grants_and_grows_positive_values_but_not_negative_or_endless() -> void:
	var calculator := StatCalculator.new()
	var positive := calculator.harvesting_result(8.0, 1)
	var negative := calculator.harvesting_result(-8.0, 1)
	var final_standard := calculator.harvesting_result(8.0, 20)
	var endless := calculator.harvesting_result(8.0, 21, true)

	assert_int(positive.materials_delta).is_equal(8)
	assert_int(positive.experience_delta).is_equal(8)
	assert_float(positive.next_harvesting).is_equal(9.0)
	assert_bool(positive.grew).is_true()
	assert_int(negative.materials_delta).is_equal(-8)
	assert_int(negative.experience_delta).is_equal(-8)
	assert_float(negative.next_harvesting).is_equal(-8.0)
	assert_bool(negative.grew).is_false()
	assert_float(final_standard.next_harvesting).is_equal(8.0)
	assert_bool(final_standard.grew).is_false()
	assert_float(endless.next_harvesting).is_equal(8.0)
	assert_bool(endless.grew).is_false()
