class_name ContentValidator
extends RefCounted


const FORBIDDEN_EXTENSIONS := {
	"cs": true,
	"exe": true,
	"gd": true,
	"gdc": true,
	"dll": true,
	"gdextension": true,
	"dylib": true,
	"so": true,
}

const PROTECTED_ROOTS := [
	"res://addons/",
	"res://autoloads/",
	"res://core/",
	"res://tests/",
	"res://tools/",
]


func validate_pack(pack: ContentPackDef, source_root := "") -> PackedStringArray:
	var errors := PackedStringArray()
	if pack == null:
		errors.append("pack is required")
		return errors

	_validate_metadata(pack, errors)
	_validate_definitions(pack, errors)
	_validate_references(pack, errors)
	_validate_declared_paths(pack, errors)
	if not source_root.is_empty():
		var normalized_root := source_root.replace("\\", "/").trim_suffix("/")
		var files := PackedStringArray()
		_collect_source_files(normalized_root, files, errors)
		errors.append_array(validate_virtual_paths(files, normalized_root))
	return errors


func validate_virtual_paths(paths: PackedStringArray, allowed_root: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_root := allowed_root.replace("\\", "/").trim_suffix("/")
	for raw_path: String in paths:
		var path := raw_path.replace("\\", "/")
		if _is_os_absolute_path(path):
			errors.append("absolute path is forbidden: %s" % raw_path)
			continue
		if _contains_traversal(path):
			errors.append("path traversal is forbidden: %s" % raw_path)
			continue
		if _is_protected_path(path):
			errors.append("core path override is forbidden: %s" % raw_path)
			continue
		if not normalized_root.is_empty() and not path.begins_with(normalized_root + "/"):
			errors.append("content path is outside allowed root %s: %s" % [normalized_root, raw_path])
			continue
		if FORBIDDEN_EXTENSIONS.has(path.get_extension().to_lower()):
			errors.append("forbidden content file: %s" % raw_path)
	return errors


func validate_release_matrix(pack: ContentPackDef) -> PackedStringArray:
	var errors := PackedStringArray()
	if pack == null:
		errors.append("release pack is required")
		return errors
	var expected_counts := {
		"characters": 12,
		"weapons": 24,
		"passives": 60,
		"enemies": 22,
		"waves": 20,
	}
	var actual_counts := {
		"characters": pack.characters.size(),
		"weapons": pack.weapons.size(),
		"passives": pack.passives.size(),
		"enemies": pack.enemies.size(),
		"waves": pack.waves.size(),
	}
	for key: String in expected_counts:
		if actual_counts[key] != expected_counts[key]:
			errors.append("release %s requires %d entries, got %d" % [
				key, expected_counts[key], actual_counts[key]
			])
	for definition: ContentDef in pack.characters + pack.weapons + pack.passives + pack.enemies:
		if definition != null and definition.tags.is_empty():
			errors.append("%s requires at least one gameplay tag" % definition.content_id)
	for character: CharacterDef in pack.characters:
		if character != null and character.stats == null:
			errors.append("%s requires stats" % character.content_id)
		elif character != null and character.rules == null:
			errors.append("%s requires CharacterRuleDef" % character.content_id)
	for weapon: WeaponDef in pack.weapons:
		if weapon == null:
			continue
		if weapon.attack_pattern == null:
			errors.append("%s requires AttackPatternDef" % weapon.content_id)
		for tier_index in weapon.tiers.size():
			var tier := weapon.tiers[tier_index]
			if tier == null or tier.scene == null:
				errors.append("%s tier %d requires a mechanical scene" % [weapon.content_id, tier_index + 1])
			elif tier_index < weapon.tiers.size() - 1 and tier.upgrade_to != weapon.tiers[tier_index + 1]:
				errors.append("%s tier %d has a broken upgrade chain" % [weapon.content_id, tier_index + 1])
	for passive: PassiveItemDef in pack.passives:
		if passive != null and passive.item == null:
			errors.append("%s requires an item definition" % passive.content_id)
	for enemy: EnemyDef in pack.enemies:
		if enemy != null and enemy.behavior == null:
			errors.append("%s requires EnemyBehaviorDef" % enemy.content_id)
	for difficulty: DifficultyDef in pack.difficulties:
		if difficulty != null and difficulty.mutator == null:
			errors.append("difficulty %d requires DifficultyMutatorDef" % difficulty.level)
	var tag_targets := {
		&"normal": 18,
		&"elite": 2,
		&"boss": 2,
	}
	for target_tag: StringName in tag_targets:
		var count := 0
		for enemy: EnemyDef in pack.enemies:
			if enemy != null and target_tag in enemy.tags:
				count += 1
		if count != tag_targets[target_tag]:
			errors.append("enemy tag %s requires %d entries, got %d" % [
				target_tag, tag_targets[target_tag], count
			])
	_validate_release_translation_names(pack, errors)
	return errors


func _validate_release_translation_names(pack: ContentPackDef, errors: PackedStringArray) -> void:
	var translation_sources: Array[String] = []
	for path: String in pack.translation_paths:
		if FileAccess.file_exists(path):
			translation_sources.append(FileAccess.get_file_as_string(path))
	if translation_sources.size() < 2:
		errors.append("release pack requires English and Simplified Chinese translations")
		return
	for definition: ContentDef in pack.characters + pack.weapons + pack.passives + pack.enemies:
		if definition == null or definition.display_name_key.is_empty():
			continue
		var needle := "msgid \"%s\"" % definition.display_name_key
		for source_index in translation_sources.size():
			if not translation_sources[source_index].contains(needle):
				errors.append("missing release translation %s in source %d" % [
					definition.display_name_key, source_index
				])


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
	for character: CharacterDef in pack.characters:
		if character == null:
			continue
		var character_id := String(character.content_id)
		if character.scene == null:
			errors.append("%s requires a scene" % character_id)
		else:
			_validate_scene_contract(character.scene, character_id, errors)
		if character.stats == null:
			errors.append("%s requires stats" % character_id)

	for weapon: WeaponDef in pack.weapons:
		if weapon == null:
			continue
		if weapon.tiers.size() != 4:
			errors.append("%s requires four tiers" % weapon.content_id)
		for tier: ItemWeapon in weapon.tiers:
			if tier == null:
				errors.append("%s contains a null tier" % weapon.content_id)

	for passive: PassiveItemDef in pack.passives:
		if passive != null and passive.item == null:
			errors.append("%s requires an item" % passive.content_id)

	for upgrade: UpgradeDef in pack.upgrades:
		if upgrade != null and upgrade.item == null:
			errors.append("%s requires an item" % upgrade.content_id)

	var enemy_ids: Dictionary = {}
	for enemy: EnemyDef in pack.enemies:
		if enemy == null:
			continue
		var local_id := String(enemy.content_id)
		if enemy.scene == null:
			errors.append("%s requires a scene" % local_id)
		else:
			_validate_scene_contract(enemy.scene, local_id, errors)
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


func _validate_declared_paths(pack: ContentPackDef, errors: PackedStringArray) -> void:
	for path: String in pack.translation_paths:
		if _is_os_absolute_path(path):
			errors.append("absolute path is forbidden: %s" % path)
		elif _contains_traversal(path):
			errors.append("path traversal is forbidden: %s" % path)
		elif _is_protected_path(path):
			errors.append("core path override is forbidden: %s" % path)
		elif not path.begins_with("res://content_packs/"):
			errors.append("translation path must be inside res://content_packs/: %s" % path)
		elif not ResourceLoader.exists(path):
			errors.append("translation path does not exist: %s" % path)


func _validate_scene_contract(scene: PackedScene, content_id: String, errors: PackedStringArray) -> void:
	var instance := scene.instantiate()
	if instance == null:
		errors.append("%s scene cannot be instantiated" % content_id)
		return
	if not instance is CharacterBody2D:
		errors.append("%s scene root must be CharacterBody2D" % content_id)
	_validate_scene_scripts(instance, content_id, errors)
	instance.free()


func _validate_scene_scripts(node: Node, content_id: String, errors: PackedStringArray) -> void:
	var script := node.get_script() as Script
	if script != null:
		var script_path := script.resource_path.replace("\\", "/")
		if script_path.begins_with("res://content_packs/"):
			errors.append("%s scene contains content script %s" % [content_id, script_path])
	for child: Node in node.get_children():
		_validate_scene_scripts(child, content_id, errors)


func _collect_source_files(path: String, files: PackedStringArray, errors: PackedStringArray) -> void:
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
				_collect_source_files(entry_path, files, errors)
			else:
				files.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _is_os_absolute_path(path: String) -> bool:
	if path.begins_with("/") or path.begins_with("//"):
		return true
	return path.length() >= 3 and path[1] == ":" and path[2] == "/"


func _contains_traversal(path: String) -> bool:
	return Array(path.split("/", false)).has("..")


func _is_protected_path(path: String) -> bool:
	for root: String in PROTECTED_ROOTS:
		if path.begins_with(root):
			return true
	return false
