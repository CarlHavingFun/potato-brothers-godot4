class_name GogoCombatStatRuntime
extends RefCounted


const CRITICAL_DAMAGE_MULTIPLIER := 2.0
const ECONOMY_PERCENT_SCALE := 0.01
const ECONOMY_REMAINDER_EPSILON := 0.000001


static func health_regen_interval_seconds(health_regen: float) -> float:
	# Match Brotato's authored cadence: 1 regeneration heals one point every five
	# seconds, with additional points shortening the interval non-linearly.
	if not is_finite(health_regen):
		return INF
	var discrete_regen := floorf(health_regen)
	if discrete_regen <= 0.0:
		return INF
	return 5.0 / (1.0 + absf(discrete_regen - 1.0) / 2.25)


static func is_critical_roll(critical_chance: float, roll: float) -> bool:
	if not is_finite(critical_chance) or not is_finite(roll):
		return false
	return clampf(roll, 0.0, 1.0) < clampf(critical_chance, 0.0, 1.0)


static func damage_after_combat_stats(
	base_damage: float,
	is_critical: bool,
	is_explosion: bool,
	explosion_damage_multiplier: float = 1.0
) -> float:
	var result := maxf(base_damage, 0.0)
	if is_critical:
		result *= CRITICAL_DAMAGE_MULTIPLIER
	if is_explosion:
		result *= maxf(explosion_damage_multiplier, 0.0)
	return result


static func explosion_multiplier_from_stat(stat_delta: float) -> float:
	if not is_finite(stat_delta):
		return 1.0
	return maxf(1.0 + stat_delta, 0.0)


static func economy_reward_grant(
	base_amount: int,
	economy_percent: float,
	previous_remainder: float = 0.0
) -> Dictionary:
	var safe_base := maxi(base_amount, 0)
	var safe_remainder := clampf(previous_remainder, 0.0, 1.0 - ECONOMY_REMAINDER_EPSILON)
	if safe_base <= 0:
		return {&"amount": 0, &"remainder": safe_remainder}
	var safe_economy := economy_percent if is_finite(economy_percent) else 0.0
	var multiplier := maxf(1.0 + safe_economy * ECONOMY_PERCENT_SCALE, 0.0)
	var exact_amount := float(safe_base) * multiplier + safe_remainder
	var granted := maxi(int(floor(exact_amount + ECONOMY_REMAINDER_EPSILON)), 0)
	var next_remainder := clampf(
		exact_amount - float(granted),
		0.0,
		1.0 - ECONOMY_REMAINDER_EPSILON
	)
	return {&"amount": granted, &"remainder": next_remainder}
