class_name ContentValidator
extends RefCounted


const FORBIDDEN_EXTENSIONS := {
	"gd": true,
	"gdc": true,
	"dll": true,
	"gdextension": true,
}


func validate_pack(pack: ContentPackDef, source_root := "") -> PackedStringArray:
	var errors := PackedStringArray()
	if pack == null:
		errors.append("pack is required")
		return errors

	_validate_metadata(pack, errors)
	_validate_definitions(pack, errors)
	_validate_references(pack, errors)
	if not source_root.is_empty():
		_validate_source_directory(source_root.trim_suffix("/"), errors)
	return errors


func _validate_metadata(pack: ContentPackDef, errors: PackedStringArray) -> void:
	var pack_id_pattern := RegEx.new()
	pack_id_pattern.compile("^[a-z0-9][a-z0-9_.-]*$")
	if pack.pack_id.is_empty() or pack_id_pattern.search(String(pack.pack_id)) == null:
		errors.append("pack_id must match ^[a-z0-9][a-z0-9_.-]*$")
	if pack.pack_version.strip_edges().is_empty():
		errors.append("pack_version is required")
	if pack.content_api_version != ContentPackDef.CURRENT_API_VERSION:
		errors.append(
			"content_api_version %d is incompatible with %d"
			% [pack.content_api_version, ContentPackDef.CURRENT_API_VERSION]
		)


func _validate_definitions(pack: ContentPackDef, errors: PackedStringArray) -> void:
	var seen: Dictionary = {}
	var collections := [
		pack.characters,
		pack.weapons,
		pack.passives,
		pack.upgrades,
		pack.enemies,
		pack.waves,
	]
	for definitions: Array in collections:
		for definition: Variant in definitions:
			if not definition is ContentDef:
				errors.append("content definition is null or has an unsupported type")
				continue
			var stable_id: StringName = definition.get_stable_id(pack.pack_id)
			if stable_id.is_empty():
				errors.append("content_id is required")
				continue
			var stable_text := String(stable_id)
			if not stable_text.begins_with("%s:" % pack.pack_id):
				errors.append("content_id %s belongs to another pack" % stable_text)
			if seen.has(stable_id):
				errors.append("duplicate content_id %s" % stable_text)
			else:
				seen[stable_id] = true


func _validate_references(pack: ContentPackDef, errors: PackedStringArray) -> void:
	var enemy_ids: Dictionary = {}
	for enemy: EnemyDef in pack.enemies:
		if enemy == null:
			continue
		var local_id := String(enemy.content_id)
		if enemy.scene == null:
			errors.append("%s requires a scene" % local_id)
		enemy_ids[enemy.content_id] = true
		enemy_ids[enemy.get_stable_id(pack.pack_id)] = true

	for wave: WaveDef in pack.waves:
		if wave == null:
			continue
		for spawn: WaveSpawnDef in wave.spawns:
			if spawn == null:
				errors.append("%s contains a null spawn definition" % wave.content_id)
				continue
			if not enemy_ids.has(spawn.enemy_id):
				errors.append(
					"%s references unknown enemy %s" % [wave.content_id, spawn.enemy_id]
				)


func _validate_source_directory(path: String, errors: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		errors.append("content source directory does not exist: %s" % path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_validate_source_directory(entry_path, errors)
			elif FORBIDDEN_EXTENSIONS.has(entry.get_extension().to_lower()):
				errors.append("forbidden content file: %s" % entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
