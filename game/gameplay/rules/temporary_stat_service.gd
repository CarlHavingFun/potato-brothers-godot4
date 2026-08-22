class_name TemporaryStatService
extends RefCounted

var _entries: Array[Dictionary] = []


func add(source_id: StringName, modifiers: Dictionary, duration: float) -> void:
	_entries.append({"source_id": source_id, "modifiers": modifiers.duplicate(true), "remaining": maxf(duration, 0.0)})


func tick(delta: float) -> void:
	for index in range(_entries.size() - 1, -1, -1):
		_entries[index].remaining = float(_entries[index].remaining) - delta
		if float(_entries[index].remaining) <= 0.0:
			_entries.remove_at(index)


func combined_modifiers() -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in _entries:
		for stat: StringName in entry.modifiers:
			result[stat] = float(result.get(stat, 0.0)) + float(entry.modifiers[stat])
	return result
