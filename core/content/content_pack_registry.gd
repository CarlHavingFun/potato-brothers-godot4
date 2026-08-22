class_name ContentPackRegistry
extends RefCounted


const SUPPORTED_API_VERSION := ContentPackDef.CURRENT_API_VERSION


func build_candidate(
	core_pack: ContentPackDef,
	optional_packs: Array[ContentPackDef],
	enabled_ids: PackedStringArray,
	balance_pack: BalancePackDef = null
) -> Dictionary:
	var errors := PackedStringArray()
	if core_pack == null or core_pack.pack_id != &"core":
		errors.append("mandatory core pack is missing")
		return _failure(errors)

	var available: Dictionary = {&"core": core_pack}
	for pack: ContentPackDef in optional_packs:
		if pack == null or pack.pack_id.is_empty() or pack.pack_id == &"core":
			errors.append("optional pack has an invalid pack_id")
			continue
		if available.has(pack.pack_id):
			errors.append("duplicate installed pack: %s" % pack.pack_id)
			continue
		available[pack.pack_id] = pack
	if not errors.is_empty():
		return _failure(errors)

	var requested: Dictionary = {&"core": true}
	for raw_id: String in enabled_ids:
		var pack_id := StringName(raw_id)
		if pack_id == &"core":
			continue
		if not available.has(pack_id):
			errors.append("enabled pack is not installed: %s" % pack_id)
			continue
		requested[pack_id] = true
	if not errors.is_empty():
		return _failure(errors)

	for pack_id: StringName in requested:
		var pack := available[pack_id] as ContentPackDef
		_validate_pack_contract(pack, errors)
		for dependency in pack.dependencies:
			if dependency == null or dependency.pack_id.is_empty():
				errors.append("pack %s has an invalid dependency" % pack_id)
				continue
			if not requested.has(dependency.pack_id):
				errors.append(
					"pack %s requires enabled dependency %s" % [pack_id, dependency.pack_id]
				)
				continue
			var installed := available.get(dependency.pack_id) as ContentPackDef
			if installed == null:
				errors.append("pack %s is missing dependency %s" % [pack_id, dependency.pack_id])
				continue
			if _compare_versions(installed.pack_version, dependency.minimum_version) < 0:
				errors.append(
					"pack %s requires %s >= %s" % [
						pack_id, dependency.pack_id, dependency.minimum_version
					]
				)
	if not errors.is_empty():
		return _failure(errors)

	var ordered_ids: Array[StringName] = []
	var visiting := {}
	var visited := {}
	for pack_id: StringName in requested:
		_visit(pack_id, available, requested, visiting, visited, ordered_ids, errors)
	if not errors.is_empty():
		return _failure(errors)

	var ordered_packs: Array[ContentPackDef] = []
	for pack_id: StringName in ordered_ids:
		ordered_packs.append(available[pack_id] as ContentPackDef)
	var catalog := ContentCatalog.new()
	var registration_error := catalog.register_packs(ordered_packs, balance_pack)
	if registration_error != OK:
		errors.append("content catalog registration failed: %s" % error_string(registration_error))
		return _failure(errors)
	return {
		"catalog": catalog,
		"active_pack_ids": PackedStringArray(ordered_ids.map(func(id): return String(id))),
		"errors": errors,
		"restart_required": false,
	}


func _visit(
	pack_id: StringName,
	available: Dictionary,
	requested: Dictionary,
	visiting: Dictionary,
	visited: Dictionary,
	ordered: Array[StringName],
	errors: PackedStringArray
) -> void:
	if visited.has(pack_id) or not errors.is_empty():
		return
	if visiting.has(pack_id):
		errors.append("content pack dependency cycle includes %s" % pack_id)
		return
	visiting[pack_id] = true
	var pack := available[pack_id] as ContentPackDef
	for dependency in pack.dependencies:
		if dependency != null and requested.has(dependency.pack_id):
			_visit(
				dependency.pack_id, available, requested, visiting, visited, ordered, errors
			)
	visiting.erase(pack_id)
	if not errors.is_empty():
		return
	visited[pack_id] = true
	ordered.append(pack_id)


func _validate_pack_contract(pack: ContentPackDef, errors: PackedStringArray) -> void:
	if pack.content_api_version != SUPPORTED_API_VERSION:
		errors.append("pack %s uses unsupported content API %d" % [
			pack.pack_id, pack.content_api_version
		])
	if not _is_semantic_version(pack.pack_version):
		errors.append("pack %s has invalid version %s" % [pack.pack_id, pack.pack_version])
	match pack.pack_kind:
		ContentPackDef.PackKind.CORE:
			if pack.pack_id != &"core":
				errors.append("only the core pack may use core pack kind")
		ContentPackDef.PackKind.CHARACTER:
			if pack.characters.size() != 1:
				errors.append("character pack %s must contain exactly one character" % pack.pack_id)
		ContentPackDef.PackKind.WEAPON:
			if pack.weapons.size() != 1:
				errors.append("weapon pack %s must contain exactly one weapon" % pack.pack_id)


func _is_semantic_version(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 3:
		return false
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int() or int(part) < 0:
			return false
	return true


func _compare_versions(left: String, right: String) -> int:
	if not _is_semantic_version(left) or not _is_semantic_version(right):
		return -1
	var left_parts := left.split(".")
	var right_parts := right.split(".")
	for index in 3:
		var delta := int(left_parts[index]) - int(right_parts[index])
		if delta != 0:
			return signi(delta)
	return 0


func _failure(errors: PackedStringArray) -> Dictionary:
	return {
		"catalog": null,
		"active_pack_ids": PackedStringArray(),
		"errors": errors,
		"restart_required": false,
	}
