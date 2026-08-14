class_name PlayerStats
extends RefCounted


var _values := PackedFloat64Array()


func _init(initial_values: Dictionary = {}) -> void:
	_values.resize(StatId.size())
	_values.fill(0.0)
	for raw_key: Variant in initial_values:
		var stat_id := _resolve_stat_id(raw_key)
		if StatId.is_valid(stat_id):
			_values[stat_id] = float(initial_values[raw_key])


func get_stat(stat_id: int) -> float:
	if not StatId.is_valid(stat_id):
		return 0.0
	return _values[stat_id]


func set_stat(stat_id: int, value: float) -> bool:
	if not StatId.is_valid(stat_id):
		return false
	_values[stat_id] = value
	return true


func add_stat(stat_id: int, amount: float) -> bool:
	if not StatId.is_valid(stat_id):
		return false
	_values[stat_id] += amount
	return true


func copy() -> PlayerStats:
	return PlayerStats.from_dict(to_dict())


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	for stat_id in StatId.size():
		result[StatId.key(stat_id)] = _values[stat_id]
	return result


static func from_dict(data: Dictionary) -> PlayerStats:
	return PlayerStats.new(data)


static func _resolve_stat_id(raw_key: Variant) -> int:
	if typeof(raw_key) == TYPE_INT:
		return int(raw_key)
	if typeof(raw_key) == TYPE_STRING or typeof(raw_key) == TYPE_STRING_NAME:
		return StatId.from_key(str(raw_key))
	return -1
