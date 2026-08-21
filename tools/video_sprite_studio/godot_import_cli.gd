extends SceneTree


const Importer = preload("godot_sprite_frames_importer.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var request_path := ""
	for index in arguments.size():
		if arguments[index] == "--request" and index + 1 < arguments.size():
			request_path = arguments[index + 1]
			break
	if request_path.is_empty() or not FileAccess.file_exists(request_path):
		_fail("--request must name an existing JSON file", 2)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(request_path)) != OK or not parser.data is Dictionary:
		_fail("request JSON is invalid", 2)
		return
	var request := parser.data as Dictionary
	var manifest_path := str(request.get("manifest_resource", ""))
	var manifest_parser := JSON.new()
	if not FileAccess.file_exists(manifest_path) or manifest_parser.parse(FileAccess.get_file_as_string(manifest_path)) != OK:
		_fail("manifest could not be loaded", 3)
		return
	var texture := ResourceLoader.load(
		str(request.get("atlas_resource", "")), "Texture2D", ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	if texture == null:
		_fail("atlas could not be imported as Texture2D", 3)
		return
	var target_path := str(request.get("target_resource", ""))
	var existing: SpriteFrames = null
	if FileAccess.file_exists(target_path):
		existing = ResourceLoader.load(
			target_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
		) as SpriteFrames
		if existing == null:
			_fail("target resource is not SpriteFrames", 3)
			return
	var animation := StringName(str(request.get("animation", "")))
	var result: Dictionary = Importer.merge_animation(
		existing, manifest_parser.data as Dictionary, animation, texture
	)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		_fail("; ".join(errors), 3)
		return
	var temp_path := str(request.get("temp_resource", ""))
	var save_error := ResourceSaver.save(result["sprite_frames"] as SpriteFrames, temp_path)
	if save_error != OK:
		_fail("could not save temporary SpriteFrames: %s" % error_string(save_error), 3)
		return
	var readback := ResourceLoader.load(
		temp_path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
	) as SpriteFrames
	if readback == null or not readback.has_animation(animation):
		_fail("temporary SpriteFrames readback failed", 3)
		return
	var expected := int((((manifest_parser.data as Dictionary)["animation"] as Dictionary)["rows"] as Dictionary)[String(animation)]["frames"])
	if readback.get_frame_count(animation) != expected:
		_fail("temporary SpriteFrames frame count mismatch", 3)
		return
	print(JSON.stringify({"ok": true, "animation": String(animation), "frames": expected, "temp": temp_path}))
	quit(0)


func _fail(message: String, code: int) -> void:
	printerr(JSON.stringify({"ok": false, "error": message}))
	quit(code)
