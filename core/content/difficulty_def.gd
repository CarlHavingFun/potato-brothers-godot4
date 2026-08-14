class_name DifficultyDef
extends Resource


const _DEFAULT_MULTIPLIERS: Dictionary = {
	1: [1.00, 1.00, 1.00, 1.00],
	2: [1.10, 1.05, 1.00, 1.10],
	3: [1.25, 1.15, 1.03, 1.20],
	4: [1.45, 1.25, 1.06, 1.30],
	5: [1.70, 1.40, 1.10, 1.40],
}

@export_range(1, 5, 1) var level: int = 1
@export var health_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var spawn_density_multiplier: float = 1.0


func _init(
	level_value: int = 1,
	health_value: float = 1.0,
	damage_value: float = 1.0,
	speed_value: float = 1.0,
	spawn_density_value: float = 1.0
) -> void:
	level = level_value
	health_multiplier = health_value
	damage_multiplier = damage_value
	speed_multiplier = speed_value
	spawn_density_multiplier = spawn_density_value


static func for_level(level_value: int) -> DifficultyDef:
	if not _DEFAULT_MULTIPLIERS.has(level_value):
		return null
	var values: Array = _DEFAULT_MULTIPLIERS[level_value]
	return DifficultyDef.new(level_value, values[0], values[1], values[2], values[3])


func scale_health(base_health: int) -> int:
	return roundi(base_health * health_multiplier)


func scale_damage(base_damage: float) -> float:
	return base_damage * damage_multiplier


func scale_speed(base_speed: float) -> float:
	return base_speed * speed_multiplier


func scale_spawn_count(base_count: int) -> int:
	return roundi(base_count * spawn_density_multiplier)
