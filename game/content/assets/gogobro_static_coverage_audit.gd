class_name GogoStaticCoverageAudit
extends RefCounted


const REQUIRED_VISUAL_ASSET_IDS: Array[StringName] = [
	&"community_server_floor",
	&"combat_hud_shell",
]
const VALID_SOURCE_KINDS: Array[StringName] = [
	&"approved_shipping",
	&"development_preview",
]


static func build(
	registry_path: String,
	snapshot: GogoStaticAssetSnapshot,
	observations: Array
) -> Dictionary:
	var registry := _load_registry(registry_path)
	var expected_ids: Array[StringName] = []
	var categories: Dictionary = {}
	if not registry.is_empty():
		for raw_unit: Variant in registry.get("units", []):
			if not raw_unit is Dictionary:
				continue
			var unit := raw_unit as Dictionary
			if String(unit.get("category", "")) == "character_creature":
				continue
			var asset_id := StringName(String(unit.get("asset_id", "")))
			if asset_id.is_empty() or expected_ids.has(asset_id):
				continue
			expected_ids.append(asset_id)
			categories[asset_id] = StringName(String(unit.get("category", "")))

	var valid_by_asset: Dictionary = {}
	var accepted: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for raw_observation: Variant in observations:
		if not raw_observation is Dictionary:
			rejected.append({"reason": &"not_a_dictionary"})
			continue
		var observation := raw_observation as Dictionary
		var validation := _validate_observation(observation, expected_ids, snapshot)
		if not bool(validation.get("valid", false)):
			var rejection := observation.duplicate(true)
			rejection["reason"] = validation.get("reason", &"invalid")
			rejected.append(rejection)
			continue
		var normalized := validation.normalized as Dictionary
		accepted.append(normalized)
		var asset_id := normalized.asset_id as StringName
		var bucket: Array = valid_by_asset.get(asset_id, [])
		bucket.append(normalized)
		valid_by_asset[asset_id] = bucket

	var unresolved: Array[StringName] = []
	var rows: Array[Dictionary] = []
	var source_counts := {
		"approved_shipping": 0,
		"development_preview": 0,
	}
	for asset_id in expected_ids:
		var asset_observations: Array = valid_by_asset.get(asset_id, [])
		if asset_observations.is_empty():
			unresolved.append(asset_id)
		else:
			var source := _preferred_source(asset_observations)
			source_counts[String(source)] = int(source_counts.get(String(source), 0)) + 1
		rows.append({
			"asset_id": asset_id,
			"category": categories.get(asset_id, &""),
			"covered": not asset_observations.is_empty(),
			"observations": asset_observations,
		})
	unresolved.sort()
	var required_failures: Array[StringName] = []
	for asset_id in REQUIRED_VISUAL_ASSET_IDS:
		if unresolved.has(asset_id):
			required_failures.append(asset_id)
	return {
		"schema_version": "gogobro-static-coverage-v1",
		"expected_units": expected_ids.size(),
		"covered_units": expected_ids.size() - unresolved.size(),
		"unresolved_asset_ids": unresolved,
		"required_visual_failures": required_failures,
		"source_unit_counts": source_counts,
		"accepted_observations": accepted,
		"rejected_observations": rejected,
		"asset_rows": rows,
		"complete": (
			expected_ids.size() == GogoStaticAssetSnapshot.DEFAULT_EXPECTED_NONCHARACTER_UNITS
			and unresolved.is_empty()
			and required_failures.is_empty()
		),
	}


static func is_allowed_consumer_scene(scene_path: String) -> bool:
	var normalized := scene_path.replace("\\", "/").to_lower()
	return (
		normalized.begins_with("res://")
		and not normalized.contains("/tools/")
		and not normalized.contains("gallery")
		and not normalized.contains("preview_sheet")
	)


static func _validate_observation(
	observation: Dictionary,
	expected_ids: Array[StringName],
	snapshot: GogoStaticAssetSnapshot
) -> Dictionary:
	var asset_id := StringName(String(observation.get("asset_id", "")))
	var role := StringName(String(observation.get("role", "")))
	var selector := StringName(String(observation.get("selector", "")))
	var scene := String(observation.get("scene", ""))
	var node := String(observation.get("node", ""))
	var source_kind := StringName(String(observation.get("source_kind", "")))
	var texture_size := _vector2i(observation.get("texture_size"))
	var integer_scale := _vector2i(observation.get("integer_display_scale"))
	if not expected_ids.has(asset_id):
		return {"valid": false, "reason": &"unknown_asset"}
	if role.is_empty() or node.strip_edges().is_empty():
		return {"valid": false, "reason": &"missing_consumer_identity"}
	if not is_allowed_consumer_scene(scene):
		return {"valid": false, "reason": &"consumer_scene_forbidden"}
	if not VALID_SOURCE_KINDS.has(source_kind):
		return {"valid": false, "reason": &"source_kind_invalid"}
	if texture_size.x <= 0 or texture_size.y <= 0:
		return {"valid": false, "reason": &"texture_size_invalid"}
	if integer_scale.x <= 0 or integer_scale.y <= 0:
		return {"valid": false, "reason": &"integer_display_scale_invalid"}
	if snapshot == null:
		return {"valid": false, "reason": &"snapshot_missing"}
	var handle := snapshot.resolve_asset(asset_id, role, selector)
	if handle == null or handle.texture == null:
		return {"valid": false, "reason": &"snapshot_handle_missing"}
	if Vector2i(handle.texture.get_width(), handle.texture.get_height()) != texture_size:
		return {"valid": false, "reason": &"texture_size_mismatch"}
	if not handle.source_kind.is_empty() and handle.source_kind != source_kind:
		return {"valid": false, "reason": &"source_kind_mismatch"}
	return {
		"valid": true,
		"normalized": {
			"asset_id": asset_id,
			"role": role,
			"selector": selector,
			"scene": scene,
			"node": node,
			"texture_size": [texture_size.x, texture_size.y],
			"integer_display_scale": [integer_scale.x, integer_scale.y],
			"source_kind": source_kind,
		},
	}


static func _preferred_source(observations: Array) -> StringName:
	for observation: Dictionary in observations:
		if observation.source_kind == &"approved_shipping":
			return &"approved_shipping"
	return &"development_preview"


static func _load_registry(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector := value as Vector2
		if vector.x == roundf(vector.x) and vector.y == roundf(vector.y):
			return Vector2i(vector)
	if value is Array and (value as Array).size() == 2:
		var values := value as Array
		if values[0] is int and values[1] is int:
			return Vector2i(int(values[0]), int(values[1]))
	return Vector2i.ZERO
