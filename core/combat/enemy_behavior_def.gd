class_name EnemyBehaviorDef
extends Resource


@export var behavior_id: StringName
@export var role_id: StringName = &"chaser"
@export var movement_mode: StringName = &"pursue"
@export var skill_states: Array[StringName] = []
@export var telegraph_seconds := 0.0
@export var heal_amount := 0.0
@export var ally_speed_bonus := 0.0
@export var spawn_reinforcements := false
@export var flank_angle_degrees := 0.0
@export var hazard_damage := 0.0
@export var material_steal := 0
@export var slow_multiplier := 1.0
@export var pulse_interval := 2.5
@export var effect_radius := 180.0
@export var damage_taken_multiplier := 1.0
@export var ambush_distance := 0.0
@export var status_immunities: Array[StringName] = []


func to_role_profile() -> EnemyRoleProfile:
	var profile := EnemyRoleProfile.new()
	profile.heal_amount = maxf(0.0, heal_amount)
	profile.ally_speed_bonus = clampf(ally_speed_bonus, 0.0, 0.35)
	profile.can_spawn_reinforcements = spawn_reinforcements
	profile.flank_angle = deg_to_rad(flank_angle_degrees)
	profile.hazard_damage = maxf(0.0, hazard_damage)
	profile.material_steal = maxi(0, material_steal)
	profile.slow_multiplier = clampf(slow_multiplier, 0.4, 1.0)
	profile.pulse_interval = maxf(0.25, pulse_interval)
	profile.effect_radius = maxf(1.0, effect_radius)
	profile.damage_taken_multiplier = clampf(damage_taken_multiplier, 0.1, 4.0)
	profile.ambush_distance = maxf(0.0, ambush_distance)
	return profile
