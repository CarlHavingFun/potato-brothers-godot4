class_name GogoStatPipeline
extends RefCounted

const ORDER: Array[StringName] = [&"character", &"equipment", &"temporary", &"difficulty", &"final_clamp"]


func rebuild(base_stats: Dictionary, modifiers_by_stage: Dictionary) -> Dictionary:
	var result := base_stats.duplicate(true)
	for stage in ORDER:
		for modifiers: Dictionary in modifiers_by_stage.get(stage, []):
			_apply_modifiers(result, modifiers)
	_apply_percent_multipliers(result)
	_clamp_final(result)
	return result


func _apply_modifiers(stats: Dictionary, modifiers: Dictionary) -> void:
	for key: StringName in modifiers:
		stats[key] = float(stats.get(key, 0.0)) + float(modifiers[key])


func _apply_percent_multipliers(stats: Dictionary) -> void:
	stats[&"movement_speed"] = float(stats.get(&"movement_speed", 1.0)) * (
		1.0 + float(stats.get(&"movement_speed_multiplier", 0.0))
	)
	stats[&"attack_speed"] = float(stats.get(&"attack_speed", 1.0)) * (
		1.0 + float(stats.get(&"attack_speed_multiplier", 0.0))
	)


func _clamp_final(stats: Dictionary) -> void:
	stats[&"max_health"] = maxf(float(stats.get(&"max_health", 1.0)), 1.0)
	stats[&"movement_speed"] = maxf(float(stats.get(&"movement_speed", 1.0)), 40.0)
	stats[&"attack_speed"] = maxf(float(stats.get(&"attack_speed", 1.0)), 0.1)
	stats[&"dodge"] = clampf(float(stats.get(&"dodge", 0.0)), 0.0, 0.6)
	stats[&"armor"] = maxf(float(stats.get(&"armor", 0.0)), -20.0)
