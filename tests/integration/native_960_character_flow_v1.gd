extends GdUnitTestSuite


const APP_SCENE := preload("res://game/app/app_root.tscn")
const CASE_NAME := "test_native_960_character_same_page_flow_waits_for_root_observation_ack"
const ARTIFACT_DIRECTORY := "native960-character-flow"
const CLIENT_SIZE := Vector2i(960, 540)
const LOGICAL_SIZE := Vector2i(1280, 720)
const ROOT_TEXTURE_SIZE := Vector2i(720, 405)
const EXPECTED_SCALE := 0.75
const SCALE_TOLERANCE := 0.01
const STAGE_TIMEOUT_MSEC := 300000


func test_native_960_character_same_page_flow_waits_for_root_observation_ack(
	_timeout := 1300000
) -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := get_tree().root
	if not _require(get_window() == root_window, "suite is hosted by the real root Window"):
		return
	root_window.size = CLIENT_SIZE
	root_window.show()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var app := auto_free(APP_SCENE.instantiate()) as AppKernel
	root_window.add_child(app)
	for frame_index in 180:
		await get_tree().process_frame
		if app.boot_result != null:
			break
	if not _require(app.boot_result != null and app.boot_result.is_ok(), "application boot"):
		return
	if not _require(app.content_snapshot.all(&"character").size() == 1, "Niko-only real character scope"):
		return
	app.begin_selection()
	if not _require(app.route(FlowRoute.CHARACTER_SELECT) == OK, "real character route"):
		return
	await _settle_ui()

	var host := app.get_node_or_null("SceneHost") as Node
	var screen := _current_screen(host)
	if not _require(_is_real_character_screen(screen), "real combined character screen"):
		return
	var roster := screen.get_node_or_null("RosterStrip") as GridContainer
	var niko := screen.get_node_or_null("RosterStrip/NikoCell") as Button
	var change := screen.get_node_or_null("ChangeCharacterButton") as Button
	if not _require(_assert_character_picker(screen, roster, niko, change), "initial 8x4 character picker"):
		return
	if not _require(root_window.gui_get_focus_owner() == niko, "initial Niko focus"):
		return
	if not await _capture_ready_and_wait(root_window, app, screen, &"character", 1):
		return

	niko.pressed.emit()
	await _settle_ui()
	if not _require(_current_screen(host) == screen, "weapon stage remains on the same page"):
		return
	var weapon_stage := screen.get_node_or_null("WeaponStage") as Control
	var difficulty_stage := screen.get_node_or_null("DifficultyStage") as Control
	var weapon_focus := root_window.gui_get_focus_owner() as Control
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.selection_draft.get("character_id", &"") == NikoContentFactory.CHARACTER_ID
		and app.selection_draft.get("weapon_id", &"") == &""
		and app.current_session == null
		and roster != null and not roster.visible
		and weapon_stage != null and weapon_stage.visible
		and difficulty_stage != null and not difficulty_stage.visible
		and change != null and change.visible and not change.disabled
		and weapon_focus != null and weapon_stage.is_ancestor_of(weapon_focus),
		"same-page weapon stage visibility, draft, and focus"
	):
		return
	if not await _capture_ready_and_wait(root_window, app, screen, &"weapon", 2):
		return

	var selected_weapon := _button_by_content_id(screen, ValidationContentFactory.RANGED_ID)
	if not _require(selected_weapon != null and not selected_weapon.disabled, "real canonical Glock-18 option"):
		return
	selected_weapon.pressed.emit()
	await _settle_ui()
	var preserved_draft := app.selection_draft.duplicate(true)
	if not _require(
		preserved_draft.get("character_id", &"") == NikoContentFactory.CHARACTER_ID
		and preserved_draft.get("weapon_id", &"") == ValidationContentFactory.RANGED_ID
		and difficulty_stage.visible
		and app.current_session == null,
		"weapon selection commits a legal draft without starting"
	):
		return
	change.pressed.emit()
	await _settle_ui()
	if not _require(_current_screen(host) == screen, "reopened character stage remains on the same page"):
		return
	if not _require(
		app.selection_draft == preserved_draft
		and app.current_session == null
		and roster.visible
		and niko.visible
		and not weapon_stage.visible
		and not difficulty_stage.visible
		and not change.visible and change.disabled
		and root_window.gui_get_focus_owner() == niko
		and _unavailable_character_count(roster) == 31,
		"reopened character picker preserves draft and Niko focus"
	):
		return
	if not await _capture_ready_and_wait(root_window, app, screen, &"character_reopened", 3):
		return

	niko.pressed.emit()
	await _settle_ui()
	if not _require(_current_screen(host) == screen, "reconfirmed weapon stage remains on the same page"):
		return
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.selection_draft == preserved_draft
		and app.current_session == null
		and not roster.visible
		and weapon_stage.visible
		and not difficulty_stage.visible
		and change.visible and not change.disabled
		and root_window.gui_get_focus_owner() == selected_weapon,
		"reconfirmed character restores the weapon stage and selected-weapon focus"
	):
		return
	selected_weapon.pressed.emit()
	await _settle_ui()
	if not _require(_current_screen(host) == screen, "difficulty stage remains on the same page"):
		return
	var difficulty := screen.get_node_or_null(
		"DifficultyStage/DifficultyStrip/DifficultyOption0"
	) as Button
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.selection_draft == preserved_draft
		and app.current_session == null
		and not roster.visible
		and weapon_stage.visible
		and difficulty_stage.visible
		and change.visible and not change.disabled
		and difficulty != null and not difficulty.disabled
		and difficulty.get_meta(&"content_id", &"") == ValidationContentFactory.DIFFICULTY_ID
		and root_window.gui_get_focus_owner() == difficulty,
		"difficulty stage restores legal draft and difficulty focus"
	):
		return
	if not await _capture_ready_and_wait(root_window, app, screen, &"difficulty", 4):
		return
	print("NATIVE960_CHARACTER_FLOW_OK stages=4")


