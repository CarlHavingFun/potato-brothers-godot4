class_name WaveDef
extends ContentDef


@export_range(1, 999, 1) var wave_number := 1
@export var duration := 30.0
@export var spawns: Array[WaveSpawnDef]
@export var fixed_spawn_time := 1.0
@export var min_spawn_time := 0.5
@export var max_spawn_time := 1.5
@export var data: WaveData
