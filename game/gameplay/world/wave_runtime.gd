class_name WaveRuntime
extends RefCounted

var wave: GogoWaveDefinition
var elapsed := 0.0
var schedules: Array[Dictionary] = []


func begin(definition: GogoWaveDefinition, spawn_multiplier: float) -> void:
	wave = definition
	elapsed = 0.0
	schedules.clear()
	for group: Dictionary in definition.spawn_groups:
		var count := maxi(1, int(round(float(group.get("count", 1)) * spawn_multiplier)))
		var start := float(group.get("start", 0.0))
		var end := maxf(float(group.get("end", definition.duration_seconds)), start + 0.01)
		schedules.append({
			"enemy_id": StringName(group.get("enemy_id", "")),
			"remaining": count,
			"next_spawn": start,
			"interval": (end - start) / float(count),
		})


func tick(delta: float) -> Array[StringName]:
	elapsed += delta
	var due: Array[StringName] = []
	for schedule: Dictionary in schedules:
		while int(schedule["remaining"]) > 0 and elapsed >= float(schedule["next_spawn"]):
			due.append(schedule["enemy_id"])
			schedule["remaining"] = int(schedule["remaining"]) - 1
			schedule["next_spawn"] = float(schedule["next_spawn"]) + float(schedule["interval"])
	return due


func is_finished() -> bool:
	return wave != null and elapsed >= wave.duration_seconds