func _capture_ready_and_wait(
	root_window: Window,
	app: AppKernel,
	screen: Control,
	stage: StringName,
	stage_index: int
) -> bool:
	root_window.title = _owned_title(stage)
	await _settle_ui()
	var screen_transform := root_window.get_screen_transform()
	var scale_x := screen_transform.x.length()
	var scale_y := screen_transform.y.length()
	var visible_size := root_window.get_visible_rect().size
	var root_texture := root_window.get_texture()
	var root_texture_size := Vector2i(root_texture.get_width(), root_texture.get_height())
	var display_window_size := DisplayServer.window_get_size(root_window.get_window_id())
	print(
		"NATIVE960_CHARACTER_FLOW_METRICS stage=%s window=%s display=%s visible=%s texture=%s content=%s factor=%.4f mode=%d aspect=%d stretch=%d scale=%.4fx%.4f transform=%s"
		% [stage, root_window.size, display_window_size, visible_size, root_texture_size,
			root_window.content_scale_size, root_window.content_scale_factor,
			root_window.content_scale_mode, root_window.content_scale_aspect,
			root_window.content_scale_stretch, scale_x, scale_y, screen_transform]
	)
	if not _require(
		root_window.size == CLIENT_SIZE
		and display_window_size == CLIENT_SIZE
		and visible_size.is_equal_approx(Vector2(LOGICAL_SIZE))
		and root_texture_size == ROOT_TEXTURE_SIZE
		and root_window.content_scale_size == LOGICAL_SIZE
		and absf(scale_x - EXPECTED_SCALE) <= SCALE_TOLERANCE
		and absf(scale_y - EXPECTED_SCALE) <= SCALE_TOLERANCE,
		"%s real 960 client maps logical 1280 at fractional 0.75" % stage
	):
		return false

	var temp_root := OS.get_environment("TEMP")
	var artifact_root := temp_root.path_join(ARTIFACT_DIRECTORY)
	if not _require(
		DirAccess.make_dir_recursive_absolute(artifact_root) in [OK, ERR_ALREADY_EXISTS],
		"%s fresh isolated artifact directory" % stage
	):
		return false
	var stage_key := "%02d-%s" % [stage_index, String(stage)]
	var ready_path := artifact_root.path_join(stage_key + "-ready.json")
	var native_client_path := artifact_root.path_join(stage_key + "-native-client-960x540.png")
	var ack_path := artifact_root.path_join(stage_key + "-observed.txt")
	var ack_token := "%s:%02d:%s:%d" % [
		OS.get_environment("TEMP").get_base_dir().get_file(),
		stage_index,
		String(stage),
		OS.get_process_id(),
	]
	if not _require(
		not FileAccess.file_exists(ready_path)
		and not FileAccess.file_exists(native_client_path)
		and not FileAccess.file_exists(ack_path),
		"%s artifacts never overwrite" % stage
	):
		return false
	var image := root_texture.get_image()
	var image_size := image.get_size() if image != null else Vector2i.ZERO
	var save_error := image.save_png(native_client_path) if image != null else ERR_CANT_CREATE
	print(
		"NATIVE960_CHARACTER_FLOW_IMAGE stage=%s texture=%s image=%s save_error=%d path=%s"
		% [stage, root_texture_size, image_size, save_error, native_client_path]
	)
	if not _require(
		image != null and image_size == CLIENT_SIZE and save_error == OK,
		"%s native 960 client PNG" % stage
	):
		return false
	var focus := root_window.gui_get_focus_owner() as Control
	var ready := {
		"schema_version": "gogobro-native960-character-flow-v1",
		"marker": CASE_NAME,
		"stage": String(stage),
		"stage_index": stage_index,
		"process_id": OS.get_process_id(),
		"title": root_window.title,
		"window_id": root_window.get_window_id(),
		"window_size": [root_window.size.x, root_window.size.y],
		"display_window_size": [display_window_size.x, display_window_size.y],
		"visible_rect": [visible_size.x, visible_size.y],
		"root_texture_size": [root_texture_size.x, root_texture_size.y],
		"root_image_size": [image_size.x, image_size.y],
		"content_scale_mode": root_window.content_scale_mode,
		"content_scale_size": [root_window.content_scale_size.x, root_window.content_scale_size.y],
		"content_scale_factor": root_window.content_scale_factor,
		"content_scale_stretch": root_window.content_scale_stretch,
		"content_scale_aspect": root_window.content_scale_aspect,
		"screen_transform": {
			"text": str(screen_transform),
			"x": [screen_transform.x.x, screen_transform.x.y],
			"y": [screen_transform.y.x, screen_transform.y.y],
			"origin": [screen_transform.origin.x, screen_transform.origin.y],
			"scale_x": scale_x,
			"scale_y": scale_y,
		},
		"route": String(app.scene_flow.current_route()),
		"same_page_script": (screen.get_script() as Script).resource_path,
		"draft": {
			"character_id": String(app.selection_draft.get("character_id", &"")),
			"weapon_id": String(app.selection_draft.get("weapon_id", &"")),
			"difficulty_id": String(app.selection_draft.get("difficulty_id", &"")),
			"zone_id": String(app.selection_draft.get("zone_id", &"")),
		},
		"stage_visibility": _stage_visibility(screen),
		"focused_control": {
			"path": String(focus.get_path()) if focus != null else "",
			"name": String(focus.name) if focus != null else "",
			"class": focus.get_class() if focus != null else "",
		},
		"ready_json": ready_path,
		"native_client_png": native_client_path,
		"observation_ack": ack_path,
		"observation_token": ack_token,
		"advance_method": "root_observation_ack",
		"timeout_msec": STAGE_TIMEOUT_MSEC,
	}
	if not _write_json_without_overwrite(ready_path, ready):
		return false
	print(
		"NATIVE960_CHARACTER_FLOW_READY stage=%s index=%d title=%s client=%dx%d visible=%dx%d texture=%dx%d scale=%.4fx%.4f ready=%s native_client_png=%s ack=%s ack_token=%s"
		% [stage, stage_index, root_window.title, root_window.size.x, root_window.size.y,
			int(visible_size.x), int(visible_size.y), root_texture_size.x, root_texture_size.y,
			scale_x, scale_y, ready_path, native_client_path, ack_path, ack_token]
	)
	return await _wait_for_root_observation_ack(stage, ack_path, ack_token)


