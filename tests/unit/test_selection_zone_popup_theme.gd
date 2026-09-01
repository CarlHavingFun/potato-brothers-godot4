extends GdUnitTestSuite


const ZONE_PRESENTER := preload("res://game/ui/selection_zone_presenter.gd")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const OPTION_RECT := Rect2(1010, 28, 238, 48)


func test_task_popup_uses_a_high_contrast_gogobro_menu_theme() -> void:
	var fixture := _fixture()
	var presenter := fixture.presenter as RefCounted
	var option := fixture.option as OptionButton
	var popup := option.get_popup()

	assert_int(option.get_theme_constant(&"icon_max_width")).is_equal(40)
	assert_int(popup.get_theme_constant(&"icon_max_width")).is_equal(64)
	assert_int(popup.get_theme_font_size(&"font_size")).is_greater_equal(20)
	assert_object(popup.get_theme_font(&"font")).is_not_null()
	assert_object(popup.get_theme_font(&"font_separator")).is_not_null()
	assert_int(popup.get_theme_constant(&"h_separation")).is_greater_equal(12)
	assert_int(popup.get_theme_constant(&"v_separation")).is_greater_equal(8)
	assert_int(popup.get_theme_constant(&"item_start_padding")).is_greater_equal(12)
	assert_int(popup.get_theme_constant(&"item_end_padding")).is_greater_equal(12)
	assert_int(popup.min_size.x).is_greater_equal(int(OPTION_RECT.size.x))

	var panel := popup.get_theme_stylebox(&"panel") as StyleBoxFlat
	var hover := popup.get_theme_stylebox(&"hover") as StyleBoxFlat
	var separator := popup.get_theme_stylebox(&"separator") as StyleBoxFlat
	assert_object(panel).is_not_null()
	assert_object(hover).is_not_null()
	assert_object(separator).is_not_null()
	if panel == null or hover == null or separator == null:
		return
	assert_bool(panel.bg_color.is_equal_approx(Color("090c0e"))).is_true()
	assert_bool(panel.border_color.is_equal_approx(HUD_SKIN.COLOR_FOCUS)).is_true()
	assert_int(panel.border_width_left).is_equal(2)
	assert_float(panel.get_content_margin(SIDE_LEFT)).is_greater_equal(8.0)
	assert_bool(hover.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_FOCUS)).is_true()
	assert_bool(
		popup.get_theme_color(&"font_hover_color").is_equal_approx(
			HUD_SKIN.COLOR_TEXT_FOCUS
		)
	).is_true()
	assert_bool(not hover.bg_color.is_equal_approx(panel.bg_color)).is_true()
	assert_bool(separator.border_color.is_equal_approx(Color("554731"))).is_true()
	assert_int(separator.border_width_top).is_equal(1)
	var selected_marker := popup.get_theme_icon(&"radio_checked")
	var unselected_marker := popup.get_theme_icon(&"radio_unchecked")
	assert_object(selected_marker).is_not_null()
	assert_object(unselected_marker).is_not_null()
	if selected_marker != null and unselected_marker != null:
		assert_vector(selected_marker.get_size()).is_equal(Vector2(16, 16))
		assert_vector(unselected_marker.get_size()).is_equal(Vector2(16, 16))
		assert_bool(
			selected_marker.get_image().get_pixel(7, 7).is_equal_approx(
				HUD_SKIN.COLOR_FOCUS
			)
		).is_true()
		assert_float(unselected_marker.get_image().get_pixel(7, 7).a).is_equal(0.0)


func test_task_popup_keeps_real_items_contiguous_and_marks_the_selection() -> void:
	var fixture := _fixture()
	var presenter := fixture.presenter as RefCounted
	var option := fixture.option as OptionButton
	var popup := option.get_popup()

	assert_int(option.item_count).is_equal(1)
	assert_int(popup.item_count).is_equal(option.item_count)
	assert_bool(popup.is_item_radio_checkable(0)).is_true()
	assert_bool(popup.is_item_checked(0)).is_false()
	presenter.call(&"apply_selection", ValidationContentFactory.ZONE_ID)
	assert_int(option.selected).is_equal(0)
	assert_bool(popup.is_item_radio_checkable(0)).is_true()
	assert_bool(popup.is_item_checked(0)).is_true()
	assert_str(option.get_item_text(0)).is_equal("任务 · 训练场")
	assert_object(option.get_item_icon(0)).is_not_null()


func _fixture() -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
	add_child(app)
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _static_snapshot()
	add_child(screen)
	var presenter := ZONE_PRESENTER.new()
	var option := presenter.build(
		screen,
		app,
		screen,
		OPTION_RECT,
		func(_content_id: StringName) -> void: pass
	)
	return {"presenter": presenter, "option": option}


func _static_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(256, 144, false, Image.FORMAT_RGBA8)
	image.fill(Color("384348"))
	var texture := ImageTexture.create_from_image(image)
	var handle := GogoStaticAssetHandle.new()
	var asset_key := "zone_thumbnail|zone_thumbnail|"
	handle._configure({
		"binding_key": StringName(asset_key),
		"asset_id": &"zone_thumbnail",
		"role": &"zone_thumbnail",
		"selector": &"",
		"display_size_px": Vector2i(256, 144),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(128, 72),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(0, 0, 256, 144),
	}, texture)
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{},
		{asset_key: handle},
		{},
		{},
		{"global||zone_thumbnail|": asset_key},
		[]
	)
	return snapshot
