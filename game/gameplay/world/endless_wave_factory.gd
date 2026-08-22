class_name EndlessWaveFactory
extends RefCounted


func build(wave_number: int, enemy_ids: Array[StringName]) -> GogoWaveDefinition:
	var definition := GogoWaveDefinition.new()
	definition.content_id = StringName("gogobro.runtime:wave/endless_%d" % wave_number)
	definition.display_name = "无尽波次 %d" % wave_number
	definition.duration_seconds = minf(30.0 + wave_number * 0.4, 60.0)
	var count := maxi(8 + wave_number * 3, 1)
	for index in count:
		definition.spawn_entries.append({
			"enemy_id": enemy_ids[index % enemy_ids.size()] if not enemy_ids.is_empty() else &"",
			"time": fmod(float(index) * definition.duration_seconds / float(count), definition.duration_seconds),
		})
	return definition