func _wait_for_root_observation_ack(stage: StringName, ack_path: String, ack_token: String) -> bool:
	var deadline := Time.get_ticks_msec() + STAGE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if (
			FileAccess.file_exists(ack_path)
			and FileAccess.get_file_as_string(ack_path).strip_edges() == ack_token
		):
			return true
		await get_tree().process_frame
	return _require(false, "%s exact root observation ACK within 300 seconds" % stage)


func _assert_character_picker(
	screen: Control,
	roster: GridContainer,
	niko: Button,
	change: Button
) -> bool:
	return (
		screen != null
		and roster != null and roster.visible and roster.columns == 8 and roster.get_child_count() == 32
		and _fits_character_output(roster)
		and niko != null and niko.visible and not niko.disabled
		and niko.get_meta(&"content_id", &"") == NikoContentFactory.CHARACTER_ID
		and _unavailable_character_count(roster) == 31
		and change != null and not change.visible and change.disabled
		and not (screen.get_node("WeaponStage") as Control).visible
		and not (screen.get_node("DifficultyStage") as Control).visible
	)


func _fits_character_output(control: Control) -> bool:
	if control == null:
		return false
	var logical_rect := control.get_global_rect()
	var client_rect := Rect2(
		logical_rect.position * EXPECTED_SCALE,
		logical_rect.size * EXPECTED_SCALE
	)
	return (
		Rect2(Vector2.ZERO, Vector2(LOGICAL_SIZE)).encloses(logical_rect)
		and Rect2(Vector2.ZERO, Vector2(CLIENT_SIZE)).encloses(client_rect)
	)


