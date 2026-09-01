extends GdUnitTestSuite


const APP_SCENE := preload("res://game/app/app_root.tscn")
const CLIENT_SIZE := Vector2i(960, 540)
const OUTPUT_DIRECTORY := "user://task-zone-native-960-v1"
const SECOND_ZONE_ID := &"gogobro.test:zone/night_training"


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
	var packs := ValidationContentFactory.create_packs(true)
	packs.append(_second_zone_pack())
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(packs)
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
	assert_int(task_option.item_count).is_equal(2)
	var training_index := _item_index(task_option, ValidationContentFactory.ZONE_ID)
	assert_int(training_index).is_greater_equal(0)
	if training_index < 0:
		return
	var second_index := 0 if training_index != 0 else 1
	var second_zone_id := StringName(task_option.get_item_metadata(second_index))
	var second_zone := app.content_snapshot.definition(second_zone_id, &"zone") as GogoZoneDefinition
	assert_object(second_zone).is_not_null()
	if second_zone == null:
		return
	assert_int(second_zone.wave_ids.size()).is_equal(20)
	assert_int(task_option.selected).is_equal(training_index)
	assert_str(task_option.text).is_equal("任务 · 训练场")
	assert_str(task_option.tooltip_text).is_equal("训练场 · 20 波 · 从第 1 波开始")
	assert_str(String(task_option.get_item_metadata(training_index))).is_equal(
		String(ValidationContentFactory.ZONE_ID)
	)
	assert_object(task_option.get_item_icon(training_index)).is_not_null()
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
	var popup := task_option.get_popup()
	var selected_indices: Array[int] = []
	task_option.item_selected.connect(
		func(index: int) -> void: selected_indices.append(index)
	)
	var gamepad_accept_probe := InputEventJoypadButton.new()
	gamepad_accept_probe.device = 0
	gamepad_accept_probe.button_index = JOY_BUTTON_A
	gamepad_accept_probe.pressed = true
	assert_bool(gamepad_accept_probe.is_action_pressed(&"ui_accept", true)).is_true()
	if not gamepad_accept_probe.is_action_pressed(&"ui_accept", true):
		return
	await _push_gamepad_accept(root_window)
	assert_bool(popup.visible).is_true()
	if not popup.visible:
		return
	popup.set_focused_item(second_index)
	await _settle(2)
	assert_int(_capture(root_window, "task-selector-popup-960x540.png")).is_equal(OK)
	assert_str(_capture_sha256("task-selector-popup-960x540.png")).is_not_equal(
		_capture_sha256("task-selector-960x540.png")
	)
	await _push_escape(root_window)
	assert_bool(not is_instance_valid(popup) or not popup.visible).is_true()
	assert_bool(task_option.has_focus()).is_true()
	assert_array(selected_indices).is_empty()
	assert_int(task_option.selected).is_equal(training_index)
	popup = task_option.get_popup()
	await _push_gamepad_accept(root_window)
	assert_bool(popup.visible).is_true()
	if not popup.visible:
		return
	popup.set_focused_item(second_index)
	await _push_gamepad_accept(root_window)
	await _settle(3)
	assert_bool(not is_instance_valid(popup) or not popup.visible).is_true()
	assert_array(selected_indices).contains_exactly([second_index])
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(
		String(second_zone_id)
	)
	assert_int(task_option.selected).is_equal(second_index)
	assert_str(task_option.text).is_equal("任务 · %s" % second_zone.display_name)
	assert_bool(roster.visible).is_true()
	assert_bool(task_option.has_focus()).is_true()
	assert_object(app.current_session).is_null()
	print(
		"TASK_ZONE_NATIVE_960_OK captures=3 zone=%s waves=20 start=1 items=2 inline=true popup_visible=true keyboard_escape=true gamepad_open=true gamepad_accept=true selection_signal=1"
		% String(second_zone_id)
	)


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


func _capture_sha256(filename: String) -> String:
	return FileAccess.get_sha256(
		ProjectSettings.globalize_path(OUTPUT_DIRECTORY).path_join(filename)
	)


func _settle(frame_count: int) -> void:
	for frame_index in frame_count:
		await get_tree().process_frame


func _push_escape(root_window: Window) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root_window.push_input(event)
	await _settle(2)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root_window.push_input(event)
	await _settle(2)


func _push_gamepad_accept(root_window: Window) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	Input.parse_input_event(event)
	await _settle(2)
	event = event.duplicate() as InputEventJoypadButton
	event.pressed = false
	Input.parse_input_event(event)
	await _settle(2)


func _second_zone_pack() -> GogoContentPackDefinition:
	var source := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
	var training := source.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	var zone := GogoZoneDefinition.new()
	zone.content_id = SECOND_ZONE_ID
	zone.display_name = "夜间训练场"
	zone.icon_asset_id = &"zone_thumbnail"
	for wave_id in training.wave_ids:
		zone.wave_ids.append(wave_id)
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"gogobro.test.task_zone_native"
	pack.pack_kind = &"core"
	pack.definitions.append(zone)
	return pack


func _item_index(option: OptionButton, content_id: StringName) -> int:
	for index in option.item_count:
		if StringName(option.get_item_metadata(index)) == content_id:
			return index
	return -1
