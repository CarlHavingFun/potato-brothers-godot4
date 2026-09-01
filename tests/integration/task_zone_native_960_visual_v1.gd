extends GdUnitTestSuite


const APP_SCENE := preload("res://game/app/app_root.tscn")
const CLIENT_SIZE := Vector2i(960, 540)
const OUTPUT_DIRECTORY := "user://task-zone-native-960-v1"


func test_real_task_selector_and_character_roster_render_at_native_960() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := get_tree().root
	root_window.size = CLIENT_SIZE
	root_window.show()
	await _settle(3)
	var app := auto_free(APP_SCENE.instantiate()) as AppKernel
	root_window.add_child(app)
	for frame_index in 180:
		await get_tree().process_frame
		if app.boot_result != null:
			break
	assert_object(app.boot_result).is_not_null()
	if app.boot_result == null:
		return
	assert_bool(app.boot_result.is_ok()).is_true()
	if not app.boot_result.is_ok():
		return
	root_window.size = CLIENT_SIZE
	DisplayServer.window_set_size(CLIENT_SIZE, root_window.get_window_id())
	await _settle(4)
	app.begin_selection()
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle(4)
	var host := app.get_node("SceneHost") as Node
	var screen := host.get_child(0) as Control
	var task_option := screen.get_node("TaskOptionButton") as OptionButton
	var roster := screen.get_node("RosterStrip") as GridContainer
	assert_object(screen.get_node_or_null("TaskButton")).is_null()
	assert_object(screen.get_node_or_null("ZoneStage")).is_null()
	assert_bool(roster.visible).is_true()
	assert_int(roster.get_child_count()).is_equal(24)
	assert_int(task_option.item_count).is_equal(1)
	assert_int(task_option.selected).is_equal(0)
	assert_str(task_option.text).is_equal("任务 · 训练场")
	assert_str(task_option.tooltip_text).is_equal("训练场 · 20 波 · 从第 1 波开始")
	assert_str(String(task_option.get_item_metadata(0))).is_equal(
		String(ValidationContentFactory.ZONE_ID)
	)
	assert_object(task_option.get_item_icon(0)).is_not_null()
	var zone := app.content_snapshot.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	assert_object(zone).is_not_null()
	if zone != null:
		assert_str(String(zone.icon_asset_id)).is_equal("zone_thumbnail")
	assert_int(screen.find_children("UnavailableZoneSlot*", "Button", true, false).size()).is_equal(0)
	assert_int(_capture(root_window, "character-roster-960x540.png")).is_equal(OK)
	task_option.grab_focus()
	await _settle(4)
	assert_bool(task_option.has_focus()).is_true()
	assert_int(_capture(root_window, "task-selector-960x540.png")).is_equal(OK)
	task_option.item_selected.emit(0)
	await _settle(3)
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(
		String(ValidationContentFactory.ZONE_ID)
	)
	assert_bool(roster.visible).is_true()
	assert_bool(task_option.has_focus()).is_true()
	assert_object(app.current_session).is_null()
	print("TASK_ZONE_NATIVE_960_OK captures=2 zone=training_ground waves=20 start=1 items=1 inline=true")


func _capture(root_window: Window, filename: String) -> Error:
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if mkdir_error not in [OK, ERR_ALREADY_EXISTS]:
		return mkdir_error
	var image := root_window.get_texture().get_image()
	if image == null or image.get_size() != CLIENT_SIZE:
		return ERR_INVALID_DATA
	var path := absolute_directory.path_join(filename)
	var error := image.save_png(path)
	if error == OK:
		print("TASK_ZONE_NATIVE_960_CAPTURE path=%s size=%s" % [path, image.get_size()])
	return error


func _settle(frame_count: int) -> void:
	for frame_index in frame_count:
		await get_tree().process_frame
