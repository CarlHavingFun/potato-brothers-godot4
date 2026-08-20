extends SceneTree


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")


static func parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"manifest": "",
		"replace_selection": false,
		"validate_only": false,
		"errors": PackedStringArray(),
		"exit_code": 0,
	}
	var index := 0
	while index < arguments.size():
		var argument := arguments[index]
		match argument:
			"--manifest":
				if index + 1 >= arguments.size() or arguments[index + 1].begins_with("--"):
					_append_error(result, "--manifest requires a path")
				else:
					index += 1
					result["manifest"] = arguments[index]
			"--replace-selection":
				result["replace_selection"] = true
			"--validate-only":
				result["validate_only"] = true
			_:
				_append_error(result, "unknown argument: %s" % argument)
		index += 1
	if str(result["manifest"]).is_empty():
		_append_error(result, "--manifest is required")
	if not (result["errors"] as PackedStringArray).is_empty():
		result["exit_code"] = 2
	return result


func _initialize() -> void:
	var arguments := parse_arguments(OS.get_cmdline_user_args())
	if int(arguments["exit_code"]) != 0:
		_emit(arguments)
		quit(2)
		return
	var manifest_path := str(arguments["manifest"])
	if bool(arguments["validate_only"]):
		var parsed := Importer.parse_manifest_file(manifest_path)
		var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
		_emit({"manifest": manifest_path, "valid": errors.is_empty(), "errors": errors})
		quit(0 if errors.is_empty() else 3)
		return
	var result := Importer.install_clip(manifest_path, bool(arguments["replace_selection"]))
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if errors.is_empty():
		var preview := Importer.write_preview_scene(manifest_path)
		errors = preview.get("errors", PackedStringArray()) as PackedStringArray
		if not errors.is_empty():
			result["errors"] = errors
		else:
			result["preview_path"] = preview["preview_path"]
	_emit(result)
	quit(0 if errors.is_empty() else 3)


static func _append_error(result: Dictionary, message: String) -> void:
	var errors := result["errors"] as PackedStringArray
	errors.append(message)
	result["errors"] = errors


func _emit(value: Dictionary) -> void:
	print(JSON.stringify(value))
