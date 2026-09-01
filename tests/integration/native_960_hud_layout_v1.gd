extends GdUnitTestSuite


const CASE_NAME := "test_native_960_combat_hud_layout_waits_for_root_observation_ack"
const ARTIFACT_DIRECTORY := "native960-hud-layout-v1"
const STAGE_NAME := &"combat_hud"
const CLIENT_SIZE := Vector2i(960, 540)
const LOGICAL_SIZE := Vector2i(1280, 720)
const ROOT_TEXTURE_SIZE := Vector2i(720, 405)
const EXPECTED_SCALE := 0.75
const SCALE_TOLERANCE := 0.01
const STAGE_TIMEOUT_MSEC := 300000
const EXPECTED_LOGICAL_GAP := 4.0
const EXPECTED_PHYSICAL_GAP := 3.0


func test_native_960_combat_hud_layout_waits_for_root_observation_ack(
	_timeout := 360000
) -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := get_tree().root
	if not _require(get_window() == root_window, "suite is hosted by the real root Window"):
		return
	root_window.size = CLIENT_SIZE
	root_window.title = _owned_title()
	# GdUnit minimizes its host before running. Restore only this owned GOBRO
	# root window so the compatibility renderer submits a real client frame.
	root_window.mode = Window.MODE_WINDOWED
	root_window.show()
	await _settle_ui()

	var content := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(false)
	)
	if not _require(content != null, "validation content snapshot"):
		return
	var static_service := GogoStaticAssetRuntimeService.new()
	if not _require(
		static_service.stage(content) == OK
		and static_service.activate_staged(&"", null) == OK,
		"canonical shipping static assets"
	):
		return
	var static_snapshot := static_service.active_snapshot()
	if not _require(
		static_snapshot != null
		and static_snapshot.resolve_global(&"hud_icon_kit", &"wave") != null
		and static_snapshot.resolve_global(&"hud_icon_kit", &"wave_timer") != null,
		"canonical wave and timer icon handles"
	):
		return

	var stage_root := auto_free(Control.new()) as Control
	stage_root.name = "Native960CombatHudStage"
	stage_root.size = Vector2(LOGICAL_SIZE)
	stage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_root.z_index = 100
	root_window.add_child(stage_root)
	var background := ColorRect.new()
	background.name = "ArenaBackground"
	background.position = Vector2.ZERO
	background.size = Vector2(LOGICAL_SIZE)
	background.color = Color("68746e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_root.add_child(background)

	var player := SessionPlayerState.new()
	player.current_health = 999.0
	player.max_health = 999.0
	player.level = 99
	player.xp = 999
	player.xp_to_next_level = 999
	player.materials = 9999
	var snapshot := GogoCombatHudSnapshot.create(
		player,
		999.0,
		999,
		3.0,
		999,
		true,
		20
	)
	var hud := GogoBrotatoCombatHud.new()
	hud.name = "ObservedCombatHUD"
	hud.configure(snapshot, content, static_snapshot)
	stage_root.add_child(hud)
	await _settle_ui()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	var wave_icon := hud.get_node_or_null("TopCenter/WaveIcon") as TextureRect
	var wave_label := hud.get_node_or_null("TopCenter/Wave") as Label
	var timer_icon := hud.get_node_or_null("TopCenter/TimerIcon") as TextureRect
	var timer_label := hud.get_node_or_null("TopCenter/Timer") as Label
	if not _require(
		wave_icon != null
		and wave_label != null
		and timer_icon != null
		and timer_label != null
		and wave_icon.texture != null
		and timer_icon.texture != null
		and wave_label.text == "无尽 · 第 999 波"
		and timer_label.text == "999",
		"visible canonical icons and longest reasonable wave/time values"
	):
		return

	var screen_transform := root_window.get_screen_transform()
	var scale_x := screen_transform.x.length()
	var scale_y := screen_transform.y.length()
	var visible_size := root_window.get_visible_rect().size
	var root_texture := root_window.get_texture()
	var root_texture_size := Vector2i(root_texture.get_width(), root_texture.get_height())
	var display_window_size := DisplayServer.window_get_size(root_window.get_window_id())
	if not _require(
		root_window.size == CLIENT_SIZE
		and display_window_size == CLIENT_SIZE
		and visible_size.is_equal_approx(Vector2(LOGICAL_SIZE))
		and root_texture_size == ROOT_TEXTURE_SIZE
		and root_window.content_scale_size == LOGICAL_SIZE
		and absf(scale_x - EXPECTED_SCALE) <= SCALE_TOLERANCE
		and absf(scale_y - EXPECTED_SCALE) <= SCALE_TOLERANCE,
		"real 960 client maps logical 1280 at fractional 0.75"
	):
		return

	var logical_rects := {
		"wave_icon": wave_icon.get_global_rect(),
		"wave_label": wave_label.get_global_rect(),
		"timer_icon": timer_icon.get_global_rect(),
		"timer_label": timer_label.get_global_rect(),
	}
	var physical_rects := {
		"wave_icon": _screen_rect(wave_icon, screen_transform),
		"wave_label": _screen_rect(wave_label, screen_transform),
		"timer_icon": _screen_rect(timer_icon, screen_transform),
		"timer_label": _screen_rect(timer_label, screen_transform),
	}
	var wave_gap_logical := (
		(logical_rects["wave_label"] as Rect2).position.x
		- (logical_rects["wave_icon"] as Rect2).end.x
	)
	var timer_gap_logical := (
		(logical_rects["timer_label"] as Rect2).position.x
		- (logical_rects["timer_icon"] as Rect2).end.x
	)
	var wave_gap_physical := (
		(physical_rects["wave_label"] as Rect2).position.x
		- (physical_rects["wave_icon"] as Rect2).end.x
	)
	var timer_gap_physical := (
		(physical_rects["timer_label"] as Rect2).position.x
		- (physical_rects["timer_icon"] as Rect2).end.x
	)
	var wave_center_logical := (
		(logical_rects["wave_icon"] as Rect2).position.x
		+ (logical_rects["wave_label"] as Rect2).end.x
	) * 0.5
	var timer_center_logical := (
		(logical_rects["timer_icon"] as Rect2).position.x
		+ (logical_rects["timer_label"] as Rect2).end.x
	) * 0.5
	var wave_center_physical := (
		(physical_rects["wave_icon"] as Rect2).position.x
		+ (physical_rects["wave_label"] as Rect2).end.x
	) * 0.5
	var timer_center_physical := (
		(physical_rects["timer_icon"] as Rect2).position.x
		+ (physical_rects["timer_label"] as Rect2).end.x
	) * 0.5
	var physical_client := Rect2(Vector2.ZERO, Vector2(CLIENT_SIZE))
	if not _require(
		is_equal_approx(wave_gap_logical, EXPECTED_LOGICAL_GAP)
		and is_equal_approx(timer_gap_logical, EXPECTED_LOGICAL_GAP)
		and is_equal_approx(wave_gap_physical, EXPECTED_PHYSICAL_GAP)
		and is_equal_approx(timer_gap_physical, EXPECTED_PHYSICAL_GAP)
		and screen_transform.origin.is_zero_approx()
		and is_equal_approx(wave_center_logical, LOGICAL_SIZE.x * 0.5)
		and is_equal_approx(timer_center_logical, LOGICAL_SIZE.x * 0.5)
		and is_equal_approx(wave_center_physical, CLIENT_SIZE.x * 0.5)
		and is_equal_approx(timer_center_physical, CLIENT_SIZE.x * 0.5)
		and (logical_rects["wave_icon"] as Rect2).is_equal_approx(
			Rect2(576, 12, 16, 16)
		)
		and (logical_rects["wave_label"] as Rect2).is_equal_approx(
			Rect2(596, 8, 108, 24)
		)
		and (logical_rects["timer_icon"] as Rect2).is_equal_approx(
			Rect2(596, 44, 16, 16)
		)
		and (logical_rects["timer_label"] as Rect2).is_equal_approx(
			Rect2(616, 32, 68, 40)
		)
		and (physical_rects["wave_icon"] as Rect2).is_equal_approx(
			Rect2(432, 9, 12, 12)
		)
		and (physical_rects["wave_label"] as Rect2).is_equal_approx(
			Rect2(447, 6, 81, 18)
		)
		and (physical_rects["timer_icon"] as Rect2).is_equal_approx(
			Rect2(447, 33, 12, 12)
		)
		and (physical_rects["timer_label"] as Rect2).is_equal_approx(
			Rect2(462, 24, 51, 30)
		)
		and _all_integer_rects(physical_rects)
		and _all_rects_enclosed(physical_rects, physical_client)
		and not (physical_rects["wave_icon"] as Rect2).intersects(
			physical_rects["wave_label"] as Rect2
		)
		and not (physical_rects["timer_icon"] as Rect2).intersects(
			physical_rects["timer_label"] as Rect2
		)
		and wave_label.get_minimum_size().x <= wave_label.size.x
		and timer_label.get_minimum_size().x <= timer_label.size.x,
		"integer 960 geometry, explicit gaps, and unclipped labels"
	):
		return

	print(
		"NATIVE960_HUD_LAYOUT_METRICS stage=combat_hud window=%s display=%s visible=%s texture=%s scale=%.4fx%.4f wave_gap=%.1f/%.1f timer_gap=%.1f/%.1f"
		% [root_window.size, display_window_size, visible_size, root_texture_size,
			scale_x, scale_y, wave_gap_logical, wave_gap_physical,
			timer_gap_logical, timer_gap_physical]
	)
	if not await _capture_ready_and_wait(
		root_window,
		root_texture,
		display_window_size,
		visible_size,
		root_texture_size,
		screen_transform,
		scale_x,
		scale_y,
		logical_rects,
		physical_rects,
		wave_gap_logical,
		timer_gap_logical,
		wave_gap_physical,
		timer_gap_physical,
		wave_center_logical,
		timer_center_logical,
		wave_center_physical,
		timer_center_physical,
		wave_label,
		timer_label
	):
		return
	print("NATIVE960_HUD_LAYOUT_OK cases=1 stages=1 gap_logical=4 gap_physical=3")


func _capture_ready_and_wait(
	root_window: Window,
	root_texture: ViewportTexture,
	display_window_size: Vector2i,
	visible_size: Vector2,
	root_texture_size: Vector2i,
	screen_transform: Transform2D,
	scale_x: float,
	scale_y: float,
	logical_rects: Dictionary,
	physical_rects: Dictionary,
	wave_gap_logical: float,
	timer_gap_logical: float,
	wave_gap_physical: float,
	timer_gap_physical: float,
	wave_center_logical: float,
	timer_center_logical: float,
	wave_center_physical: float,
	timer_center_physical: float,
	wave_label: Label,
	timer_label: Label
) -> bool:
	var temp_root := OS.get_environment("TEMP")
	var artifact_root := temp_root.path_join(ARTIFACT_DIRECTORY)
	if not _require(
		DirAccess.make_dir_recursive_absolute(artifact_root) in [OK, ERR_ALREADY_EXISTS],
		"fresh isolated artifact directory"
	):
		return false
	var stage_key := "01-combat_hud"
	var ready_path := artifact_root.path_join(stage_key + "-ready.json")
	var native_client_path := artifact_root.path_join(
		stage_key + "-native-client-960x540.png"
	)
	var ack_path := artifact_root.path_join(stage_key + "-observed.txt")
	var ack_token := "%s:01:combat_hud:%d" % [
		temp_root.get_base_dir().get_file(),
		OS.get_process_id(),
	]
	if not _require(
		not FileAccess.file_exists(ready_path)
		and not FileAccess.file_exists(native_client_path)
		and not FileAccess.file_exists(ack_path),
		"combat HUD artifacts never overwrite"
	):
		return false
	var image := root_texture.get_image()
	var image_size := image.get_size() if image != null else Vector2i.ZERO
	var save_error := image.save_png(native_client_path) if image != null else ERR_CANT_CREATE
	if not _require(
		image != null and image_size == CLIENT_SIZE and save_error == OK,
		"native 960 client PNG"
	):
		return false
	var ready := {
		"schema_version": "gogobro-native960-hud-layout-v1",
		"marker": CASE_NAME,
		"stage": String(STAGE_NAME),
		"stage_index": 1,
		"process_id": OS.get_process_id(),
		"title": root_window.title,
		"window_id": root_window.get_window_id(),
		"window_size": [root_window.size.x, root_window.size.y],
		"display_window_size": [display_window_size.x, display_window_size.y],
		"visible_rect": [visible_size.x, visible_size.y],
		"root_texture_size": [root_texture_size.x, root_texture_size.y],
		"root_image_size": [image_size.x, image_size.y],
		"content_scale_mode": root_window.content_scale_mode,
		"content_scale_size": [
			root_window.content_scale_size.x,
			root_window.content_scale_size.y,
		],
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
		"hud": {
			"wave_text": wave_label.text,
			"timer_text": timer_label.text,
			"wave_minimum_width": wave_label.get_minimum_size().x,
			"timer_minimum_width": timer_label.get_minimum_size().x,
			"wave_gap_logical": wave_gap_logical,
			"timer_gap_logical": timer_gap_logical,
			"wave_gap_physical": wave_gap_physical,
			"timer_gap_physical": timer_gap_physical,
			"wave_center_logical": wave_center_logical,
			"timer_center_logical": timer_center_logical,
			"wave_center_physical": wave_center_physical,
			"timer_center_physical": timer_center_physical,
			"logical_rects": _rect_dictionary_payload(logical_rects),
			"physical_rects": _rect_dictionary_payload(physical_rects),
			"integer_physical_rects": _all_integer_rects(physical_rects),
			"physical_client_encloses": _all_rects_enclosed(
				physical_rects,
				Rect2(Vector2.ZERO, Vector2(CLIENT_SIZE))
			),
		},
		"ready_json": ready_path,
		"native_client_png": native_client_path,
		"observation_ack": ack_path,
		"observation_token": ack_token,
		"advance_method": "root_observation_ack",
		"timeout_msec": STAGE_TIMEOUT_MSEC,
		"profile_entry": "none_direct_hud_stage",
	}
	if not _write_json_without_overwrite(ready_path, ready):
		return false
	print(
		"NATIVE960_HUD_LAYOUT_READY stage=combat_hud index=1 title=%s client=960x540 visible=1280x720 texture=720x405 scale=0.7500x0.7500 ready=%s native_client_png=%s ack=%s ack_token=%s"
		% [root_window.title, ready_path, native_client_path, ack_path, ack_token]
	)
	return await _wait_for_root_observation_ack(ack_path, ack_token)


func _wait_for_root_observation_ack(ack_path: String, ack_token: String) -> bool:
	var deadline := Time.get_ticks_msec() + STAGE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if (
			FileAccess.file_exists(ack_path)
			and FileAccess.get_file_as_string(ack_path).strip_edges() == ack_token
		):
			return true
		await get_tree().process_frame
	return _require(false, "exact root observation ACK within 300 seconds")


func _screen_rect(control: Control, screen_transform: Transform2D) -> Rect2:
	var logical_rect := control.get_global_rect()
	var start := screen_transform * logical_rect.position
	var finish := screen_transform * logical_rect.end
	return Rect2(start, finish - start)


func _all_integer_rects(rects: Dictionary) -> bool:
	for value: Variant in rects.values():
		var rect := value as Rect2
		for component: float in [rect.position.x, rect.position.y, rect.size.x, rect.size.y]:
			if not is_equal_approx(component, roundf(component)):
				return false
	return true


func _all_rects_enclosed(rects: Dictionary, bounds: Rect2) -> bool:
	for value: Variant in rects.values():
		if not bounds.encloses(value as Rect2):
			return false
	return true


func _rect_dictionary_payload(rects: Dictionary) -> Dictionary:
	var payload := {}
	for key: String in rects:
		var rect := rects[key] as Rect2
		payload[key] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return payload


func _owned_title() -> String:
	var isolation_id := OS.get_environment("TEMP").get_base_dir().get_file()
	return "GOGOBRO native960 HUD %s pid-%d combat_hud" % [
		isolation_id,
		OS.get_process_id(),
	]


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


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("NATIVE_960_HUD_LAYOUT_FAILED: " + message)
