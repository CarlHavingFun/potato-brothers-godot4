class_name GogoRunStateCodec
extends RefCounted

const GogoWeaponInventory := preload("res://game/session/weapon_inventory.gd")
const INT64_MAX := 9223372036854775807
const RUN_FIELDS := ["schema_version", "run_seed", "rng_state", "current_wave", "total_waves", "phase", "zone_id", "difficulty_id", "won", "ended", "endless", "players", "locked_shop_offer_ids", "shop_offer_wave", "shop_offer_ids", "shop_offer_initialized", "shop_offer_initialization_id", "reroll_count", "upgrade_reroll_count", "pending_upgrade_count", "elapsed_seconds"]
const PLAYER_FIELDS := ["player_index", "character_id", "level", "xp", "xp_to_next_level", "materials", "economy_material_remainder", "current_health", "max_health", "base_stats", "final_stats", "weapons", "next_weapon_instance_id", "item_ids", "upgrade_ids"]
const V1_RUN_DEFAULTS := {"endless": false, "locked_shop_offer_ids": [], "shop_offer_wave": 0, "shop_offer_ids": [], "shop_offer_initialized": false, "shop_offer_initialization_id": 0, "reroll_count": 0, "upgrade_reroll_count": 0, "pending_upgrade_count": 0, "elapsed_seconds": 0.0}
const V1_PLAYER_DEFAULTS := {"economy_material_remainder": 0.0, "weapon_levels": {}}


static func parse(data: Variant, snapshot: ContentSnapshot) -> Dictionary:
	if snapshot == null: return _error("$", "content snapshot is required")
	if not data is Dictionary: return _error("$", "expected run object")
	if not data.has("schema_version"): return _error("schema_version", "required field")
	var version_check := checked_integer(data.schema_version, 1, GogoRunState.SCHEMA_VERSION, "schema_version")
	if version_check.error != OK: return version_check
	var version: int = version_check.value
	var legacy: bool = version == 1
	var fields := RUN_FIELDS.duplicate()
	if version < 3:
		fields.erase("rng_state")
	var shape := _object(data, fields, V1_RUN_DEFAULTS if legacy else {}, "")
	if shape.error != OK: return shape
	var values: Dictionary = shape.value
	for key in ["run_seed", "current_wave", "total_waves", "shop_offer_wave", "shop_offer_initialization_id", "reroll_count", "upgrade_reroll_count", "pending_upgrade_count"]:
		var minimum := -9223372036854775808 if key == "run_seed" else (1 if key in ["current_wave", "total_waves"] else 0)
		var checked := checked_integer(values[key], minimum, INT64_MAX, key)
		if checked.error != OK: return checked
		values[key] = checked.value
	if version < 3:
		# Legacy checkpoints never stored generator progress. This deterministic
		# seed boundary is compatibility only, not a claim of the old random stream.
		var fallback_rng := RandomNumberGenerator.new()
		fallback_rng.seed = values.run_seed
		values["rng_state"] = fallback_rng.state
	var rng_check := checked_integer(values.rng_state, -9223372036854775808, INT64_MAX, "rng_state")
	if rng_check.error != OK: return rng_check
	values.rng_state = rng_check.value
	for key in ["won", "ended", "endless", "shop_offer_initialized"]:
		if not values[key] is bool: return _error(key, "expected boolean")
	if not _is_text(values.phase) or not String(values.phase) in ["selection", "combat", "upgrade", "shop", "settlement"]:
		return _error("phase", "unknown phase")
	for key in ["zone_id", "difficulty_id"]:
		var kind: StringName = &"zone" if key == "zone_id" else &"difficulty"
		var checked := _reference(values[key], snapshot, [kind], key)
		if checked.error != OK: return checked
		values[key] = checked.value
	if not _finite_number(values.elapsed_seconds) or values.elapsed_seconds < 0:
		return _error("elapsed_seconds", "expected finite nonnegative number")
	if values.won and not values.ended: return _error("won", "victory requires ended")
	if values.ended and values.phase != "settlement": return _error("phase", "ended requires settlement")
	if (values.endless and values.current_wave <= values.total_waves) or (not values.endless and values.current_wave > values.total_waves):
		return _error("current_wave", "wave/endless relation is invalid")
	if values.shop_offer_wave > values.current_wave: return _error("shop_offer_wave", "cache cannot be from a future wave")
	for key in ["locked_shop_offer_ids", "shop_offer_ids"]:
		var checked := _references(values[key], snapshot, [&"item", &"weapon"], key, 4, key == "shop_offer_ids", key == "locked_shop_offer_ids")
		if checked.error != OK: return checked
		values[key] = checked.value
	if values.shop_offer_initialized and values.shop_offer_wave == values.current_wave:
		if values.shop_offer_ids.size() != 4:
			return _error("shop_offer_ids", "initialized current-wave cache requires exactly four slots")
		if values.phase != "shop" and not (values.ended and values.phase == "settlement"):
			return _error("phase", "initialized current-wave cache requires shop or ended settlement")
	if not values.players is Array or values.players.is_empty(): return _error("players", "expected nonempty player array")
	var players: Array[SessionPlayerState] = []
	var indices := {}
	for index in values.players.size():
		var path := "players[%d]" % index
		var checked := _player(values.players[index], snapshot, legacy, path)
		if checked.error != OK: return checked
		var player: SessionPlayerState = checked.value
		if indices.has(player.player_index): return _error(path + ".player_index", "duplicate player index")
		indices[player.player_index] = true
		players.append(player)
	# Detached candidates are published only after every player and relation passes.
	var state := GogoRunState.new()
	for key in RUN_FIELDS:
		if key not in ["schema_version", "players"]: state.set(key, values[key])
	state.players = players
	return {"state": state, "error": OK, "path": "", "message": ""}


