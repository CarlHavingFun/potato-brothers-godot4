extends SceneTree


const Importer = preload("res://tools/sprites/sprite_gen_state_importer.gd")


func _init() -> void:
	var parsed := _parse_arguments(OS.get_cmdline_user_args())
	var errors := parsed.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		for message in errors:
			push_error(message)
		quit(2)
		return
	var result := Importer.import_file(
		str(parsed["manifest"]),
		StringName(str(parsed["state"])),
		str(parsed["output"])
	)
	errors = result.get("errors", PackedStringArray()) as PackedStringArray
	if not errors.is_empty():
		for message in errors:
			push_error(message)
		quit(3)
		return
	print(
		"sprite_gen_state_imported=%s state=%s frames=%d" % [
			result["output"], result["state"], result["frames"]
		]
	)
	quit()


func _parse_arguments(arguments: PackedStringArray) -> Dictionary:
	var values := {"state": "walk_down"}
	var errors := PackedStringArray()
	var index := 0
	while index < arguments.size():
		var argument := arguments[index]
		if argument in ["--manifest", "--state", "--output"]:
			if index + 1 >= arguments.size():
				errors.append("missing value for %s" % argument)
				break
			values[argument.trim_prefix("--")] = arguments[index + 1]
			index += 2
			continue
		errors.append("unknown argument: %s" % argument)
		index += 1
	for required in ["manifest", "output"]:
		if str(values.get(required, "")).is_empty():
			errors.append("missing --%s" % required)
	values["errors"] = errors
	return values