func _unavailable_character_count(roster: GridContainer) -> int:
	if roster == null:
		return -1
	var count := 0
	for child in roster.get_children():
		if child.name == &"NikoCell":
			continue
		var slot := child as Button
		if (
			slot == null
			or not String(slot.name).begins_with("UnavailableCharacterSlot")
			or not slot.text.is_empty()
			or not slot.has_node("SlotIndex")
			or not slot.has_node("Glyph")
			or not slot.has_node("Status")
			or (slot.get_node("Status") as Label).text != "待开放"
			or not slot.disabled
			or slot.focus_mode != Control.FOCUS_NONE
			or slot.has_meta(&"content_id")
			or slot.has_meta(&"definition")
			or not slot.get_signal_connection_list(&"pressed").is_empty()
		):
			return -1
		count += 1
	return count


func _button_by_content_id(screen: Control, content_id: StringName) -> Button:
	for candidate in screen.find_children("WeaponOption*", "Button", true, false):
		var button := candidate as Button
		if button != null and button.get_meta(&"content_id", &"") == content_id:
			return button
	return null


func _stage_visibility(screen: Control) -> Dictionary:
	return {
		"roster": (screen.get_node("RosterStrip") as Control).visible,
		"niko": (screen.get_node("RosterStrip/NikoCell") as Control).visible,
		"change_character": (screen.get_node("ChangeCharacterButton") as Control).visible,
		"weapon": (screen.get_node("WeaponStage") as Control).visible,
		"difficulty": (screen.get_node("DifficultyStage") as Control).visible,
		"unavailable_slots": _unavailable_character_count(screen.get_node("RosterStrip") as GridContainer),
	}


func _owned_title(stage: StringName) -> String:
	var temp_root := OS.get_environment("TEMP")
	var isolation_id := temp_root.get_base_dir().get_file()
	return "GOGOBRO native960 character %s pid-%d %s" % [isolation_id, OS.get_process_id(), stage]


func _write_json_without_overwrite(path: String, value: Dictionary) -> bool:
	if FileAccess.file_exists(path):
		_fail("ready JSON overwrite refused: " + path)
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("ready JSON open failed: " + path)
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return true


func _settle_ui() -> void:
	_queue_canvas_redraw(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _queue_canvas_redraw(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	for child in node.get_children():
		_queue_canvas_redraw(child)


func _current_screen(host: Node) -> Control:
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0) as Control


func _is_real_character_screen(screen: Control) -> bool:
	return (
		screen != null
		and screen.get_script() != null
		and (screen.get_script() as Script).resource_path == "res://game/ui/character_select_screen.gd"
	)


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("NATIVE_960_CHARACTER_FLOW_FAILED: " + message)
