@tool
extends EditorPlugin


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const Commands = preload("res://mcp_commands/video_sprite_commands.gd")
const CONFIG_PATH := "res://tools/video_sprites/niko_character_sources.json"
const IMPORT_LABEL := "角色精灵/导入 Niko 全部视频"
const PUBLISH_LABEL := "角色精灵/发布当前角色动画"
const STATUS_LABEL := "角色精灵/显示当前角色状态"


func _enter_tree() -> void:
	add_tool_menu_item(IMPORT_LABEL, _import_all)
	add_tool_menu_item(PUBLISH_LABEL, _publish_current)
	add_tool_menu_item(STATUS_LABEL, _show_status)


func _exit_tree() -> void:
	remove_tool_menu_item(IMPORT_LABEL)
	remove_tool_menu_item(PUBLISH_LABEL)
	remove_tool_menu_item(STATUS_LABEL)


func _import_all() -> void:
	var commands := Commands.new()
	var result := commands.get_commands()["character_sprite.import_all"].call({
		"character_id": "niko",
		"config_path": CONFIG_PATH,
		"pipeline_root": "E:/01_gobro/pixelmotion-2d-niko",
	}) as Dictionary
	_print_result("导入任务", result)
	commands.free()


func _publish_current() -> void:
	var context := _load_context()
	if not (context.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_print_result("发布失败", context)
		return
	var config := context["config"] as Dictionary
	var authoring := _edited_sprite_frames()
	if authoring == null:
		authoring = ResourceLoader.load(
			str(config["authoring_path"]), "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
		) as SpriteFrames
	if authoring == null:
		_print_result("发布失败", {"errors": ["请先导入并打开 Niko 动作母资源"]})
		return
	var result := Importer.publish_character_runtime(
		authoring,
		str(config["character_id"]),
		str(config["runtime_root"]),
		Callable(self, "_load_published_texture")
	)
	_print_result("发布结果", result)


func _show_status() -> void:
	var commands := Commands.new()
	var result := commands.get_commands()["character_sprite.status"].call({
		"character_id": "niko", "config_path": CONFIG_PATH,
	}) as Dictionary
	_print_result("角色状态", result)
	commands.free()


func _load_context() -> Dictionary:
	return Importer.parse_character_config_file(CONFIG_PATH)


func _edited_sprite_frames() -> SpriteFrames:
	var inspector := get_editor_interface().get_inspector()
	if inspector == null:
		return null
	var edited := inspector.get_edited_object()
	if edited is SpriteFrames and str((edited as SpriteFrames).get_meta("character_id", "")) == "niko":
		return edited as SpriteFrames
	return null


func _load_published_texture(path: String) -> Texture2D:
	var filesystem := get_editor_interface().get_resource_filesystem()
	filesystem.update_file(path)
	filesystem.reimport_files(PackedStringArray([path]))
	return ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D


func _print_result(label: String, result: Dictionary) -> void:
	var message := "%s: %s" % [label, JSON.stringify(result)]
	var errors: Variant = result.get("errors", [])
	if errors is Array and not (errors as Array).is_empty():
		push_error(message)
	elif errors is PackedStringArray and not (errors as PackedStringArray).is_empty():
		push_error(message)
	else:
		print(message)
