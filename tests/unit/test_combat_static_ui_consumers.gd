extends GdUnitTestSuite


const COMBAT_SCREEN := preload("res://game/ui/combat_screen.gd")


func test_combat_hud_keeps_native_flat_fallbacks_when_static_textures_are_unavailable() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	add_child(combat)
	combat.call("_build_hud")

	var hud := combat.get_node("HUDCanvas/BrotatoHUD") as GogoBrotatoCombatHud
	assert_vector(hud.custom_minimum_size).is_equal(Vector2(1280, 720))
	assert_vector(hud.scale).is_equal(Vector2.ONE)
	assert_bool(hud.has_node("Backdrop")).is_false()
	assert_bool(hud.has_node("Shell")).is_true()
	if not hud.has_node("Shell"):
		return
	assert_bool((hud.get_node("Shell") as TextureRect).visible).is_false()
	assert_bool(hud.has_node("TopCenter/Timer")).is_true()
	assert_bool(hud.has_node("TopLeft/Health/HealthBar")).is_true()
	assert_bool(hud.has_node("WeaponStrip")).is_false()
	assert_bool(hud.has_node("ItemStrip")).is_false()
	assert_bool((hud.get_node("ControlHint") as Control).visible).is_true()


func test_combat_hud_resolves_accent_hud_and_control_texture_consumers_at_nearest_filtering() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var snapshot := _static_ui_snapshot()
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	combat.set("static_asset_snapshot_override", snapshot)
	add_child(combat)
	combat.call("_build_hud")

	var paths := [
		"HUDCanvas/BrotatoHUD/TopLeft/Health/HealthIcon",
		"HUDCanvas/BrotatoHUD/TopCenter/WaveIcon",
		"HUDCanvas/BrotatoHUD/TopCenter/TimerIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/MoveKeyboardIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/MoveGamepadIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/AutoAttackIcon",
	]
	for path: String in paths:
		var icon := combat.get_node_or_null(path) as TextureRect
		assert_object(icon).is_not_null()
		if icon == null:
			continue
		assert_object(icon.texture).is_not_null()
		assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		var displayed_size := Vector2i(roundi(icon.size.x), roundi(icon.size.y))
		var source_size := icon.texture.get_size()
		assert_bool(displayed_size.x > 0 and displayed_size.y > 0).is_true()
		assert_int(int(source_size.x) % displayed_size.x).is_zero()
		assert_int(int(source_size.y) % displayed_size.y).is_zero()
		assert_int(int(source_size.x) / displayed_size.x).is_equal(
			int(source_size.y) / displayed_size.y
		)
	var hud := combat.get_node("HUDCanvas/BrotatoHUD") as GogoBrotatoCombatHud
	var shell := hud.get_node_or_null("Shell") as TextureRect
	assert_object(shell).is_not_null()
	if shell == null:
		return
	assert_object(shell.texture).is_same(
		snapshot.resolve_global(&"combat_hud_shell").texture
	)
	assert_bool(shell.visible).is_true()
	assert_bool(shell.is_visible_in_tree()).is_true()
	assert_int(shell.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_vector(shell.size).is_equal(Vector2(1280, 720))
	var metric_style := (hud.get_node("TopLeft/Health") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	assert_bool(metric_style.bg_color.is_equal_approx(GogoBrotatoCombatHud.METRIC_BACKING_COLOR)).is_true()
	var shell_records := GogoStaticConsumerRegistry.current().records().filter(
		func(record: Dictionary) -> bool:
			return record.get("asset_id", &"") == &"combat_hud_shell"
	)
	assert_int(shell_records.size()).is_equal(1)
	if shell_records.size() == 1:
		assert_str(String(shell_records[0].node)).is_equal("BrotatoHUD/Shell")
		assert_bool(shell_records[0].get("visible_texture", false)).is_true()
		assert_vector(shell_records[0].integer_display_scale).is_equal(Vector2i(4, 4))
	assert_bool(GogoStaticConsumerRegistry.current().records().any(func(record: Dictionary) -> bool:
		return record.get("node", "") == "BrotatoHUD/MetricPalette"
	)).is_false()


func test_combat_screen_mounts_hidden_pause_overlay_above_the_hud() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	add_child(combat)
	combat.call("_build_hud")
	combat.call("_build_pause_overlay")
	var hud_canvas := combat.get_node("HUDCanvas") as CanvasLayer
	var pause_canvas := combat.get_node("PauseCanvas") as CanvasLayer
	var overlay := pause_canvas.get_node("PauseOverlay") as Control
	assert_bool(pause_canvas.layer > hud_canvas.layer).is_true()
	assert_bool(overlay.visible).is_false()
	assert_bool(overlay.has_node("PauseMenu/ContinueButton")).is_true()
	assert_bool(overlay.has_node("ExitConfirmation/ConfirmButton")).is_true()


func _static_ui_snapshot() -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	var global_bindings: Dictionary = {}
	_add_global_handle(handles, global_bindings, &"combat_hud_shell", &"", Vector2i(320, 180))
	for selector in [&"health", &"wave", &"wave_timer"]:
		_add_global_handle(handles, global_bindings, &"hud_icon_kit", selector, Vector2i(64, 64))
	for selector in [&"move_keyboard_wasd", &"move_gamepad_left_stick", &"auto_attack"]:
		_add_global_handle(handles, global_bindings, &"control_icon_kit", selector, Vector2i(64, 64))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "fixture", 70, {}, handles, {}, {}, global_bindings, [])
	return snapshot


func _add_global_handle(
	handles: Dictionary,
	global_bindings: Dictionary,
	asset_id: StringName,
	selector: StringName,
	display_size: Vector2i
) -> void:
	var role := asset_id
	var asset_key := "%s|%s|%s" % [asset_id, role, selector]
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": StringName(asset_key),
		"asset_id": asset_id,
		"role": role,
		"selector": selector,
		"display_size_px": display_size,
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(display_size / 2),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(Vector2i.ZERO, display_size),
	}, _test_texture(display_size))
	handles[asset_key] = handle
	global_bindings["global||%s|%s" % [asset_id, selector]] = asset_key


func _test_texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color8(235, 151, 40, 255))
	return ImageTexture.create_from_image(image)
