extends Node


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	var source_root := _argument(arguments, "--source-root", "res://content_packs/default")
	var manifest_path := _argument(arguments, "--manifest", source_root.path_join("pack.tres"))
	var output_path := _argument(arguments, "--output", "res://builds/content/default_content.pck")
	var contents_path := _argument(
		arguments,
		"--contents",
		output_path.get_basename() + ".contents.json"
	)
	var result := _build(source_root, manifest_path, output_path, contents_path)
	get_tree().quit(result)


func _build(source_root: String, manifest_path: String, output_path: String, contents_path: String) -> int:
	var resource := ResourceLoader.load(manifest_path, "ContentPackDef", ResourceLoader.CACHE_MODE_REPLACE)
	if not resource is ContentPackDef:
		printerr("Content manifest is not a ContentPackDef: %s" % manifest_path)
		return ERR_INVALID_DATA
	var validator := ContentValidator.new()
	var errors := validator.validate_pack(resource, source_root)
	if not errors.is_empty():
		printerr("Content validation failed:\n%s" % "\n".join(errors))
		return ERR_INVALID_DATA

	var source_files := PackedStringArray()
	_collect_files(source_root.trim_suffix("/"), source_files)
	var presentation_root := source_root.trim_suffix("/").path_join("assets") + "/"
	var gameplay_files := PackedStringArray()
	for virtual_path: String in source_files:
		if not virtual_path.begins_with(presentation_root):
			gameplay_files.append(virtual_path)
	source_files = gameplay_files
	var path_errors := validator.validate_virtual_paths(source_files, source_root.trim_suffix("/"))
	if not path_errors.is_empty():
		printerr("Content path validation failed:\n%s" % "\n".join(path_errors))
		return ERR_INVALID_DATA

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var packer := PCKPacker.new()
	var result := packer.pck_start(ProjectSettings.globalize_path(output_path))
	if result != OK:
		printerr("Could not start content PCK: %s" % error_string(result))
		return result

	var packed_files := PackedStringArray()
	for virtual_path: String in source_files:
		if virtual_path.ends_with(".uid"):
			continue
		result = _add_file(packer, virtual_path, virtual_path, packed_files)
		if result != OK:
			return result
		if virtual_path.ends_with(".import"):
			result = _add_imported_dependencies(packer, virtual_path, packed_files)
			if result != OK:
				return result

	result = packer.flush()
	if result != OK:
		printerr("Could not finalize content PCK: %s" % error_string(result))
		return result
	packed_files.sort()
	var manifest := {
		"pack_id": String(resource.pack_id),
		"pack_version": resource.pack_version,
		"content_api_version": resource.content_api_version,
		"replace_files": false,
		"files": Array(packed_files),
	}
	result = _write_json(contents_path, manifest)
	if result != OK:
		return result
	print("Built restricted content PCK: %s (%d files)" % [output_path, packed_files.size()])
	return OK


func _add_file(packer: PCKPacker, virtual_path: String, source_path: String, packed_files: PackedStringArray) -> int:
	if packed_files.has(virtual_path):
		return OK
	var absolute_source := ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(absolute_source):
		printerr("Content dependency does not exist: %s" % source_path)
		return ERR_FILE_NOT_FOUND
	var result := packer.add_file(virtual_path, absolute_source)
	if result != OK:
		printerr("Could not add %s: %s" % [virtual_path, error_string(result)])
		return result
	packed_files.append(virtual_path)
	return OK


func _add_imported_dependencies(packer: PCKPacker, import_path: String, packed_files: PackedStringArray) -> int:
	var config := ConfigFile.new()
	var result := config.load(import_path)
	if result != OK:
		printerr("Could not read import metadata %s: %s" % [import_path, error_string(result)])
		return result
	var dependencies: Array = config.get_value("deps", "dest_files", [])
	var remap_path: String = config.get_value("remap", "path", "")
	if not remap_path.is_empty() and not dependencies.has(remap_path):
		dependencies.append(remap_path)
	for dependency: String in dependencies:
		if not dependency.begins_with("res://.godot/imported/"):
			printerr("Imported dependency is outside the import cache: %s" % dependency)
			return ERR_INVALID_DATA
		result = _add_file(packer, dependency, dependency, packed_files)
		if result != OK:
			return result
	return OK


func _collect_files(path: String, files: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_collect_files(entry_path, files)
			else:
				files.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()


func _write_json(path: String, payload: Dictionary) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write content manifest: %s" % path)
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t") + "\n")
	return OK


func _argument(arguments: PackedStringArray, name: String, fallback: String) -> String:
	var index := arguments.find(name)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return fallback
