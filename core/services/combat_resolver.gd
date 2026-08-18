class_name CombatResolver
extends RefCounted


const STREAM_OFFSET := 0x434F4D42

var rng := RandomNumberGenerator.new()
var stat_rules: StatRulesDef
var stat_calculator: StatCalculator
var _last_life_steal_proc_seconds := -INF


func _init(run_seed: int = 0, rules: StatRulesDef = null) -> void:
	rng.seed = run_seed ^ STREAM_OFFSET
	stat_rules = rules if rules != null else StatRulesDef.baseline()
	stat_calculator = StatCalculator.new(stat_rules)


func damage_after_armor(raw_damage: float, armor: float) -> float:
	return stat_calculator.damage_after_armor(raw_damage, armor)


func weapon_damage(
	base_damage: float,
	stats: PlayerStats,
	scaling_stat_id: int,
	scaling_coefficient: float = 1.0
) -> float:
	var coefficients := {}
	if scaling_stat_id in [
		StatId.MELEE_DAMAGE,
		StatId.RANGED_DAMAGE,
		StatId.ELEMENTAL_DAMAGE,
		StatId.ENGINEERING,
	]:
		coefficients[scaling_stat_id] = scaling_coefficient
	return stat_calculator.final_damage(
		base_damage,
		stats,
		coefficients,
		scaling_stat_id != StatId.ENGINEERING
	)


func weapon_damage_with_coefficients(
	base_damage: float,
	stats: PlayerStats,
	scaling_coefficients: Dictionary,
	is_engineering_structure: bool = false
) -> float:
	return stat_calculator.final_damage(
		base_damage,
		stats,
		scaling_coefficients,
		not is_engineering_structure
	)


func attack_cooldown(base_cooldown: float, stats: PlayerStats) -> float:
	var attack_speed := stats.get_stat(StatId.ATTACK_SPEED) if stats != null else 0.0
	return stat_calculator.attack_cooldown(base_cooldown, attack_speed)


func attack_range(base_range: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.RANGE) if stats != null else 0.0
	return stat_calculator.attack_range(base_range, bonus)


func critical_chance(base_chance: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.CRITICAL_CHANCE) if stats != null else 0.0
	return stat_calculator.critical_chance(base_chance, bonus)


func life_steal_chance(base_chance: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.LIFE_STEAL) if stats != null else 0.0
	return stat_calculator.life_steal_chance(base_chance, bonus)


func try_life_steal(
	base_chance: float,
	stats: PlayerStats,
	now_seconds: float = -1.0
) -> bool:
	var timestamp := now_seconds
	if timestamp < 0.0:
		timestamp = Time.get_ticks_usec() / 1_000_000.0
	if timestamp - _last_life_steal_proc_seconds < stat_rules.life_steal_minimum_interval_seconds:
		return false
	if not roll_chance(life_steal_chance(base_chance, stats)):
		return false
	_last_life_steal_proc_seconds = timestamp
	return true


func reset_life_steal_rate_limit() -> void:
	_last_life_steal_proc_seconds = -INF


func dodge_chance(stats: PlayerStats, cap_override_percent: float = -1.0) -> float:
	var dodge_stat := stats.get_stat(StatId.DODGE) if stats != null else 0.0
	if cap_override_percent < 0.0:
		return stat_calculator.dodge_chance(dodge_stat)
	return clampf(dodge_stat / 100.0, 0.0, clampf(cap_override_percent / 100.0, 0.0, 1.0))


func max_health(stats: PlayerStats) -> float:
	return stat_calculator.maximum_health(
		stats.get_stat(StatId.MAX_HEALTH) if stats != null else 0.0
	)


func recovery_per_second(stats: PlayerStats) -> float:
	return stat_calculator.regeneration_per_second(
		stats.get_stat(StatId.RECOVERY) if stats != null else 0.0
	)


func recovery_amount(stats: PlayerStats, seconds: float = -1.0) -> float:
	return stat_calculator.regeneration_for_interval(
		stats.get_stat(StatId.RECOVERY) if stats != null else 0.0,
		seconds
	)


func movement_speed(stats: PlayerStats) -> float:
	return stat_calculator.movement_speed(
		stats.get_stat(StatId.MOVE_SPEED) if stats != null else 0.0
	)


func luck(stats: PlayerStats) -> float:
	return stats.get_stat(StatId.LUCK) if stats != null else 0.0


func luck_multiplier(stats: PlayerStats) -> float:
	return stat_calculator.luck_multiplier(luck(stats))


func harvesting_materials(stats: PlayerStats) -> int:
	return roundi(stats.get_stat(StatId.HARVESTING)) if stats != null else 0


func harvesting_result(stats: PlayerStats, wave: int, is_endless: bool = false) -> Dictionary:
	return stat_calculator.harvesting_result(
		stats.get_stat(StatId.HARVESTING) if stats != null else 0.0,
		wave,
		is_endless
	)


func roll_chance(chance: float) -> bool:
	return rng.randf() < clampf(chance, 0.0, 1.0)
