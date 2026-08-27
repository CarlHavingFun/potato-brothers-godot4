class_name GogoWeaponRuntimeStats
extends RefCounted

var definition_id: StringName
var static_asset_id: StringName = &""
var mode: GogoWeaponDefinition.Mode
var damage: float
var cooldown_seconds: float
var attack_range: float
var projectile_speed: float
var projectile_count: int
var spread_degrees: float
var knockback: float
var feedback_profile_id: StringName = &"rifle"
var damage_kind: StringName = &"ballistic"
var impact_kind: StringName = &"normal"
