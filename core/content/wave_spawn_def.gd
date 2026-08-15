class_name WaveSpawnDef
extends Resource


@export var enemy_id: StringName
@export_range(0.01, 1000.0, 0.01) var weight := 1.0
@export var is_boss := false
@export var is_elite := false


func is_priority_spawn() -> bool:
	return is_boss or is_elite
