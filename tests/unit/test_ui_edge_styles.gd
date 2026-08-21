extends GdUnitTestSuite


func test_representative_cards_and_buttons_share_smooth_six_pixel_edges() -> void:
	var custom_button: Button = auto_free(
		(load("res://scenes/ui/custom_button/custom_buttom.tscn") as PackedScene).instantiate()
	) as Button
	var shop_card: Panel = auto_free(
		(load("res://scenes/ui/shop_card/shop_card.tscn") as PackedScene).instantiate()
	) as Panel
	var selection_card: Button = auto_free(
		(load("res://scenes/ui/selection_panel/selection_card.tscn") as PackedScene).instantiate()
	) as Button
	var settings_panel: Panel = auto_free(
		(load("res://scenes/ui/settings_panel/settings_panel.tscn") as PackedScene).instantiate()
	) as Panel
	add_child(custom_button)
	add_child(shop_card)
	add_child(selection_card)
	add_child(settings_panel)
	await await_idle_frame()

	var styles: Array[StyleBoxFlat] = [
		custom_button.get_theme_stylebox(&"normal") as StyleBoxFlat,
		custom_button.get_theme_stylebox(&"hover") as StyleBoxFlat,
		(shop_card.get_node("MarginContainer/Control/ItemBG") as Panel).get_theme_stylebox(
			&"panel"
		) as StyleBoxFlat,
		(selection_card.get_node("SelectedIndicator") as Panel).get_theme_stylebox(
			&"panel"
		) as StyleBoxFlat,
		(settings_panel.get_node("SafeArea/Layout/PageFrame") as PanelContainer).get_theme_stylebox(
			&"panel"
		) as StyleBoxFlat,
	]
	for style: StyleBoxFlat in styles:
		assert_object(style).is_not_null()
		if style == null:
			continue
		assert_bool(style.anti_aliasing).is_true()
		assert_float(style.anti_aliasing_size).is_equal_approx(1.25, 0.001)
		assert_bool(style.border_blend).is_true()
		assert_int(style.border_width_left).is_equal(2)
		assert_int(style.corner_radius_top_left).is_equal(6)
		assert_int(style.corner_detail).is_greater_equal(12)
