extends GdUnitTestSuite


const COMBAT_RESOLVER_PATH := "res://core/services/combat_resolver.gd"


func test_armor_reduces_damage_without_mutating_inputs() -> void:
	assert_bool(ResourceLoader.exists(COMBAT_RESOLVER_PATH)).is_true()
	if not ResourceLoader.exists(COMBAT_RESOLVER_PATH):
		return
	var resolver: RefCounted = load(COMBAT_RESOLVER_PATH).new()

	assert_float(resolver.call("damage_after_armor", 30.0, 15.0)).is_equal_approx(15.0, 0.001)
	assert_float(resolver.call("damage_after_armor", 30.0, 0.0)).is_equal(30.0)
	assert_float(resolver.call("damage_after_armor", 30.0, -15.0)).is_equal_approx(60.0, 0.001)


func test_each_weapon_scaling_stat_changes_only_its_matching_damage_channel() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.DAMAGE: 3.0,
		StatId.MELEE_DAMAGE: 5.0,
		StatId.RANGED_DAMAGE: 7.0,
		StatId.ELEMENTAL_DAMAGE: 11.0,
		StatId.ENGINEERING: 13.0,
	})

	assert_float(resolver.weapon_damage(10.0, stats, StatId.MELEE_DAMAGE)).is_equal(18.0)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.RANGED_DAMAGE)).is_equal(20.0)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.ELEMENTAL_DAMAGE)).is_equal(24.0)
	assert_float(resolver.weapon_damage(10.0, stats, StatId.ENGINEERING)).is_equal(26.0)


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
	assert_float(resolver.attack_range(150.0, stats)).is_equal(190.0)
	assert_float(resolver.critical_chance(0.05, stats)).is_equal_approx(0.20, 0.001)
	assert_float(resolver.life_steal_chance(0.10, stats)).is_equal_approx(0.35, 0.001)
	assert_float(resolver.dodge_chance(stats)).is_equal_approx(0.60, 0.001)


func test_health_movement_recovery_luck_and_harvesting_have_runtime_values() -> void:
	var resolver := CombatResolver.new()
	var stats := PlayerStats.new({
		StatId.MAX_HEALTH: 25.0,
		StatId.RECOVERY: 3.0,
		StatId.MOVE_SPEED: 320.0,
		StatId.LUCK: 12.0,
		StatId.HARVESTING: 8.0,
	})

	assert_float(resolver.max_health(stats)).is_equal(25.0)
	assert_float(resolver.recovery_amount(stats)).is_equal(3.0)
	assert_float(resolver.movement_speed(stats)).is_equal(320.0)
	assert_float(resolver.luck(stats)).is_equal(12.0)
	assert_int(resolver.harvesting_materials(stats)).is_equal(8)
