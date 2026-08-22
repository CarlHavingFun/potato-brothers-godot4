class_name GogoZoneDefinition
extends GogoContentDefinition

@export var arena_size: Vector2 = Vector2(2048.0, 1536.0)
@export var wave_ids: Array[StringName] = []


func _init() -> void:
	kind = &"zone"
