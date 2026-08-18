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
@export_range(0.01, 1.0, 0.01) var burst_interval := 0.08
@export_range(0.01, 2.0, 0.01) var charge_duration := 0.24
@export_range(1, 12, 1) var beam_pulse_count := 3
@export_range(0.01, 1.0, 0.01) var beam_pulse_interval := 0.045
@export_range(0.03, 1.0, 0.01) var continuous_tick_interval := 0.10
@export_range(0.05, 2.0, 0.01) var boomerang_outbound_duration := 0.28
@export_range(0, 8, 1) var pierce := 0
@export_range(0, 8, 1) var bounce := 0
@export_range(0.0, 1.0, 0.01) var pierce_damage_retention := 0.75
@export_range(0.0, 1.0, 0.01) var bounce_damage_retention := 0.65
@export var damage_multiplier := 1.0
@export var cooldown_multiplier := 1.0
@export var projectile_speed_multiplier := 1.0
@export var melee_reach_multiplier := 1.0
@export var swing_degrees := 0.0
@export var active_duration_multiplier := 1.0
@export var explosion_radius := 0.0
@export_range(0.0, 5.0, 0.05) var explosion_damage_scale := 0.5
@export var status_id: StringName
@export_range(0.0, 30.0, 0.1) var status_duration := 2.5
@export_range(1, 99, 1) var status_stacks := 1
@export_range(0.0, 5.0, 0.05) var status_damage_scale := 0.1
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


func volley_rotations(base_rotation: float, sequence_index: int = 0) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for lane: int in maxi(1, projectile_count):
		var centered := float(lane) - float(maxi(1, projectile_count) - 1) * 0.5
		result.append(
			base_rotation
			+ deg_to_rad(centered * spread_degrees)
			+ float(maxi(0, sequence_index)) * 0.0075
		)
	return result


func attack_windup() -> float:
	return maxf(0.01, charge_duration) if kind == Kind.CHARGED else 0.0


func runtime_shot_count() -> int:
	if kind == Kind.BEAM:
		return maxi(1, beam_pulse_count)
	if kind == Kind.BURST:
		return maxi(1, burst_count)
	return 1


func runtime_shot_interval() -> float:
	if kind == Kind.BEAM:
		return maxf(0.01, beam_pulse_interval)
	if kind == Kind.BURST:
		return maxf(0.01, burst_interval)
	return 0.0


func sequence_duration() -> float:
	return float(runtime_shot_count() - 1) * runtime_shot_interval()


func projectile_modifiers() -> Dictionary:
	return {
		"pierce": maxi(0, pierce),
		"bounce": maxi(0, bounce),
		"pierce_damage_retention": clampf(pierce_damage_retention, 0.0, 1.0),
		"bounce_damage_retention": clampf(bounce_damage_retention, 0.0, 1.0),
		"damage_multiplier": maxf(0.0, damage_multiplier),
		"speed_multiplier": maxf(0.05, projectile_speed_multiplier),
		"explosion_radius": maxf(0.0, explosion_radius),
		"explosion_damage_scale": maxf(0.0, explosion_damage_scale),
		"status_id": String(status_id),
		"status_duration": maxf(0.0, status_duration),
		"status_stacks": maxi(1, status_stacks),
		"status_damage_scale": maxf(0.0, status_damage_scale),
		"runtime_motion": "boomerang" if kind == Kind.BOOMERANG else "linear",
		"boomerang_outbound_duration": maxf(0.05, boomerang_outbound_duration),
	}


func behavior_signature() -> String:
	return JSON.stringify({
		"kind": kind,
		"projectile_count": projectile_count,
		"burst_count": burst_count,
		"burst_interval": burst_interval,
		"charge_duration": charge_duration,
		"beam_pulses": beam_pulse_count,
		"beam_interval": beam_pulse_interval,
		"continuous_tick": continuous_tick_interval,
		"boomerang_outbound": boomerang_outbound_duration,
		"spread": spread_degrees,
		"pierce": pierce,
		"bounce": bounce,
		"pierce_retention": pierce_damage_retention,
		"bounce_retention": bounce_damage_retention,
		"damage": damage_multiplier,
		"cooldown": cooldown_multiplier,
		"speed": projectile_speed_multiplier,
		"reach": melee_reach_multiplier,
		"swing": swing_degrees,
		"active": active_duration_multiplier,
		"explosion": explosion_radius,
		"explosion_scale": explosion_damage_scale,
		"status": String(status_id),
		"status_duration": status_duration,
		"status_stacks": status_stacks,
		"status_scale": status_damage_scale,
		"summon": summon_count,
	})
