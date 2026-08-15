class_name EnemyRoleRules
extends RefCounted


func profile_for(raw_tags: Array[StringName]) -> EnemyRoleProfile:
	var profile := EnemyRoleProfile.new()
	var unique_tags: Array[StringName] = []
	for tag: StringName in raw_tags:
		if tag not in unique_tags:
			unique_tags.append(tag)
	unique_tags.sort()
	for tag: StringName in unique_tags:
		match tag:
			&"healer":
				profile.heal_amount = minf(20.0, profile.heal_amount + 8.0)
			&"buffer":
				profile.ally_speed_bonus = minf(0.35, profile.ally_speed_bonus + 0.18)
			&"spawner":
				profile.can_spawn_reinforcements = true
				profile.pulse_interval = 6.0
			&"flanker":
				profile.flank_angle = deg_to_rad(32.0)
			&"hazard":
				profile.hazard_damage = 5.0
				profile.effect_radius = 150.0
			&"resource_disrupt":
				profile.material_steal = 1
				profile.effect_radius = 125.0
			&"debuffer":
				profile.slow_multiplier = 0.72
				profile.effect_radius = 165.0
	return profile
