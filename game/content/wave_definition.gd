class_name GogoWaveDefinition
extends GogoContentDefinition

@export var wave_number: int = 1
@export var duration_seconds: float = 12.0
@export var spawn_groups: Array[Dictionary] = []


func _init() -> void:
	kind = &"wave"
