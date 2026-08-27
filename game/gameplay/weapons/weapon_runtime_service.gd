class_name WeaponRuntimeService
extends RefCounted

const VALID_FEEDBACK_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const VALID_IMPACT_KINDS: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]


func build_instance(definition: GogoWeaponDefinition, player_state: SessionPlayerState) -> GogoWeaponRuntimeStats:
	if definition == null or player_state == null:
		return null
	var stats := GogoWeaponRuntimeStats.new()
	var damage_multiplier := float(player_state.final_stats.get(&"damage_multiplier", 1.0))
	var attack_speed := maxf(float(player_state.final_stats.get(&"attack_speed", 1.0)), 0.1)
	var flat_damage_key := &"melee_damage" if definition.mode == GogoWeaponDefinition.Mode.MELEE else &"ranged_damage"
	var flat_damage := float(player_state.final_stats.get(flat_damage_key, 0.0))
	var range_bonus := float(player_state.final_stats.get(&"attack_range_bonus", 0.0))
	stats.definition_id = definition.content_id
	stats.static_asset_id = definition.icon_asset_id
	stats.mode = definition.mode
	stats.damage = maxf(definition.damage * damage_multiplier + flat_damage, 0.0)
	stats.cooldown_seconds = maxf(definition.cooldown_seconds / attack_speed, 0.05)
	stats.attack_range = maxf(definition.attack_range + range_bonus, 12.0)
	stats.projectile_speed = maxf(definition.projectile_speed, 1.0)
	stats.projectile_count = maxi(definition.projectile_count, 1)
	stats.spread_degrees = maxf(definition.spread_degrees, 0.0)
	stats.knockback = definition.knockback
	stats.feedback_profile_id = definition.feedback_profile_id if VALID_FEEDBACK_PROFILES.has(definition.feedback_profile_id) else &"rifle"
	stats.damage_kind = definition.damage_kind if not definition.damage_kind.is_empty() else &"ballistic"
	stats.impact_kind = definition.impact_kind if VALID_IMPACT_KINDS.has(definition.impact_kind) else &"normal"
	return stats
