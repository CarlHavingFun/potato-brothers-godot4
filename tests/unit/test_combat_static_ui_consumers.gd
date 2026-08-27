extends GdUnitTestSuite


const COMBAT_SCREEN := preload("res://game/ui/combat_screen.gd")


func test_combat_hud_keeps_large_block_fallbacks_when_static_textures_are_unavailable() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	add_child(combat)
	combat.call("_build_hud")

	var hud := combat.get_node("HUDCanvas/BrotatoHUD") as GogoBrotatoCombatHud
	assert_vector(hud.custom_minimum_size).is_equal(Vector2(320, 180))
	assert_vector(hud.scale).is_equal(Vector2(4, 4))
	assert_object((hud.get_node("Shell") as TextureRect).texture).is_null()
	assert_bool(hud.has_node("TopCenter/Timer")).is_true()
	assert_bool(hud.has_node("BottomLeft/HealthBar")).is_true()
	assert_int(hud.get_node("WeaponStrip").get_child_count()).is_equal(6)
	assert_int(hud.get_node("ItemStrip").get_child_count()).is_equal(8)
	assert_bool((hud.get_node("ControlHint") as Control).visible).is_true()


func test_combat_hud_resolves_shell_hud_and_control_texture_consumers_at_nearest_filtering() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	combat.set("static_asset_snapshot_override", _static_ui_snapshot())
	add_child(combat)
	combat.call("_build_hud")

	var paths := [
		"HUDCanvas/BrotatoHUD/Shell",
		"HUDCanvas/BrotatoHUD/BottomLeft/HealthIcon",
		"HUDCanvas/BrotatoHUD/TopCenter/WaveIcon",
		"HUDCanvas/BrotatoHUD/TopCenter/TimerIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/MoveKeyboardIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/MoveGamepadIcon",
		"HUDCanvas/BrotatoHUD/ControlHint/HintContent/AutoAttackIcon",
	]
	for path: String in paths:
		var icon := combat.get_node(path) as TextureRect
		assert_object(icon).is_not_null()
		assert_object(icon.texture).is_not_null()
		assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)


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
