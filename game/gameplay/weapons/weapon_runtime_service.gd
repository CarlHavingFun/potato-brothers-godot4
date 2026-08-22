class_name WeaponRuntimeService
extends RefCounted


func build_instance(definition: GogoWeaponDefinition, player_state: SessionPlayerState) -> GogoWeaponRuntimeStats:
	if definition == null or player_state == null:
		return null
	var stats := GogoWeaponRuntimeStats.new()
	var damage_multiplier := float(player_state.final_stats.get(&"damage_multiplier", 1.0))
	var attack_speed := maxf(float(player_state.final_stats.get(&"attack_speed", 1.0)), 0.1)
	stats.definition_id = definition.content_id
	stats.mode = definition.mode
	stats.damage = maxf(definition.damage * damage_multiplier, 0.0)
	stats.cooldown_seconds = maxf(definition.cooldown_seconds / attack_speed, 0.05)
	stats.attack_range = maxf(definition.attack_range, 12.0)
	stats.projectile_speed = maxf(definition.projectile_speed, 1.0)
	stats.projectile_count = maxi(definition.projectile_count, 1)
	stats.spread_degrees = maxf(definition.spread_degrees, 0.0)
	stats.knockback = definition.knockback
	return stats
