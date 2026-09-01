class_name GogoWeaponRuntimeStats
extends RefCounted

var definition_id: StringName
var weapon_quality: int = 1
var inventory_instance_id: int = 0
var static_asset_id: StringName = &""
var mode: GogoWeaponDefinition.Mode
var damage: float
var cooldown_seconds: float
var attack_range: float
var projectile_speed: float
var projectile_count: int
var spread_degrees: float
var knockback: float
var critical_chance := 0.0
var explosion_damage_multiplier := 1.0
var feedback_profile_id: StringName = &"rifle"
var damage_kind: StringName = &"ballistic"
var impact_kind: StringName = &"normal"
