class_name GogoWeaponInventory
extends Resource

const CAPACITY := 6
const MAX_ID := 9007199254740991

@export_storage var _records: Array[Dictionary] = []
@export_storage var _next_id: int = 1


func records() -> Array[Dictionary]:
	return _records.duplicate(true)


func content_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for value: Dictionary in _records:
		result.append(value["content_id"] as StringName)
	return result


func size() -> int:
	return _records.size()


func next_id() -> int:
	return _next_id


func record(instance_id: int) -> Dictionary:
	var index := index_of(instance_id)
	return _records[index].duplicate(true) if index >= 0 else {}


func index_of(instance_id: int) -> int:
	if instance_id <= 0:
		return -1
	for index in _records.size():
		if _records[index].get("instance_id", 0) == instance_id:
			return index
	return -1


func validate_add(content_id: StringName, snapshot: ContentSnapshot, quality: int = 1) -> Error:
	if content_id.is_empty() or snapshot == null or not snapshot.has_definition(content_id, &"weapon"):
		return ERR_INVALID_DATA
	if not _is_valid_quality(quality):
		return ERR_INVALID_DATA
	if _records.size() >= CAPACITY:
		return ERR_UNAVAILABLE
	if _next_id < 1 or _next_id >= MAX_ID:
		return ERR_UNAVAILABLE
	return OK


func add_weapon(content_id: StringName, snapshot: ContentSnapshot, quality: int = 1) -> Dictionary:
	var error := validate_add(content_id, snapshot, quality)
	if error != OK:
		return {"error": error, "instance_id": 0}
	var instance_id := _next_id
	_records.append({"instance_id": instance_id, "content_id": content_id, "quality": quality})
	_next_id += 1
	return {"error": OK, "instance_id": instance_id}


func remove_weapon(instance_id: int) -> Error:
	var index := index_of(instance_id)
	if index < 0:
		return ERR_UNAVAILABLE
	_records.remove_at(index)
	return OK


func combination_partner(instance_id: int) -> int:
	var selected_index := index_of(instance_id)
	if selected_index < 0:
		return 0
	var selected: Dictionary = _records[selected_index]
	var selected_quality: int = selected.get("quality", 0)
	if not _is_valid_quality(selected_quality) or selected_quality >= 4:
		return 0
	for index in _records.size():
		if index == selected_index:
			continue
		var candidate: Dictionary = _records[index]
		if candidate.get("content_id", &"") == selected.get("content_id", &"") and candidate.get("quality", 0) == selected_quality:
			return candidate.get("instance_id", 0)
	return 0


func combine_weapon(instance_id: int) -> Error:
	var selected_index := index_of(instance_id)
	var partner_id := combination_partner(instance_id)
	if selected_index < 0 or partner_id == 0:
		return ERR_UNAVAILABLE
	var partner_index := index_of(partner_id)
	if partner_index < 0:
		return ERR_UNAVAILABLE
	_records[selected_index]["quality"] += 1
	_records.remove_at(partner_index)
	return OK


static func parse_records(raw: Variant, raw_next: Variant, snapshot: ContentSnapshot) -> Dictionary:
	if snapshot == null:
		return _parse_error("weapons", "content snapshot is required")
	if not raw is Array:
		return _parse_error("weapons", "expected array")
	var next_check: Dictionary = _checked_id(raw_next, "next_weapon_instance_id")
	if next_check.error != OK:
		return next_check
	var parsed_records: Array[Dictionary] = []
	var seen_ids := {}
	if raw.size() > CAPACITY:
		return _parse_error("weapons", "capacity exceeded")
	for index in raw.size():
		var path := "weapons[%d]" % index
		var raw_record: Variant = raw[index]
		if not raw_record is Dictionary:
			return _parse_error(path, "expected record")
		if raw_record.size() != 3 or not raw_record.has_all(["instance_id", "content_id", "quality"]):
			return _parse_error(path, "expected exact weapon record")
		var id_check: Dictionary = _checked_id(raw_record["instance_id"], path + ".instance_id")
		if id_check.error != OK:
			return id_check
		var instance_id: int = id_check.value
		if instance_id >= next_check.value or seen_ids.has(instance_id):
			return _parse_error(path + ".instance_id", "must be unique and less than next weapon instance ID")
		var content_check: Dictionary = _checked_content_id(raw_record["content_id"], snapshot, path + ".content_id")
		if content_check.error != OK:
			return content_check
		var quality_check: Dictionary = _checked_quality(raw_record["quality"], path + ".quality")
		if quality_check.error != OK:
			return quality_check
		seen_ids[instance_id] = true
		parsed_records.append({
			"instance_id": instance_id,
			"content_id": content_check.value,
			"quality": quality_check.value,
		})
	var inventory: Variant = load("res://game/session/weapon_inventory.gd").new()
	inventory._records = parsed_records
	inventory._next_id = next_check.value
	return {"inventory": inventory, "error": OK, "path": "", "message": ""}


static func _parse_error(path: String, message: String) -> Dictionary:
	return {"inventory": null, "error": ERR_INVALID_DATA, "path": path, "message": message}


static func _checked_id(raw: Variant, path: String) -> Dictionary:
	var value: Variant = _checked_integer(raw, 1, MAX_ID)
	if value == null:
		return _parse_error(path, "expected bounded integer")
	return {"error": OK, "value": value, "path": "", "message": ""}


static func _checked_quality(raw: Variant, path: String) -> Dictionary:
	var value: Variant = _checked_integer(raw, 1, 4)
	if value == null:
		return _parse_error(path, "expected weapon quality I-IV")
	return {"error": OK, "value": value, "path": "", "message": ""}


static func _checked_content_id(raw: Variant, snapshot: ContentSnapshot, path: String) -> Dictionary:
	if not (raw is String or raw is StringName):
		return _parse_error(path, "expected weapon content ID")
	var content_id := StringName(raw)
	if content_id.is_empty() or not snapshot.has_definition(content_id, &"weapon"):
		return _parse_error(path, "unknown weapon content ID")
	return {"error": OK, "value": content_id, "path": "", "message": ""}


static func _checked_integer(raw: Variant, minimum: int, maximum: int) -> Variant:
	if typeof(raw) == TYPE_INT:
		if raw >= minimum and raw <= maximum:
			return raw
	elif typeof(raw) == TYPE_FLOAT:
		if is_finite(raw) and raw == floor(raw) and raw >= float(minimum) and raw <= float(maximum):
			return int(raw)
	return null


static func _is_valid_quality(quality: int) -> bool:
	return quality >= 1 and quality <= 4
