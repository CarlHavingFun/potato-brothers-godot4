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
		schedules.append_array(build_group_schedules(group, definition.duration_seconds, spawn_multiplier))


# Runtime and preflight share the same count/window/interval normalization.
# This is compilation only: callers validate untrusted inputs before building.
static func build_group_schedules(group: Dictionary, duration_seconds: float, spawn_multiplier: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := maxi(1, int(round(float(group.get("count", 1)) * spawn_multiplier)))
	var start := float(group.get("start", 0.0))
	var end := maxf(float(group.get("end", duration_seconds)), start + 0.01)
	if group.has("batch_size"):
		var authored_count := maxi(0, int(group.get("count", 1)))
		var batch_size := maxi(1, int(group["batch_size"]))
		var authored_batches := ceili(float(authored_count) / float(batch_size))
		var interval := maxf(float(group.get("interval_seconds", (end - start) / float(maxi(authored_count, 1)))), 0.01)
		var previous_scaled_prefix := 0
		for batch_index in authored_batches:
			var authored_prefix := mini((batch_index + 1) * batch_size, authored_count)
			var scaled_prefix := roundi(float(authored_prefix) * maxf(spawn_multiplier, 0.0))
			var batch := scaled_prefix - previous_scaled_prefix
			previous_scaled_prefix = scaled_prefix
			# One schedule per authored slot retains partial batches and timing.
			# Prefix differences conserve the rounded total; zero-sized slots
			# stay empty rather than pulling later enemies into an earlier slot.
			result.append({
				"enemy_id": StringName(group.get("enemy_id", "")),
				"remaining": batch,
				"next_spawn": start + float(batch_index) * interval,
				"batch_size": maxi(batch, 1),
				"interval": interval,
			})
		return result
	# Preserve the existing continuous-group contract when no batch is authored.
	result.append({
		"enemy_id": StringName(group.get("enemy_id", "")),
		"remaining": count,
		"next_spawn": start,
		"batch_size": 1,
		"interval": maxf(float(group.get("interval_seconds", (end - start) / float(count))), 0.01),
	})
	return result


func tick(delta: float) -> Array[StringName]:
	elapsed += delta
	var due: Array[StringName] = []
	for schedule: Dictionary in schedules:
		while int(schedule["remaining"]) > 0 and elapsed >= float(schedule["next_spawn"]):
			var batch := mini(int(schedule["batch_size"]), int(schedule["remaining"]))
			for index in batch:
				due.append(schedule["enemy_id"])
			schedule["remaining"] = int(schedule["remaining"]) - batch
			schedule["next_spawn"] = float(schedule["next_spawn"]) + float(schedule["interval"])
	return due


func is_finished() -> bool:
	return wave != null and elapsed >= wave.duration_seconds