static func _player(raw: Variant, snapshot: ContentSnapshot, legacy: bool, path: String) -> Dictionary:
	var fields := PLAYER_FIELDS.duplicate()
	if legacy:
		fields.erase("weapons")
		fields.erase("next_weapon_instance_id")
		fields.append_array(["weapon_ids", "weapon_levels"])
	var shape := _object(raw, fields, V1_PLAYER_DEFAULTS if legacy else {}, path)
	if shape.error != OK: return shape
	var values: Dictionary = shape.value
	for key in ["player_index", "level", "xp", "xp_to_next_level", "materials"]:
		var minimum := 1 if key in ["level", "xp_to_next_level"] else 0
		var checked := checked_integer(values[key], minimum, INT64_MAX, path + "." + key)
		if checked.error != OK: return checked
		values[key] = checked.value
	if values.xp >= values.xp_to_next_level: return _error(path + ".xp", "xp must be below next level")
	for key in ["current_health", "max_health", "economy_material_remainder"]:
		if not _finite_number(values[key]): return _error(path + "." + key, "expected finite number")
	if values.max_health <= 0: return _error(path + ".max_health", "must be positive")
	if values.current_health < 0 or values.current_health > values.max_health: return _error(path + ".current_health", "outside health range")
	if values.economy_material_remainder < 0 or values.economy_material_remainder >= 1: return _error(path + ".economy_material_remainder", "outside remainder range")
	var character := _reference(values.character_id, snapshot, [&"character"], path + ".character_id")
	if character.error != OK: return character
	values.character_id = character.value
	for key in ["base_stats", "final_stats"]:
		var stats := _runtime_stats(values[key], path + "." + key)
		if stats.error != OK: return stats
		values[key] = stats.value
	for key in ["item_ids", "upgrade_ids"]:
		var kind: StringName = &"item" if key == "item_ids" else &"upgrade"
		var checked := _references(values[key], snapshot, [kind], path + "." + key)
		if checked.error != OK: return checked
		values[key] = checked.value
	var inventory_result: Dictionary
	if legacy:
		var ids := _references(values.weapon_ids, snapshot, [&"weapon"], path + ".weapon_ids", 6)
		if ids.error != OK: return ids
		if not values.weapon_levels is Dictionary: return _error(path + ".weapon_levels", "expected rank object")
		for id in values.weapon_levels:
			if not _is_text(id) or not ids.value.has(StringName(id)): return _error(path + ".weapon_levels." + str(id), "orphan rank")
			var rank := checked_integer(values.weapon_levels[id], 1, 1, path + ".weapon_levels." + str(id))
			if rank.error != OK: return rank
		var records := []
		for index in ids.value.size(): records.append({"instance_id": index + 1, "content_id": ids.value[index], "quality": 1})
		inventory_result = GogoWeaponInventory.parse_records(records, records.size() + 1, snapshot)
	else:
		# Inventory's standalone validator reports a malformed record as a unit.
		# The run codec additionally promises exact missing/unknown field paths.
		if values.weapons is Array:
			for index in values.weapons.size():
				var weapon_shape := _object(values.weapons[index], ["instance_id", "content_id", "quality"], {}, "%s.weapons[%d]" % [path, index])
				if weapon_shape.error != OK: return weapon_shape
		inventory_result = GogoWeaponInventory.parse_records(values.weapons, values.next_weapon_instance_id, snapshot)
	if inventory_result.error != OK: return _error(path + "." + String(inventory_result.path), String(inventory_result.message))
	var player := SessionPlayerState.new()
	for key in PLAYER_FIELDS:
		if key not in ["weapons", "next_weapon_instance_id"]: player.set(key, values[key])
	player.weapon_inventory = inventory_result.inventory
	return {"error": OK, "value": player}


