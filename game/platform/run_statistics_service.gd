class_name RunStatisticsService
extends RefCounted

var values: Dictionary = {"kills": 0, "damage_dealt": 0.0, "damage_taken": 0.0, "materials_collected": 0}


func record(counter: StringName, amount: float = 1.0) -> void:
	values[counter] = float(values.get(counter, 0.0)) + amount


func snapshot() -> Dictionary:
	return values.duplicate(true)
