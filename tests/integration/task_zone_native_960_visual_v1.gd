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
	var task_button := screen.get_node("TaskButton") as Button
	assert_str(task_button.text).is_equal("任务 · 训练场")
	assert_str(task_button.tooltip_text).contains("20 波")
	assert_int(_capture(root_window, "character-roster-960x540.png")).is_equal(OK)
	task_button.pressed.emit()
	await _settle(4)
	var zone_stage := screen.get_node("ZoneStage") as Control
	var option := zone_stage.get_node("ZoneGrid/ZoneOption0") as Button
	assert_bool(zone_stage.visible).is_true()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_str(String(option.get_meta(&"content_id", &""))).is_equal(String(ValidationContentFactory.ZONE_ID))
	assert_object((option.get_node("Thumbnail") as TextureRect).texture).is_not_null()
	assert_object((zone_stage.get_node("SelectedZoneDetail/Thumbnail") as TextureRect).texture).is_not_null()
	assert_int(_capture(root_window, "task-selector-960x540.png")).is_equal(OK)
	option.pressed.emit()
	await _settle(3)
	assert_bool(zone_stage.visible).is_false()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(app.current_session).is_null()
	print("TASK_ZONE_NATIVE_960_OK captures=2 zone=training_ground waves=20 start=1")


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
