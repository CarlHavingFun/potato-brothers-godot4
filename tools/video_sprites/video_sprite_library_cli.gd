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


static func parse_character_arguments(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"character_config": "",
		"operation": "",
		"replace_runtime": false,
		"errors": PackedStringArray(),
		"exit_code": 0,
	}
	var index := 0
	while index < arguments.size():
		var argument := arguments[index]
		match argument:
			"--character-config":
				if index + 1 >= arguments.size() or arguments[index + 1].begins_with("--"):
					_append_error(result, "--character-config requires a path")
				else:
					index += 1
					result["character_config"] = arguments[index]
			"--install-character":
				_set_operation(result, "install")
			"--publish-character":
				_set_operation(result, "publish")
			"--character-status":
				_set_operation(result, "status")
			"--replace-runtime":
				result["replace_runtime"] = true
			_:
				_append_error(result, "unknown character argument: %s" % argument)
		index += 1
	if str(result["character_config"]).is_empty():
		_append_error(result, "--character-config is required")
	if str(result["operation"]).is_empty():
		_append_error(result, "one character operation is required")
	if not (result["errors"] as PackedStringArray).is_empty():
		result["exit_code"] = 2
	return result


func _initialize() -> void:
	var raw_arguments := OS.get_cmdline_user_args()
	if "--character-config" in raw_arguments:
		_run_character(raw_arguments)
		return
	var arguments := parse_arguments(raw_arguments)
	if int(arguments["exit_code"]) != 0:
		_emit(arguments)
		quit(2)
		return
	var manifest_path := str(arguments["manifest"])
	if bool(arguments["validate_only"]):
		var parsed := Importer.parse_manifest_file(manifest_path)
		var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
		if errors.is_empty():
			errors = Importer.validate_manifest_assets(parsed["manifest"] as Dictionary)
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


func _run_character(raw_arguments: PackedStringArray) -> void:
	var arguments := parse_character_arguments(raw_arguments)
	if int(arguments["exit_code"]) != 0:
		_emit(arguments)
		quit(2)
		return
	var parsed := Importer.parse_character_config_file(str(arguments["character_config"]))
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		_emit({"errors": errors})
		quit(3)
		return
	var config := parsed["config"] as Dictionary
	var result: Dictionary
	match str(arguments["operation"]):
		"install":
			result = Importer.install_character_library(
				config,
				str(config["clip_root"]),
				str(config["authoring_path"]),
				bool(arguments["replace_runtime"])
			)
		"publish":
			var authoring := ResourceLoader.load(
				str(config["authoring_path"]), "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
			) as SpriteFrames
			result = Importer.publish_character_runtime(
				authoring,
				str(config["character_id"]),
				str(config["runtime_root"]),
				Callable(self, "_load_page_texture")
			)
		_:
			var authoring := ResourceLoader.load(
				str(config["authoring_path"]), "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
			) as SpriteFrames
			result = Importer.character_status(config, authoring)
	errors = result.get("errors", PackedStringArray()) as PackedStringArray
	_emit(result)
	quit(0 if errors.is_empty() else 3)


func _load_page_texture(path: String) -> Texture2D:
	var texture := ResourceLoader.load(
		path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	if texture != null:
		return texture
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if not image.is_empty() else null


static func _append_error(result: Dictionary, message: String) -> void:
	var errors := result["errors"] as PackedStringArray
	errors.append(message)
	result["errors"] = errors


static func _set_operation(result: Dictionary, operation: String) -> void:
	if not str(result["operation"]).is_empty():
		_append_error(result, "character operations are mutually exclusive")
	else:
		result["operation"] = operation


func _emit(value: Dictionary) -> void:
	print(JSON.stringify(value))
