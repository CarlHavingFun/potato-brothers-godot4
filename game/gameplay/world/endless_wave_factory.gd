class_name EndlessWaveFactory
extends RefCounted


func build(wave_number: int, enemy_ids: Array[StringName], normal_limit: int = 20) -> GogoWaveDefinition:
	if normal_limit < 1 or wave_number <= normal_limit or enemy_ids.is_empty():
		return null
	for enemy_id in enemy_ids:
		if enemy_id.is_empty():
			return null
	# Clamp before arithmetic; cost and stats never depend on the absolute index.
	var step := mini(wave_number - normal_limit, 200)
	var count := mini(280 + 12 * step, 480)
	var definition := GogoWaveDefinition.new()
	definition.content_id = StringName("gogobro.runtime:wave/endless_%d" % wave_number)
	definition.display_name = "无尽波次 %d" % wave_number
	definition.wave_number = wave_number
	definition.duration_seconds = 60.0
	definition.enemy_health_multiplier = 2.5 + 0.15 * step
	definition.enemy_damage_multiplier = 1.75 + 0.05 * step
	definition.enemy_speed_multiplier = 1.15 + 0.01 * mini(step, 35)
	# Same W20 roles/starts, with a rounded cumulative split conserving the total.
	var cumulative := [160, 220, 272, 280]
	var starts := [1.0, 6.0, 10.0, 33.0]
	var previous := 0
	for index in 4:
		var prefix := roundi(float(count) * float(cumulative[index]) / 280.0)
		definition.spawn_groups.append({
			"enemy_id": enemy_ids[index % enemy_ids.size()],
			"count": prefix - previous,
			"start": starts[index], "end": 59.0 if index < 3 else 58.0,
			"phase": &"endless_pressure",
		})
		previous = prefix
	return definition
