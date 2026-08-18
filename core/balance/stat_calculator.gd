class_name StatCalculator
extends RefCounted


var rules: StatRulesDef


func _init(stat_rules: StatRulesDef = null) -> void:
	rules = stat_rules if stat_rules != null else StatRulesDef.baseline()


func final_damage(
	base_damage: float,
	stats: PlayerStats,
	scaling_coefficients: Dictionary = {},
	apply_global_damage: bool = true
) -> float:
	var scaled_damage := base_damage
	if stats != null:
		for raw_stat_id: Variant in scaling_coefficients:
			var stat_id := _resolve_stat_id(raw_stat_id)
			if StatId.is_valid(stat_id) and stat_id != StatId.DAMAGE:
				scaled_damage += stats.get_stat(stat_id) * float(scaling_coefficients[raw_stat_id])
		if apply_global_damage:
			scaled_damage *= maxf(0.0, 1.0 + stats.get_stat(StatId.DAMAGE) / 100.0)
	return maxf(rules.minimum_final_damage, scaled_damage)


func damage_after_armor(raw_damage: float, armor: float) -> float:
	var damage := maxf(0.0, raw_damage)
	if armor >= 0.0:
		return damage * rules.armor_half_damage_point / (
			rules.armor_half_damage_point + armor
		)
	return damage * (
		rules.armor_half_damage_point - 2.0 * armor
	) / (
		rules.armor_half_damage_point - armor
	)


func attack_cooldown(base_cooldown: float, attack_speed_percent: float) -> float:
	var cooldown := maxf(0.001, base_cooldown)
	if attack_speed_percent >= 0.0:
		cooldown /= 1.0 + attack_speed_percent / 100.0
	else:
		# Negative attack speed lengthens cooldown linearly instead of approaching
		# the singularity produced by the positive-speed formula.
		cooldown *= 1.0 + absf(attack_speed_percent) / 100.0
	return maxf(1.0 / rules.maximum_attacks_per_second, cooldown)


func attack_range(base_range: float, range_stat: float) -> float:
	return maxf(0.0, base_range + range_stat)


func critical_chance(base_chance: float, critical_stat: float) -> float:
	return clampf(base_chance + critical_stat / 100.0, 0.0, 1.0)


func life_steal_chance(base_chance: float, life_steal_stat: float) -> float:
	return clampf(base_chance + life_steal_stat / 100.0, 0.0, 1.0)


func dodge_chance(dodge_stat: float) -> float:
	return clampf(dodge_stat / 100.0, 0.0, rules.maximum_dodge_chance)


func maximum_health(max_health_stat: float) -> float:
	return maxf(1.0, max_health_stat)


func regeneration_per_second(recovery_stat: float) -> float:
	if recovery_stat <= 0.0:
		return 0.0
	return (
		rules.regeneration_first_point_per_second
		+ maxf(0.0, recovery_stat - 1.0)
		* rules.regeneration_additional_point_per_second
	)


func regeneration_for_interval(recovery_stat: float, seconds: float = -1.0) -> float:
	var interval := rules.regeneration_tick_seconds if seconds < 0.0 else maxf(0.0, seconds)
	return regeneration_per_second(recovery_stat) * interval


func movement_speed(move_speed_percent: float) -> float:
	var multiplier := maxf(
		rules.minimum_move_speed_multiplier,
		1.0 + move_speed_percent / 100.0
	)
	return rules.base_move_speed * multiplier


func luck_multiplier(luck_stat: float) -> float:
	return maxf(0.0, 1.0 + luck_stat / 100.0)


func harvesting_result(
	harvesting_stat: float,
	wave: int,
	_is_endless: bool = false,
	endless_growth_cutoff_wave: int = 20
) -> Dictionary:
	var amount := roundi(harvesting_stat)
	var next_value := harvesting_stat
	var can_grow := harvesting_stat > 0.0 and wave < endless_growth_cutoff_wave
	if can_grow:
		next_value = ceilf(harvesting_stat * (1.0 + rules.harvesting_growth_rate))
	return {
		"materials_delta": amount,
		"experience_delta": amount,
		"next_harvesting": next_value,
		"grew": can_grow,
	}


func _resolve_stat_id(raw_stat_id: Variant) -> int:
	if raw_stat_id is int:
		return int(raw_stat_id)
	if raw_stat_id is String or raw_stat_id is StringName:
		return StatId.from_key(str(raw_stat_id))
	return -1
