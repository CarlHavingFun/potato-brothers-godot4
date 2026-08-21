@tool
extends EditorPlugin


const Importer = preload("res://tools/video_sprites/video_sprite_manifest_importer.gd")
const Commands = preload("res://mcp_commands/video_sprite_commands.gd")
const ImportJobTracker = preload("res://addons/character_sprite_authoring/import_job_tracker.gd")
const CurationDock = preload("res://addons/character_sprite_authoring/video_sprite_curation_dock.gd")
const DockLifecycle = preload("res://addons/character_sprite_authoring/dock_lifecycle.gd")
const CONFIG_PATH := "res://tools/video_sprites/niko_character_sources.json"
const IMPORT_LABEL := "角色精灵/导入 Niko 全部视频"
const PUBLISH_LABEL := "角色精灵/发布当前角色动画"
const STATUS_LABEL := "角色精灵/显示当前角色状态"
const DOCK_LABEL := "角色精灵/打开视频挑帧 Dock"
const POLL_INTERVAL_SECONDS := 0.5

var _commands: Commands
var _job_tracker: CharacterSpriteImportJobTracker
var _dock: CharacterSpriteAuthoringDock
var _dock_lifecycle: CharacterSpriteDockLifecycle
var _poll_elapsed := 0.0


func _enter_tree() -> void:
	_commands = Commands.new()
	_job_tracker = ImportJobTracker.new()
	_job_tracker.commands = _commands
	_dock = CurationDock.new()
	_dock.controller.publish_callback = Callable(self, "_publish_current")
	_dock.controller.open_resource_callback = Callable(self, "_open_promoted_resource")
	_dock.controller.refresh_callback = Callable(self, "_refresh_dock")
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	_dock_lifecycle = DockLifecycle.new()
	var editor_window := get_editor_interface().get_base_control().get_window()
	_dock_lifecycle.connect_files_dropped(editor_window, Callable(self, "_on_files_dropped"))
	set_process(false)
	add_tool_menu_item(IMPORT_LABEL, _import_all)
	add_tool_menu_item(PUBLISH_LABEL, _publish_current)
	add_tool_menu_item(STATUS_LABEL, _show_status)
	add_tool_menu_item(DOCK_LABEL, _focus_dock)


func _exit_tree() -> void:
	set_process(false)
	remove_tool_menu_item(IMPORT_LABEL)
	remove_tool_menu_item(PUBLISH_LABEL)
	remove_tool_menu_item(STATUS_LABEL)
	remove_tool_menu_item(DOCK_LABEL)
	if _dock_lifecycle != null:
		_dock_lifecycle.disconnect_files_dropped()
	_dock_lifecycle = null
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null
	_job_tracker = null
	if is_instance_valid(_commands):
		_commands.free()
	_commands = null


func _process(delta: float) -> void:
	if _job_tracker == null or _job_tracker.active_job_id.is_empty():
		set_process(false)
		return
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL_SECONDS:
		return
	_poll_elapsed = 0.0
	poll_import_job()


func _import_all() -> void:
	var context := _load_context()
	if not (context.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_print_result("导入失败", context)
		return
	var config := context["config"] as Dictionary
	var source_directory := Commands.resolve_character_source_directory(config)
	var pipeline_root := Commands.resolve_pipeline_root({})
	var result := _commands.get_commands()["character_sprite.import_all"].call({
		"character_id": "niko",
		"config_path": CONFIG_PATH,
		"source_directory": source_directory,
		"pipeline_root": pipeline_root,
	}) as Dictionary
	_print_result("导入任务", result)
	if _job_tracker.track_import_result(result):
		_poll_elapsed = 0.0
		set_process(true)


func poll_import_job() -> Dictionary:
	if _job_tracker == null or _job_tracker.active_job_id.is_empty():
		set_process(false)
		return {"state": "idle", "errors": PackedStringArray()}
	var result := _job_tracker.poll_import_job()
	if not _job_tracker.active_job_id.is_empty():
		return result
	set_process(false)
	_print_result("导入完成", result)
	return result


func _publish_current() -> Dictionary:
	var context := _load_context()
	if not (context.get("errors", PackedStringArray()) as PackedStringArray).is_empty():
		_print_result("发布失败", context)
		return context
	var config := context["config"] as Dictionary
	var authoring := _edited_sprite_frames()
	if authoring == null:
		authoring = ResourceLoader.load(
			str(config["authoring_path"]), "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE
		) as SpriteFrames
	if authoring == null:
		var missing := {"errors": PackedStringArray(["请先导入并打开 Niko 动作母资源"])}
		_print_result("发布失败", missing)
		return missing
	var result := Importer.publish_character_runtime(
		authoring,
		str(config["character_id"]),
		str(config["runtime_root"]),
		Callable(self, "_load_published_texture")
	)
	_print_result("发布结果", result)
	return result


func _focus_dock() -> void:
	if is_instance_valid(_dock):
		_dock.focus_dock_tab()


func _on_files_dropped(files: PackedStringArray) -> void:
	if is_instance_valid(_dock):
		_dock.handle_files_dropped(files)


func _open_promoted_resource(path: String) -> void:
	var filesystem := get_editor_interface().get_resource_filesystem()
	filesystem.scan()
	filesystem.update_file(path)
	var resource := ResourceLoader.load(path, "SpriteFrames", ResourceLoader.CACHE_MODE_REPLACE)
	if resource != null:
		get_editor_interface().edit_resource(resource)


func _refresh_dock() -> void:
	if is_instance_valid(_dock):
		_dock.refresh_config()


func _show_status() -> void:
	var result := _commands.get_commands()["character_sprite.status"].call({
		"character_id": "niko", "config_path": CONFIG_PATH,
	}) as Dictionary
	_print_result("角色状态", result)


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
