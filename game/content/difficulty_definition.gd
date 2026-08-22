class_name GogoDifficultyDefinition
extends GogoContentDefinition

@export var enemy_health_multiplier: float = 1.0
@export var enemy_damage_multiplier: float = 1.0
@export var enemy_speed_multiplier: float = 1.0
@export var spawn_multiplier: float = 1.0


func _init() -> void:
	kind = &"difficulty"
