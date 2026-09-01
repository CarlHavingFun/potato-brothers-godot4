class_name GogoWaveDefinition
extends GogoContentDefinition

@export var wave_number: int = 1
@export var duration_seconds: float = 12.0
@export var spawn_groups: Array[Dictionary] = []
@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0


func _init() -> void:
	kind = &"wave"
