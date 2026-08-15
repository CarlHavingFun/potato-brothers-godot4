class_name AttackPatternDef
extends Resource


enum Kind {
	ARC,
	THRUST,
	CONTINUOUS,
	SCATTER,
	BURST,
	CHARGED,
	BOOMERANG,
	BEAM,
	AREA,
	ORBIT,
	BUILDING,
	SUMMON,
}

const KIND_KEYS: Array[StringName] = [
	&"arc", &"thrust", &"continuous", &"scatter", &"burst", &"charged",
	&"boomerang", &"beam", &"area", &"orbit", &"building", &"summon",
]

@export var pattern_id: StringName
@export var kind: Kind = Kind.ARC
@export_range(1, 16, 1) var projectile_count := 1
@export_range(1, 16, 1) var burst_count := 1
@export var spread_degrees := 0.0
@export_range(0, 8, 1) var pierce := 0
@export_range(0, 8, 1) var bounce := 0
@export var damage_multiplier := 1.0
@export var cooldown_multiplier := 1.0
@export var projectile_speed_multiplier := 1.0
@export var melee_reach_multiplier := 1.0
@export var swing_degrees := 0.0
@export var active_duration_multiplier := 1.0
@export var explosion_radius := 0.0
@export var status_id: StringName
@export var summon_count := 0


func kind_key() -> StringName:
	return KIND_KEYS[kind] if kind >= 0 and kind < KIND_KEYS.size() else &"unknown"


func shot_rotations(base_rotation: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var shots := maxi(1, projectile_count) * maxi(1, burst_count)
	for index: int in shots:
		var lane := index % maxi(1, projectile_count)
		var centered := float(lane) - float(maxi(1, projectile_count) - 1) * 0.5
		var burst_offset := floori(float(index) / float(maxi(1, projectile_count))) * 0.0075
		result.append(base_rotation + deg_to_rad(centered * spread_degrees) + burst_offset)
	return result


func projectile_modifiers() -> Dictionary:
	return {
		"pierce": maxi(0, pierce),
		"bounce": maxi(0, bounce),
		"damage_multiplier": maxf(0.0, damage_multiplier),
		"speed_multiplier": maxf(0.05, projectile_speed_multiplier),
		"explosion_radius": maxf(0.0, explosion_radius),
		"status_id": String(status_id),
	}


func behavior_signature() -> String:
	return JSON.stringify({
		"kind": kind,
		"projectile_count": projectile_count,
		"burst_count": burst_count,
		"spread": spread_degrees,
		"pierce": pierce,
		"bounce": bounce,
		"damage": damage_multiplier,
		"cooldown": cooldown_multiplier,
		"speed": projectile_speed_multiplier,
		"reach": melee_reach_multiplier,
		"swing": swing_degrees,
		"active": active_duration_multiplier,
		"explosion": explosion_radius,
		"status": String(status_id),
		"summon": summon_count,
	})
