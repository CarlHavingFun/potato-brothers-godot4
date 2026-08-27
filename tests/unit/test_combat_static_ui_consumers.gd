extends GdUnitTestSuite


const COMBAT_SCREEN := preload("res://game/ui/combat_screen.gd")


func test_combat_hud_keeps_text_fallback_when_static_atlases_are_unavailable() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	add_child(combat)
	combat.call("_build_hud")

	var metrics := combat.get_node("HUDCanvas/HUDMetrics") as HBoxContainer
	assert_int(metrics.get_child_count()).is_equal(3)
	var hint := combat.get_node("HUDCanvas/ControlHint") as HBoxContainer
	assert_bool(hint.position == Vector2(24.0, 100.0)).is_true()
	var fallback := hint.get_node("ControlHintFallback") as Label
	assert_str(fallback.text).is_equal("WASD 移动 · 武器自动攻击")


func test_combat_hud_resolves_all_frozen_global_atlas_selectors() -> void:
	var combat := auto_free(COMBAT_SCREEN.new()) as Node2D
	combat.set("static_asset_snapshot_override", _static_ui_snapshot())
	add_child(combat)
	combat.call("_build_hud")

	for path: String in [
		"HUDCanvas/HUDMetrics/HealthMetric/healthIcon",
		"HUDCanvas/HUDMetrics/WaveMetric/waveIcon",
		"HUDCanvas/HUDMetrics/WaveTimerMetric/wave_timerIcon",
		"HUDCanvas/ControlHint/move_keyboard_wasdControl/move_keyboard_wasdIcon",
		"HUDCanvas/ControlHint/move_gamepad_left_stickControl/move_gamepad_left_stickIcon",
		"HUDCanvas/ControlHint/auto_attackControl/auto_attackIcon",
	]:
		var icon := combat.get_node(path) as TextureRect
		assert_object(icon).is_not_null()
		assert_bool(icon.custom_minimum_size == Vector2(64.0, 64.0)).is_true()
		assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_bool(combat.has_node("HUDCanvas/ControlHint/ControlHintFallback")).is_false()


func _static_ui_snapshot() -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	var global_bindings: Dictionary = {}
	var selectors := {
		"hud_icon_kit": ["health", "wave", "wave_timer"],
		"control_icon_kit": ["move_keyboard_wasd", "move_gamepad_left_stick", "auto_attack"],
	}
	for asset_id: String in selectors:
		for selector: String in selectors[asset_id]:
			var asset_key := "%s|icon|%s" % [asset_id, selector]
			var handle := GogoStaticAssetHandle.new()
			handle._configure({
				"binding_key": StringName(asset_key),
				"asset_id": StringName(asset_id),
				"role": &"icon",
				"selector": StringName(selector),
				"display_size_px": Vector2i(64, 64),
				"display_scale": Vector2.ONE,
				"pivot_px": Vector2i(32, 32),
				"anchors_px": {},
				"atlas_rect_px": Rect2i(0, 0, 64, 64),
			}, _test_texture())
			handles[asset_key] = handle
			global_bindings["global||%s|%s" % [asset_id, selector]] = asset_key
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "fixture", 70, {}, handles, {}, {}, global_bindings, [])
	return snapshot


func _test_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color8(235, 151, 40, 255))
	return ImageTexture.create_from_image(image)
