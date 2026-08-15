class_name EnemyRoleProfile
extends RefCounted

var heal_amount := 0.0
var ally_speed_bonus := 0.0
var can_spawn_reinforcements := false
var flank_angle := 0.0
var hazard_damage := 0.0
var material_steal := 0
var slow_multiplier := 1.0
var pulse_interval := 2.5
var effect_radius := 180.0
var damage_taken_multiplier := 1.0
var ambush_distance := 0.0


func to_dict() -> Dictionary:
	return {
		"heal_amount": heal_amount,
		"ally_speed_bonus": ally_speed_bonus,
		"can_spawn_reinforcements": can_spawn_reinforcements,
		"flank_angle": flank_angle,
		"hazard_damage": hazard_damage,
		"material_steal": material_steal,
		"slow_multiplier": slow_multiplier,
		"pulse_interval": pulse_interval,
		"effect_radius": effect_radius,
		"damage_taken_multiplier": damage_taken_multiplier,
		"ambush_distance": ambush_distance,
	}