static func checked_integer(raw: Variant, minimum: int, maximum: int, path: String) -> Dictionary:
	if typeof(raw) == TYPE_INT:
		if raw >= minimum and raw <= maximum: return {"error": OK, "value": raw}
	elif typeof(raw) == TYPE_FLOAT:
		if is_finite(raw) and raw == floor(raw) and raw >= -9223372036854775808.0 and raw < 9223372036854775808.0:
			var converted := int(raw)
			if converted >= minimum and converted <= maximum: return {"error": OK, "value": converted}
	return _error(path, "expected bounded integer")


static func _object(raw: Variant, fields: Array, defaults: Dictionary, path: String) -> Dictionary:
	if not raw is Dictionary: return _error(path, "expected object")
	for key in raw:
		if not _is_text(key) or not fields.has(String(key)): return _error(_child(path, str(key)), "unknown field")
	var values: Dictionary = raw.duplicate(true)
	for field in fields:
		if not values.has(field):
			if not defaults.has(field): return _error(_child(path, field), "required field")
			values[field] = defaults[field].duplicate(true) if defaults[field] is Array or defaults[field] is Dictionary else defaults[field]
	return {"error": OK, "value": values}


static func _reference(raw: Variant, snapshot: ContentSnapshot, kinds: Array, path: String, allow_empty: bool = false) -> Dictionary:
	if not _is_text(raw): return _error(path, "expected content ID string")
	var id := StringName(raw)
	if allow_empty and id.is_empty(): return {"error": OK, "value": id}
	for kind in kinds:
		if not id.is_empty() and snapshot.has_definition(id, kind): return {"error": OK, "value": id}
	return _error(path, "unknown content reference")


static func _references(raw: Variant, snapshot: ContentSnapshot, kinds: Array, path: String, capacity: int = INT64_MAX, allow_empty: bool = false, unique: bool = false) -> Dictionary:
	if not raw is Array or raw.size() > capacity: return _error(path, "expected bounded reference array")
	var ids: Array[StringName] = []
	for index in raw.size():
		var checked := _reference(raw[index], snapshot, kinds, "%s[%d]" % [path, index], allow_empty)
		if checked.error != OK: return checked
		if unique and ids.has(checked.value): return _error("%s[%d]" % [path, index], "duplicate reference")
		ids.append(checked.value)
	return {"error": OK, "value": ids}


static func _finite_number(raw: Variant) -> bool:
	return (typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT) and is_finite(float(raw))


static func _runtime_stats(raw: Variant, path: String) -> Dictionary:
	if not raw is Dictionary: return _error(path, "expected stat object")
	var normalized := {}
	for stat in raw:
		var value: Variant = raw[stat]
		if not _is_text(stat) or not _finite_number(value):
			return _error(path + "." + str(stat), "expected text key and finite numeric stat")
		normalized[StringName(stat)] = _runtime_stat_value(value)
	return {"error": OK, "value": normalized}


static func _runtime_stat_value(value: Variant) -> Variant:
	if typeof(value) != TYPE_INT: return value
	var as_float := float(value)
	# Never convert at the int64 float boundary before proving the reverse cast
	# is safe: int64 extrema and unrepresentable odd integers stay exact ints.
	if as_float > -9223372036854775808.0 and as_float < 9223372036854775808.0 and int(as_float) == value:
		return as_float
	return value


static func _is_text(raw: Variant) -> bool:
	return raw is String or raw is StringName


static func _child(path: String, field: String) -> String:
	return field if path.is_empty() else path + "." + field


static func _error(path: String, message: String) -> Dictionary:
	return {"state": null, "error": ERR_INVALID_DATA, "path": path, "message": message}
