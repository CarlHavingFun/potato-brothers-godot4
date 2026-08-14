extends Node


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	var manifest_path := _argument(arguments, "--manifest", "res://content_packs/default/pack.tres")
	var source_root := _argument(arguments, "--source-root", manifest_path.get_base_dir())
	var resource := ResourceLoader.load(manifest_path, "ContentPackDef", ResourceLoader.CACHE_MODE_REPLACE)
	if not resource is ContentPackDef:
		printerr("Content manifest is not a ContentPackDef: %s" % manifest_path)
		get_tree().quit(ERR_INVALID_DATA)
		return
	var errors := ContentValidator.new().validate_pack(resource, source_root)
	if not errors.is_empty():
		printerr("Content validation failed:\n%s" % "\n".join(errors))
		get_tree().quit(ERR_INVALID_DATA)
		return
	print("Content validation passed: %s (%s)" % [resource.pack_id, resource.pack_version])
	get_tree().quit(OK)


func _argument(arguments: PackedStringArray, name: String, fallback: String) -> String:
	var index := arguments.find(name)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return fallback
