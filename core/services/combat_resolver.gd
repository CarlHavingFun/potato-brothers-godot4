class_name CombatResolver
extends RefCounted


const ARMOR_HALF_DAMAGE_POINT := 15.0
const MAX_DODGE_CHANCE := 0.60
const MIN_ATTACK_SPEED_FACTOR := 0.20
const STREAM_OFFSET := 0x434F4D42

var rng := RandomNumberGenerator.new()


func _init(run_seed: int = 0) -> void:
	rng.seed = run_seed ^ STREAM_OFFSET


func damage_after_armor(raw_damage: float, armor: float) -> float:
	var damage := maxf(0.0, raw_damage)
	if armor >= 0.0:
		return damage * ARMOR_HALF_DAMAGE_POINT / (ARMOR_HALF_DAMAGE_POINT + armor)
	return damage * (1.0 + absf(armor) / ARMOR_HALF_DAMAGE_POINT)


func weapon_damage(base_damage: float, stats: PlayerStats, scaling_stat_id: int) -> float:
	if stats == null:
		return maxf(0.0, base_damage)
	var scaling_bonus := 0.0
	if scaling_stat_id in [
		StatId.MELEE_DAMAGE,
		StatId.RANGED_DAMAGE,
		StatId.ELEMENTAL_DAMAGE,
		StatId.ENGINEERING,
	]:
		scaling_bonus = stats.get_stat(scaling_stat_id)
	return maxf(0.0, base_damage + stats.get_stat(StatId.DAMAGE) + scaling_bonus)


func attack_cooldown(base_cooldown: float, stats: PlayerStats) -> float:
	var attack_speed := stats.get_stat(StatId.ATTACK_SPEED) if stats != null else 0.0
	var speed_factor := maxf(MIN_ATTACK_SPEED_FACTOR, 1.0 + attack_speed / 100.0)
	return maxf(0.01, base_cooldown / speed_factor)


func attack_range(base_range: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.RANGE) if stats != null else 0.0
	return maxf(20.0, base_range + bonus)


func critical_chance(base_chance: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.CRITICAL_CHANCE) / 100.0 if stats != null else 0.0
	return clampf(base_chance + bonus, 0.0, 1.0)


func life_steal_chance(base_chance: float, stats: PlayerStats) -> float:
	var bonus := stats.get_stat(StatId.LIFE_STEAL) / 100.0 if stats != null else 0.0
	return clampf(base_chance + bonus, 0.0, 1.0)


func dodge_chance(stats: PlayerStats) -> float:
	if stats == null:
		return 0.0
	return clampf(stats.get_stat(StatId.DODGE) / 100.0, 0.0, MAX_DODGE_CHANCE)


func max_health(stats: PlayerStats) -> float:
	return maxf(1.0, stats.get_stat(StatId.MAX_HEALTH)) if stats != null else 1.0


func recovery_amount(stats: PlayerStats) -> float:
	return maxf(0.0, stats.get_stat(StatId.RECOVERY)) if stats != null else 0.0


func movement_speed(stats: PlayerStats) -> float:
	return maxf(0.0, stats.get_stat(StatId.MOVE_SPEED)) if stats != null else 0.0


func luck(stats: PlayerStats) -> float:
	return stats.get_stat(StatId.LUCK) if stats != null else 0.0


func harvesting_materials(stats: PlayerStats) -> int:
	return maxi(0, roundi(stats.get_stat(StatId.HARVESTING))) if stats != null else 0


func roll_chance(chance: float) -> bool:
	return rng.randf() < clampf(chance, 0.0, 1.0)
