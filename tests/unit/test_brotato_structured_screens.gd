extends GdUnitTestSuite


const STAT_LIST_PATH := "res://game/ui/stat_list_presenter.gd"
const LOADOUT_STRIP_PATH := "res://game/ui/loadout_strip_presenter.gd"
const HUD_SKIN_PATH := "res://game/ui/hud_skin.gd"
const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const PAUSE_OVERLAY := preload("res://game/ui/pause_overlay.gd")
const UPGRADE_SCREEN := preload("res://game/ui/upgrade_screen.gd")
const NATIVE_CAPTURE_RECT := Rect2(0, 0, 1280, 720)
const NIKO_ID := NikoContentFactory.CHARACTER_ID


func test_base_chrome_exposes_native_safe_content_without_a_viewport_frame() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	assert_bool(screen.has_method(&"build_screen_chrome")).is_true()
	if not screen.has_method(&"build_screen_chrome"):
		return
	var content_root := screen.call(&"build_screen_chrome", "军备整备", "第 2 波") as Control
	assert_object(content_root).is_same(screen.get_node("ContentRoot"))
	assert_int(screen.find_children("StaticNineSlicePanel", "*", true, false).size()).is_equal(0)
	assert_bool(content_root.position.is_equal_approx(Vector2(32, 100))).is_true()
	assert_bool(content_root.size.is_equal_approx(Vector2(1216, 588))).is_true()
	var title_band := screen.get_node("TitleBand") as Control
	assert_bool(title_band.position.is_equal_approx(Vector2(32, 20))).is_true()
	assert_bool(title_band.size.is_equal_approx(Vector2(1216, 64))).is_true()
	assert_str((title_band.get_node("Title") as Label).text).is_equal("军备整备")
	assert_str((title_band.get_node("Subtitle") as Label).text).is_equal("第 2 波")
	assert_int(
		(screen.get_node("StaticMenuBackground") as TextureRect).texture_filter
	).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)


func test_screen_chrome_keeps_explicit_background_readability_and_content_layers() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	screen.build_screen_chrome("分层界面", "背景不抢正文")
	await get_tree().process_frame

	var layer_names := [
		"FlatMenuFallback",
		"StaticMenuBackground",
		"ReadabilityVeil",
		"TitleBand",
		"ContentRoot",
	]
	for expected_index in layer_names.size():
		var layer := screen.get_node_or_null(layer_names[expected_index]) as Control
		assert_object(layer).is_not_null()
		if layer != null:
			assert_int(layer.get_index()).is_equal(expected_index)

	var background := screen.get_node("StaticMenuBackground") as TextureRect
	var veil := screen.get_node("ReadabilityVeil") as ColorRect
	assert_bool(background.get_rect().is_equal_approx(NATIVE_CAPTURE_RECT)).is_true()
	assert_bool(veil.get_rect().is_equal_approx(NATIVE_CAPTURE_RECT)).is_true()
	assert_bool(veil.color.a > 0.0 and veil.color.a < 1.0).is_true()
	assert_int(background.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(veil.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((screen.get_node("ContentRoot") as Control).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)


func test_build_screen_compatibility_wrapper_uses_the_unframed_content_root() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	var body := screen.build_screen("兼容页面")
	assert_bool(screen.has_node("ContentRoot/Body")).is_true()
	if not screen.has_node("ContentRoot/Body"):
		return
	assert_object(body).is_same(screen.get_node("ContentRoot/Body"))
	assert_int(screen.find_children("StaticNineSlicePanel", "*", true, false).size()).is_equal(0)
	assert_bool(body.position.is_equal_approx(Vector2.ZERO)).is_true()
	assert_bool(body.size.is_equal_approx(Vector2(1216, 588))).is_true()
	assert_int(body.get_theme_constant(&"separation")).is_equal(8)
	assert_int(body.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_legacy_weapon_and_shop_stacks_fit_the_native_content_height() -> void:
	var definition := GogoItemDefinition.new()
	definition.content_id = &"fixture:item/compact_card"
	definition.display_name = "紧凑卡片"
	definition.stat_modifiers = {&"max_health": 2.0}

	var weapon_screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	weapon_screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(weapon_screen)
	weapon_screen.build_screen("旧武器页")
	var weapon_grid := GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.add_theme_constant_override(&"v_separation", 8)
	weapon_screen.body.add_child(weapon_grid)
	for index in 12:
		weapon_screen.add_static_card(
			definition,
			"武器 %d" % index,
			Callable(),
			false,
			weapon_grid
		)
	weapon_screen.add_action("返回", Callable())

	var shop_screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	shop_screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(shop_screen)
	shop_screen.build_screen("旧商店页")
	shop_screen.add_info("")
	for index in 4:
		var row := HBoxContainer.new()
		shop_screen.body.add_child(row)
		shop_screen.add_static_card(
			definition,
			"%d 金币" % (index + 1),
			Callable(),
			false,
			row
		)
		var lock := Button.new()
		shop_screen.configure_action_button(lock, "锁定")
		row.add_child(lock)
	for label in ["刷新商店", "出售武器", "合成武器", "进入下一波"]:
		shop_screen.add_action(label, Callable())

	await get_tree().process_frame
	assert_bool(
		weapon_screen.body.get_combined_minimum_size().y <= weapon_screen.content_root.size.y
	).is_true()
	for button: Button in shop_screen.find_children("*", "Button", true, false):
		assert_float(button.custom_minimum_size.y).is_greater_equal(56.0)
		assert_bool(button.get_node_or_null("ButtonFill") == null).is_true()


func test_principal_surface_is_opt_in_and_uses_only_the_requested_rect() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	assert_bool(screen.has_method(&"add_principal_surface")).is_true()
	if not screen.has_method(&"add_principal_surface"):
		return
	screen.call(&"build_screen_chrome", "确认")
	var surface := screen.call(
		&"add_principal_surface",
		Rect2(160, 132, 640, 360)
	) as Control
	assert_object(surface).is_same(screen.get_node("PrincipalSurface"))
	assert_bool(surface.position.is_equal_approx(Vector2(160, 132))).is_true()
	assert_bool(surface.size.is_equal_approx(Vector2(640, 360))).is_true()
	assert_bool(surface.size.x < 1280.0 and surface.size.y < 720.0).is_true()
	assert_int(surface.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_int(screen.content_root.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(surface.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)


func test_principal_surface_child_receives_a_real_pointer_click_through_content_root() -> void:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(1280, 720)
	viewport.gui_disable_input = false
	add_child(viewport)
	var screen := GogoScreenBase.new()
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	viewport.add_child(screen)
	screen.build_screen("交互表面")
	var surface := screen.add_principal_surface(Rect2(160, 132, 640, 360))
	var button := Button.new()
	button.name = "SurfaceAction"
	button.text = "确认"
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.add_child(button)
	var presses: Array[bool] = []
	button.pressed.connect(func() -> void: presses.append(true))
	var content_button := Button.new()
	content_button.name = "ContentAction"
	content_button.position = Vector2(850, 40)
	content_button.size = Vector2(120, 50)
	content_button.text = "内容按钮"
	screen.content_root.add_child(content_button)
	var content_presses: Array[bool] = []
	content_button.pressed.connect(func() -> void: content_presses.append(true))

	await get_tree().process_frame
	await _push_pointer_click(viewport, Vector2(220, 180))
	await _push_pointer_click(viewport, Vector2(900, 165))
	assert_int(presses.size()).is_equal(1)
	assert_int(content_presses.size()).is_equal(1)


func test_shared_button_skin_uses_one_flat_surface_without_a_second_fill() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	screen.build_screen("按钮")
	var button := screen.add_action("继续", func() -> void: pass)
	var normal := button.get_theme_stylebox(&"normal")
	assert_bool(normal is StyleBoxFlat).is_true()
	if not normal is StyleBoxFlat:
		return
	var flat_style := normal as StyleBoxFlat
	assert_bool(flat_style.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL)).is_true()
	assert_bool(flat_style.border_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_BORDER)).is_true()
	assert_int(flat_style.border_width_left).is_equal(1)
	assert_float(flat_style.content_margin_top).is_greater_equal(8.0)
	assert_float(flat_style.content_margin_bottom).is_greater_equal(8.0)
	assert_float(button.custom_minimum_size.y).is_greater_equal(56.0)
	assert_bool(button.get_node_or_null("ButtonFill") == null).is_true()


func test_hud_skin_exposes_complete_components_and_button_height_tokens() -> void:
	assert_bool(FileAccess.file_exists(HUD_SKIN_PATH)).is_true()
	for texture: Texture2D in [
		HUD_SKIN.BUTTON_NORMAL,
		HUD_SKIN.BUTTON_FOCUS,
		HUD_SKIN.BUTTON_PRESSED,
		HUD_SKIN.BUTTON_DISABLED,
		HUD_SKIN.SURFACE_TEXTURE,
		HUD_SKIN.DIALOG_TEXTURE,
		HUD_SKIN.SHOP_CARD_TEXTURE,
		HUD_SKIN.SLOT_TEXTURE,
	]:
		assert_object(texture).is_not_null()

	var variants := [
		{&"name": &"compact", &"height": HUD_SKIN.BUTTON_HEIGHT_COMPACT},
		{&"name": &"standard", &"height": HUD_SKIN.BUTTON_HEIGHT_STANDARD},
		{&"name": &"primary", &"height": HUD_SKIN.BUTTON_HEIGHT_PRIMARY},
	]
	var state_colors := {
		&"normal": HUD_SKIN.COLOR_CONTROL,
		&"hover": HUD_SKIN.COLOR_CONTROL_FOCUS,
		&"focus": HUD_SKIN.COLOR_CONTROL_FOCUS,
		&"pressed": HUD_SKIN.COLOR_CONTROL_PRESSED,
		&"disabled": HUD_SKIN.COLOR_CONTROL_DISABLED,
	}
	var buttons: Array[Button] = []
	for spec: Dictionary in variants:
		var button := auto_free(Button.new()) as Button
		button.name = "HudSkin%sButton" % String(spec[&"name"]).capitalize()
		var legacy_fill := ColorRect.new()
		legacy_fill.name = "ButtonFill"
		button.add_child(legacy_fill)
		add_child(button)
		HUD_SKIN.apply_action_button(button, spec[&"name"] as StringName)
		buttons.append(button)
		assert_float(button.custom_minimum_size.y).is_equal(float(spec[&"height"]))
		assert_int(button.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_bool(button.clip_text).is_true()
		assert_int(button.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		for state: StringName in state_colors:
			var style := button.get_theme_stylebox(state)
			assert_bool(style is StyleBoxFlat).is_true()
			if style is StyleBoxFlat:
				var flat_style := style as StyleBoxFlat
				assert_bool(flat_style.bg_color.is_equal_approx(state_colors[state])).is_true()
				assert_int(flat_style.border_width_left).is_equal(1)
				assert_int(flat_style.border_width_top).is_equal(1)
				assert_float(flat_style.content_margin_top).is_greater_equal(8.0)
				assert_float(flat_style.content_margin_bottom).is_greater_equal(8.0)

	await get_tree().process_frame
	for button in buttons:
		assert_bool(button.get_node_or_null("ButtonFill") == null).is_true()


func test_hud_skin_limits_authored_textures_to_semantic_opt_ins() -> void:
	var authored_button := auto_free(Button.new()) as Button
	HUD_SKIN.apply_action_button(authored_button, &"primary", false, true)
	_assert_authored_button_states(authored_button)

	var surface := auto_free(Panel.new()) as Panel
	var dialog := auto_free(Panel.new()) as Panel
	var soft := auto_free(Panel.new()) as Panel
	var stats := auto_free(Panel.new()) as Panel
	HUD_SKIN.apply_panel(surface, &"surface")
	HUD_SKIN.apply_panel(dialog, &"dialog")
	HUD_SKIN.apply_panel(soft, &"soft")
	HUD_SKIN.apply_panel(stats, &"stats")
	_assert_authored_texture_style(
		surface.get_theme_stylebox(&"panel"),
		HUD_SKIN.SURFACE_TEXTURE,
		HUD_SKIN.PANEL_PATCH_MARGIN,
		0.0,
		0.0
	)
	_assert_authored_texture_style(
		dialog.get_theme_stylebox(&"panel"),
		HUD_SKIN.DIALOG_TEXTURE,
		HUD_SKIN.DIALOG_PATCH_MARGIN,
		0.0,
		0.0
	)
	assert_bool(soft.get_theme_stylebox(&"panel") is StyleBoxFlat).is_true()
	assert_bool(stats.get_theme_stylebox(&"panel") is StyleBoxFlat).is_true()

	var compact_card := auto_free(Button.new()) as Button
	var shop_card := auto_free(Button.new()) as Button
	var selected_shop_card := auto_free(Button.new()) as Button
	HUD_SKIN.apply_card(compact_card)
	HUD_SKIN.apply_card(shop_card, false, true)
	HUD_SKIN.apply_card(selected_shop_card, true, true)
	assert_bool(compact_card.get_theme_stylebox(&"normal") is StyleBoxFlat).is_true()
	_assert_authored_texture_style(
		shop_card.get_theme_stylebox(&"normal"),
		HUD_SKIN.SHOP_CARD_TEXTURE,
		HUD_SKIN.SHOP_CARD_PATCH_MARGIN,
		12.0,
		12.0
	)
	assert_bool(shop_card.get_theme_stylebox(&"focus") is StyleBoxFlat).is_true()
	assert_bool(selected_shop_card.get_theme_stylebox(&"normal") is StyleBoxFlat).is_true()

	var empty_slot := auto_free(Button.new()) as Button
	var occupied_slot := auto_free(Button.new()) as Button
	var selected_slot := auto_free(Button.new()) as Button
	HUD_SKIN.apply_slot(empty_slot)
	HUD_SKIN.apply_slot(occupied_slot, false, true)
	HUD_SKIN.apply_slot(selected_slot, true, true)
	assert_bool(empty_slot.get_theme_stylebox(&"normal") is StyleBoxFlat).is_true()
	_assert_authored_texture_style(
		occupied_slot.get_theme_stylebox(&"normal"),
		HUD_SKIN.SLOT_TEXTURE,
		HUD_SKIN.SLOT_PATCH_MARGIN,
		8.0,
		8.0
	)
	assert_bool(occupied_slot.get_theme_stylebox(&"focus") is StyleBoxFlat).is_true()
	assert_bool(selected_slot.get_theme_stylebox(&"normal") is StyleBoxFlat).is_true()


func test_card_has_one_hard_outline_one_rarity_strip_and_localized_rows() -> void:
	var item := GogoItemDefinition.new()
	item.content_id = &"fixture:item/medical_kit"
	item.display_name = "战术急救包"
	item.tier = 3
	item.stat_modifiers = {
		&"max_health": 2.0,
		&"movement_speed": -5.0,
		&"damage_multiplier": 0.08,
	}
	var card := auto_free(GogoStaticCardPresenter.build_card(
		item,
		"12 金币",
		_empty_static_snapshot()
	)) as Button
	var accents := card.find_children("RarityAccent", "ColorRect", true, false)
	assert_int(accents.size()).is_equal(1)
	if accents.size() != 1:
		return
	assert_bool(not card.has_node("Frame")).is_true()
	var normal := card.get_theme_stylebox(&"normal")
	assert_bool(normal is StyleBoxFlat).is_true()
	if not normal is StyleBoxFlat:
		return
	var card_style := normal as StyleBoxFlat
	assert_bool(card_style.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL)).is_true()
	assert_bool(card_style.border_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_BORDER)).is_true()
	assert_int(card_style.border_width_left).is_equal(1)
	assert_bool((accents[0] as ColorRect).color.is_equal_approx(Color("c65ce2"))).is_true()
	var icon := card.get_node("Icon") as TextureRect
	assert_bool(icon.size.is_equal_approx(Vector2(64, 64))).is_true()
	assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_int((card.get_node("Name") as Label).get_theme_font_size("font_size")).is_equal(18)
	var stat_rows := card.get_node("StatRows") as VBoxContainer
	assert_int(stat_rows.get_child_count()).is_equal(2)
	assert_str((stat_rows.get_node("Stat1/Text") as Label).text).is_equal("最大生命 +2")
	assert_str((stat_rows.get_node("Stat2/Text") as Label).text).is_equal("移动速度 -5")
	assert_bool((stat_rows.get_node("Stat1/Text") as Label).text.contains("max_health")).is_false()
	assert_bool((stat_rows.get_node("Stat2/Text") as Label).text.contains("movement_speed")).is_false()
	for stat_row in stat_rows.get_children():
		var effect_icon := (stat_row as HBoxContainer).get_node("Icon") as TextureRect
		assert_object(effect_icon.texture).is_not_null()
		assert_int(effect_icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_str((card.get_node("PriceOrState") as Label).text).is_equal("12 金币")
	assert_bool(card.custom_minimum_size.y <= 76.0).is_true()
	assert_bool(
		4.0 * card.custom_minimum_size.x + 3.0 * 8.0 + 265.0 + 16.0 <= 1216.0
	).is_true()
	add_child(card)
	card.size = card.custom_minimum_size
	await get_tree().process_frame
	var name_label := card.get_node("Name") as Label
	var price_label := card.get_node("PriceOrState") as Label
	assert_bool(name_label.position.x + name_label.size.x <= price_label.position.x).is_true()
	assert_bool(price_label.position.x + price_label.size.x <= card.size.x).is_true()


func test_card_compacts_three_stats_to_primary_positive_and_visible_negative() -> void:
	var item := GogoItemDefinition.new()
	item.content_id = &"fixture:item/tradeoff"
	item.display_name = "带代价的配件"
	item.tier = 2
	item.set_meta(&"description", "磨损但可靠的实体配件。")
	item.set_meta(&"flavor", "多拿一项，也多付一项。")
	item.stat_modifiers = {
		&"max_health": 2.0,
		&"damage_multiplier": 0.08,
		&"critical_chance": -0.12,
	}
	var rows := GogoStaticCardPresenter.localized_stat_rows(item)
	assert_int(rows.size()).is_equal(2)
	assert_str(String(rows[0].get("text", ""))).is_equal("最大生命 +2")
	assert_float(float(rows[0].get("amount", 0.0))).is_equal(2.0)
	assert_str(String(rows[0].get("stat_key", &""))).is_equal("max_health")
	assert_str(String(rows[1].get("text", ""))).is_equal("暴击率 -12%")
	assert_float(float(rows[1].get("amount", 0.0))).is_equal_approx(-0.12, 0.0001)
	assert_str(String(rows[1].get("stat_key", &""))).is_equal("critical_chance")

	var card := auto_free(GogoStaticCardPresenter.build_card(
		item,
		"14 金币",
		_empty_static_snapshot()
	)) as Button
	var negative_label := card.get_node("StatRows/Stat2/Text") as Label
	assert_str(negative_label.text).is_equal("暴击率 -12%")
	assert_bool(
		negative_label.get_theme_color("font_color").is_equal_approx(Color("ef6a67"))
	).is_true()
	assert_str(card.tooltip_text).contains("磨损但可靠的实体配件。")
	assert_str(card.tooltip_text).contains("多拿一项，也多付一项。")
	assert_str(card.tooltip_text).contains("伤害 +8%")
	assert_str(card.tooltip_text).contains("暴击率 -12%")
	assert_bool(card.custom_minimum_size.is_equal_approx(Vector2(216, 76))).is_true()


func test_card_keeps_first_two_rows_when_no_tradeoff_is_hidden() -> void:
	var two_stat_item := GogoItemDefinition.new()
	two_stat_item.content_id = &"fixture:item/two_stats"
	two_stat_item.display_name = "双属性配件"
	two_stat_item.stat_modifiers = {
		&"max_health": 3.0,
		&"damage_multiplier": 0.05,
	}
	var two_rows := GogoStaticCardPresenter.localized_stat_rows(two_stat_item)
	assert_int(two_rows.size()).is_equal(2)
	assert_str(String(two_rows[0].get("text", ""))).is_equal("最大生命 +3")
	assert_str(String(two_rows[1].get("text", ""))).is_equal("伤害 +5%")

	var positive_only_item := GogoItemDefinition.new()
	positive_only_item.content_id = &"fixture:item/positive_only"
	positive_only_item.display_name = "纯增益配件"
	positive_only_item.stat_modifiers = {
		&"max_health": 3.0,
		&"damage_multiplier": 0.05,
		&"armor": 2.0,
	}
	var positive_rows := GogoStaticCardPresenter.localized_stat_rows(positive_only_item)
	assert_int(positive_rows.size()).is_equal(2)
	assert_str(String(positive_rows[0].get("text", ""))).is_equal("最大生命 +3")
	assert_str(String(positive_rows[1].get("text", ""))).is_equal("伤害 +5%")


func test_card_missing_icon_keeps_a_readable_interactive_fallback() -> void:
	var item := GogoItemDefinition.new()
	item.content_id = &"fixture:item/no_icon"
	item.display_name = "备用止痛针"
	item.tier = 2
	var card := auto_free(GogoStaticCardPresenter.build_card(
		item,
		"已装备",
		_empty_static_snapshot()
	)) as Button
	assert_bool(card.focus_mode == Control.FOCUS_ALL).is_true()
	assert_bool(card.mouse_filter == Control.MOUSE_FILTER_STOP).is_true()
	assert_object((card.get_node("Icon") as TextureRect).texture).is_null()
	assert_bool(card.has_node("IconFallback/Label")).is_true()
	if not card.has_node("IconFallback/Label"):
		return
	assert_bool((card.get_node("IconFallback") as ColorRect).visible).is_true()
	assert_str((card.get_node("IconFallback/Label") as Label).text).is_equal("无图")
	assert_str((card.get_node("Name") as Label).text).is_equal("备用止痛针")


func test_shop_cards_show_explicit_weapon_and_item_type_badges() -> void:
	var weapon := GogoWeaponDefinition.new()
	weapon.content_id = &"fixture:weapon/type_badge"
	weapon.display_name = "蝴蝶刀"
	var weapon_card := auto_free(GogoStaticCardPresenter.build_card(
		weapon,
		"12 金币",
		_empty_static_snapshot(),
		&"shop_offer"
	)) as Button
	var weapon_badge := weapon_card.get_node("TypeBadge") as Label
	assert_bool(weapon_badge.visible).is_true()
	assert_bool(weapon_badge.text.begins_with("武器 · ")).is_true()
	assert_str(String(weapon_card.get_meta(&"content_kind", &""))).is_equal("weapon")

	var item := GogoItemDefinition.new()
	item.content_id = &"fixture:item/type_badge"
	item.display_name = "战术急救包"
	var item_card := auto_free(GogoStaticCardPresenter.build_card(
		item,
		"10 金币",
		_empty_static_snapshot(),
		&"shop_offer"
	)) as Button
	var item_badge := item_card.get_node("TypeBadge") as Label
	assert_bool(item_badge.visible).is_true()
	assert_str(item_badge.text).is_equal("道具")
	assert_str(String(item_card.get_meta(&"content_kind", &""))).is_equal("item")


func test_stat_list_localizes_canonical_keys_and_colors_real_deltas() -> void:
	assert_bool(FileAccess.file_exists(STAT_LIST_PATH)).is_true()
	if not FileAccess.file_exists(STAT_LIST_PATH):
		return
	var player := SessionPlayerState.new()
	player.base_stats = {
		&"max_health": 20.0,
		&"damage_multiplier": 1.0,
		&"armor": 0.0,
		&"movement_speed": 235.0,
	}
	player.final_stats = {
		&"max_health": 24.0,
		&"damage_multiplier": 1.12,
		&"armor": -2.0,
		&"movement_speed": 250.0,
	}
	var presenter := load(STAT_LIST_PATH) as GDScript
	var rows := auto_free(presenter.build(player, ContentSnapshot.new())) as VBoxContainer
	assert_int(rows.get_child_count()).is_equal(4)
	for row in rows.get_children():
		assert_object((row as HBoxContainer).get_node("Icon") as TextureRect).is_not_null()
		assert_object(((row as HBoxContainer).get_node("Icon") as TextureRect).texture).is_not_null()
	assert_str((rows.get_node("MaxHealth/Name") as Label).text).is_equal("最大生命")
	assert_str((rows.get_node("MaxHealth/Value") as Label).text).is_equal("24")
	assert_str((rows.get_node("DamageMultiplier/Name") as Label).text).is_equal("伤害")
	assert_str((rows.get_node("DamageMultiplier/Value") as Label).text).is_equal("+12%")
	assert_str((rows.get_node("Armor/Value") as Label).text).is_equal("-2")
	assert_bool(
		(rows.get_node("MaxHealth/Value") as Label).get_theme_color("font_color").is_equal_approx(
			Color("72d572")
		)
	).is_true()
	assert_bool(
		(rows.get_node("Armor/Value") as Label).get_theme_color("font_color").is_equal_approx(
			Color("ef6a67")
		)
	).is_true()
	assert_int(rows.find_children("*", "PanelContainer", true, false).size()).is_equal(0)


func test_stat_list_compares_new_additive_stats_against_zero() -> void:
	var player := SessionPlayerState.new()
	player.base_stats = {}
	player.final_stats = {
		&"ranged_damage": 3.0,
		&"armor": -2.0,
	}
	var rows := auto_free(STAT_LIST_PRESENTER.build(
		player,
		ContentSnapshot.new()
	)) as VBoxContainer
	assert_bool(
		(rows.get_node("RangedDamage/Value") as Label).get_theme_color("font_color").is_equal_approx(
			Color("72d572")
		)
	).is_true()
	assert_bool(
		(rows.get_node("Armor/Value") as Label).get_theme_color("font_color").is_equal_approx(
			Color("ef6a67")
		)
	).is_true()


func test_stat_list_shows_brotato_style_final_percent_without_internal_multiplier_rows() -> void:
	var player := SessionPlayerState.new()
	player.base_stats = {
		&"movement_speed": 250.0,
		&"attack_speed": 1.0,
	}
	player.final_stats = {
		&"movement_speed": 275.0,
		&"movement_speed_multiplier": 0.1,
		&"attack_speed": 1.2,
		&"attack_speed_multiplier": 0.2,
	}
	var rows := auto_free(STAT_LIST_PRESENTER.build(
		player,
		ContentSnapshot.new()
	)) as VBoxContainer
	assert_str((rows.get_node("MovementSpeed/Name") as Label).text).is_equal("移动速度")
	assert_str((rows.get_node("MovementSpeed/Value") as Label).text).is_equal("+10%")
	assert_str((rows.get_node("AttackSpeed/Name") as Label).text).is_equal("攻击速度")
	assert_str((rows.get_node("AttackSpeed/Value") as Label).text).is_equal("+20%")
	assert_bool(rows.has_node("MovementSpeedMultiplier")).is_false()
	assert_bool(rows.has_node("AttackSpeedMultiplier")).is_false()


func test_loadout_has_owned_slots_nearest_icons_fallbacks_and_selection_only() -> void:
	assert_bool(FileAccess.file_exists(LOADOUT_STRIP_PATH)).is_true()
	if not FileAccess.file_exists(LOADOUT_STRIP_PATH):
		return
	var content := _loadout_content()
	var player := SessionPlayerState.new()
	for id in [&"fixture:weapon/ak", &"fixture:weapon/knife"]: player.weapon_inventory.add_weapon(id, content)
	for index in 12:
		player.item_ids.append(StringName("fixture:item/%02d" % index))
	var selected_slots: Array[int] = []
	var actions := {
		"selected_weapon_instance_id": 2,
		"select": func(slot: int) -> void: selected_slots.append(slot),
	}
	var presenter := load(LOADOUT_STRIP_PATH) as GDScript
	var strip := auto_free(presenter.build(
		player,
		content,
		_loadout_static_snapshot(),
		actions
	)) as Control
	var weapons := strip.get_node("Weapons") as HBoxContainer
	assert_int(weapons.get_child_count()).is_equal(2)
	for slot_index in 2:
		var slot := weapons.get_child(slot_index) as Button
		assert_bool(slot.custom_minimum_size.is_equal_approx(Vector2(72, 72))).is_true()
	assert_int(
		(weapons.get_node("WeaponSlot0/Icon") as TextureRect).texture_filter
	).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_object((weapons.get_node("WeaponSlot0/Icon") as TextureRect).texture).is_not_null()
	assert_str(
		(weapons.get_node("WeaponSlot1/FallbackLabel") as Label).text
	).is_equal("爪子刀")
	assert_bool(weapons.get_node("WeaponSlot1").has_node("Actions")).is_false()
	assert_bool(weapons.get_node("WeaponSlot0").has_node("Actions")).is_false()
	var occupied_normal := (
		(weapons.get_node("WeaponSlot0") as Button).get_theme_stylebox(&"normal")
		as StyleBoxTexture
	)
	assert_object(occupied_normal).is_not_null()
	if occupied_normal != null:
		assert_object(occupied_normal.texture).is_same(HUD_SKIN.SLOT_TEXTURE)
	assert_bool(
		(weapons.get_node("WeaponSlot0") as Button).get_theme_stylebox(&"focus")
		is StyleBoxFlat
	).is_true()
	assert_bool(
		(weapons.get_node("WeaponSlot1") as Button).get_theme_stylebox(&"normal")
		is StyleBoxFlat
	).is_true()
	(weapons.get_node("WeaponSlot0") as Button).pressed.emit()
	assert_array(selected_slots).is_equal([1])
	assert_bool(weapons.has_node("WeaponSlot2")).is_false()
	var items := strip.get_node("Items") as HBoxContainer
	assert_int(items.find_children("ItemIcon*", "Control", false, false).size()).is_equal(8)
	assert_str((items.get_node("Overflow") as Label).text).is_equal("+4")
	assert_bool(
		(items.get_node("ItemIcon0") as Control).custom_minimum_size.is_equal_approx(Vector2(48, 48))
	).is_true()


func test_loadout_renders_only_owned_weapons_in_both_presentations() -> void:
	for expanded in [false, true]:
		for count in [0, 1, 3, 6]:
			var player := SessionPlayerState.new()
			for index in count:
				player.weapon_inventory.add_weapon(&"fixture:weapon/ak", _loadout_content())
			var strip := auto_free(GogoLoadoutStripPresenter.build(
				player,
				_loadout_content(),
				_loadout_static_snapshot(),
				{"expanded": expanded}
			)) as Control
			var weapons := strip.get_node("Weapons") as HBoxContainer
			assert_int(weapons.find_children("WeaponSlot*", "Button", false, false).size()).is_equal(count)
			assert_bool(weapons.has_node("WeaponSlot%d" % count)).is_false()
			assert_bool(weapons.has_node("EmptyWeapons")).is_equal(count == 0)
			if count == 0:
				var empty := weapons.get_node_or_null("EmptyWeapons") as Label
				if empty != null:
					assert_str(empty.text).is_equal("尚未装备武器")
			for index in count:
				var slot := weapons.get_node("WeaponSlot%d" % index) as Button
				assert_int(slot.get_meta(&"slot_index")).is_equal(index)
				assert_str(String(slot.get_meta(&"content_id"))).is_equal("fixture:weapon/ak")
				assert_bool(slot.disabled).is_false()


func test_character_setup_has_exactly_one_real_niko_cell_and_first_frame_detail() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := fixture.host.get_child(0) as GogoScreenBase
	var required_paths: Array[NodePath] = [
		^"BackButton",
		^"NikoDetail",
		^"NikoDetail/Preview",
		^"NikoDetail/Name",
		^"NikoDetail/Traits",
		^"NikoDetail/SectionTitle",
		^"RosterCaption",
		^"RosterStrip",
		^"RosterStrip/NikoCell",
		^"RosterStrip/NikoCell/Name",
		^"RosterStrip/UnavailableCharacterSlot01",
		^"RosterStrip/UnavailableCharacterSlot23",
		^"ChangeCharacterButton",
	]
	for path in required_paths:
		assert_object(screen.get_node_or_null(path)).is_not_null()
	var roster := screen.get_node_or_null("RosterStrip") as GridContainer
	if roster == null:
		return
	assert_int(roster.columns).is_equal(6)
	assert_int(roster.get_child_count()).is_equal(24)
	var niko_cell := roster.get_node("NikoCell") as Button
	assert_str(String(niko_cell.get_meta(&"content_id", &""))).is_equal(String(NIKO_ID))
	assert_bool(niko_cell.focus_mode == Control.FOCUS_ALL).is_true()
	assert_bool(niko_cell.custom_minimum_size.is_equal_approx(Vector2(143, 116))).is_true()
	var draft_before := app.selection_draft.duplicate(true)
	var unavailable_count := 0
	for child in roster.get_children():
		var slot := child as Button
		assert_bool(_fits_native_capture(slot)).is_true()
		if slot == niko_cell:
			continue
		unavailable_count += 1
		assert_str(String(slot.name)).starts_with("UnavailableCharacterSlot")
		assert_str(slot.text).is_equal("未开放")
		assert_bool(slot.disabled).is_true()
		assert_int(slot.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(slot.has_meta(&"content_id")).is_false()
		assert_bool(slot.has_meta(&"definition")).is_false()
		assert_bool(slot.has_meta(&"character_definition")).is_false()
		assert_int(slot.get_signal_connection_list(&"pressed").size()).is_equal(0)
		slot.pressed.emit()
	assert_int(unavailable_count).is_equal(23)
	assert_dict(app.selection_draft).is_equal(draft_before)
	assert_object(app.current_session).is_null()
	var preview := screen.get_node("NikoDetail/Preview") as TextureRect
	var niko := app.content_snapshot.definition(NIKO_ID, &"character") as CharacterDefinition
	var source_frame := niko.sprite_frames.get_frame_texture(niko.default_animation, 0)
	assert_bool(preview.texture is AtlasTexture).is_true()
	if preview.texture is AtlasTexture:
		var cropped_preview := preview.texture as AtlasTexture
		assert_object(cropped_preview.atlas).is_same(source_frame)
		assert_bool(cropped_preview.region.size.x < source_frame.get_width()).is_true()
		assert_bool(cropped_preview.region.size.y < source_frame.get_height()).is_true()
	assert_int(preview.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_str((screen.get_node("NikoDetail/Name") as Label).text).is_equal("Niko")
	var traits_text := (screen.get_node("NikoDetail/Traits") as Label).text
	assert_str(traits_text).starts_with("初始生命")
	assert_bool(
		traits_text.contains("标签")
		or traits_text.contains("niko")
		or traits_text.contains("balanced")
		or traits_text.contains("均衡型")
	).is_false()
	assert_int(screen.find_children("*", "PanelContainer", true, false).size()).is_equal(0)
	assert_bool(
		(screen.get_node("RosterStrip") as Control).get_rect().is_equal_approx(
			Rect2(348, 140, 900, 488)
		)
	).is_true()
	assert_bool(
		(screen.get_node("NikoDetail") as Control).get_rect().is_equal_approx(
			Rect2(32, 104, 300, 510)
		)
	).is_true()
	var change := screen.get_node("ChangeCharacterButton") as Button
	assert_bool(change.visible).is_false()
	assert_bool(change.get_rect().is_equal_approx(Rect2(32, 648, 300, 56))).is_true()
	_assert_authored_button_states(change)
	assert_bool(_fits_native_capture(screen.get_node("NikoDetail") as Control)).is_true()
	assert_bool(_fits_native_capture(screen.get_node("RosterCaption") as Control)).is_true()
	assert_bool(_fits_native_capture(roster)).is_true()
	assert_bool(_fits_native_capture(change)).is_true()


func test_character_setup_uses_one_whole_light_selected_niko_focus() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	app.selection_draft["character_id"] = NIKO_ID
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := fixture.host.get_child(0) as GogoScreenBase
	var cell := screen.get_node("RosterStrip/NikoCell") as Button
	assert_bool(cell.get_meta(&"selected", false) as bool).is_true()
	var normal := cell.get_theme_stylebox(&"normal")
	assert_bool(normal is StyleBoxFlat).is_true()
	if normal is StyleBoxFlat:
		var selected_style := normal as StyleBoxFlat
		assert_bool(selected_style.bg_color.get_luminance() > 0.70).is_true()
		assert_bool(selected_style.border_color.is_equal_approx(HUD_SKIN.COLOR_FOCUS)).is_true()
		assert_int(selected_style.border_width_left).is_equal(3)
		assert_int(selected_style.border_width_top).is_equal(3)
		assert_int(selected_style.border_width_right).is_equal(3)
		assert_int(selected_style.border_width_bottom).is_equal(3)
	assert_bool(
		cell.get_theme_color(&"font_color").is_equal_approx(HUD_SKIN.COLOR_TEXT_FOCUS)
	).is_true()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool(cell.visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	var change := screen.get_node("ChangeCharacterButton") as Button
	assert_bool(change.visible).is_true()
	assert_str(change.text).is_equal("Niko · 更换角色")
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_object(focus).is_not_null()
	if focus != null:
		assert_bool(focus.is_visible_in_tree()).is_true()
		assert_int(focus.focus_mode).is_not_equal(Control.FOCUS_NONE)
		assert_bool(focus != cell).is_true()


func test_setup_focus_previews_without_committing_and_clicks_commit_on_same_page() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Node
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := host.get_child(0) as GogoScreenBase
	var niko_cell := screen.get_node("RosterStrip/NikoCell") as Button
	assert_bool(niko_cell.get_meta(&"selected", false) as bool).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko_cell)
	assert_str(String(app.selection_draft.get("character_id", &""))).is_empty()
	niko_cell.pressed.emit()
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_str(String(app.selection_draft.get("character_id", &""))).is_equal(String(NIKO_ID))
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_bool((screen.get_node("ChangeCharacterButton") as Button).visible).is_true()
	var strip := screen.get_node("WeaponStage/WeaponColumns") as HBoxContainer
	var selected_count := 0
	for option in strip.find_children("WeaponOption*", "Button", true, false):
		if (option as Button).get_meta(&"selected", false) as bool:
			selected_count += 1
	assert_int(selected_count).is_equal(0)
	var weapon := strip.get_node("Class4/WeaponOption11") as Button
	weapon.grab_focus()
	await _settle_ui()
	assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Name") as Label).text).is_equal("AWP")
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_empty()
	weapon.pressed.emit()
	await _settle_ui()
	assert_bool(weapon.get_meta(&"selected", false) as bool).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_true()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_object(app.current_session).is_null()


func test_weapon_setup_uses_all_twelve_canonical_cs_options_and_complete_selected_detail() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	app.selection_draft["character_id"] = NIKO_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	assert_int(app.route(FlowRoute.WEAPON_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := fixture.host.get_child(0) as GogoScreenBase
	for path in [
		^"BackButton",
		^"NikoDetail",
		^"WeaponStage/SelectedWeaponDetail",
		^"WeaponStage/SelectedWeaponDetail/Icon",
		^"WeaponStage/SelectedWeaponDetail/Name",
		^"WeaponStage/SelectedWeaponDetail/Mode",
		^"WeaponStage/SelectedWeaponDetail/Damage",
		^"WeaponStage/SelectedWeaponDetail/Cooldown",
		^"WeaponStage/SelectedWeaponDetail/Modifiers",
		^"WeaponStage/WeaponColumns",
	]:
		assert_object(screen.get_node_or_null(path)).is_not_null()
	var strip := screen.get_node_or_null("WeaponStage/WeaponColumns") as HBoxContainer
	if strip == null:
		return
	var definitions := app.content_snapshot.all(&"weapon")
	assert_int(definitions.size()).is_equal(12)
	var weapon_options := strip.find_children("WeaponOption*", "Button", true, false)
	assert_int(weapon_options.size()).is_equal(definitions.size())
	var expected_names := [
		"蝴蝶刀", "Glock-18", "爪子刀", "AK-47", "AWP", "M4A1-S",
		"USP-S", "Desert Eagle", "MAC-10", "MP9", "P90", "UMP-45",
	]
	var expected_ids := [
		"weapon.training_blade:weapon/training_blade",
		"weapon.training_blaster:weapon/training_blaster",
		"gogobro.preview:weapon/community_tapper",
		"gogobro.preview:weapon/wood_stock_assault_rifle",
		"gogobro.preview:weapon/heavy_bolt_sniper",
		"gogobro.preview:weapon/suppressed_carbine",
		"gogobro.preview:weapon/suppressed_tactical_pistol",
		"gogobro.preview:weapon/heavy_hand_cannon",
		"gogobro.preview:weapon/box_submachine_gun",
		"gogobro.preview:weapon/compact_submachine_gun",
		"gogobro.preview:weapon/bullpup_pdw",
		"gogobro.preview:weapon/folding_stock_submachine_gun",
	]
	var actual_ids: Array[StringName] = []
	var actual_id_strings: Array[String] = []
	var actual_names: Array[String] = []
	var selected_options := 0
	for option_node in weapon_options:
		var option := option_node as Button
		var content_id := option.get_meta(&"content_id", &"") as StringName
		if option.get_meta(&"selected", false) as bool:
			selected_options += 1
			assert_str(String(content_id)).is_equal(String(ValidationContentFactory.RANGED_ID))
			var selected_style := option.get_theme_stylebox(&"normal") as StyleBoxFlat
			assert_object(selected_style).is_not_null()
			if selected_style != null:
				assert_bool(
					selected_style.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_FOCUS)
				).is_true()
		actual_ids.append(content_id)
		actual_id_strings.append(String(content_id))
		var definition := app.content_snapshot.definition(content_id, &"weapon") as GogoWeaponDefinition
		assert_object(definition).is_not_null()
		if definition == null:
			continue
		actual_names.append(definition.display_name)
		assert_str((option.get_node("Name") as Label).text).is_equal(definition.display_name)
		var icon := option.get_node("Icon") as TextureRect
		assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
		assert_bool(
			icon.texture != null
			or (
				(option.get_node("IconFallback") as Control).visible
				and not (option.get_node("IconFallback/Label") as Label).text.is_empty()
			)
		).is_true()
		option.grab_focus()
		await get_tree().process_frame
		assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Name") as Label).text).is_equal(
			definition.display_name
		)
		assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Mode") as Label).text).is_equal(
			"近战" if definition.mode == GogoWeaponDefinition.Mode.MELEE else "远程"
		)
		assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Damage") as Label).text).contains(
			_num(definition.damage)
		)
		assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Cooldown") as Label).text).contains(
			_num(definition.cooldown_seconds)
		)
		assert_bool(
			(screen.get_node("WeaponStage/SelectedWeaponDetail/Modifiers") as Label).text.contains(
				_num(definition.attack_range)
			)
		).is_true()
		var modifiers := (screen.get_node("WeaponStage/SelectedWeaponDetail/Modifiers") as Label).text
		assert_str(modifiers).contains(_localized_damage_kind(definition.damage_kind))
		assert_str(modifiers).contains(_localized_impact_kind(definition.impact_kind))
		assert_bool(
			modifiers.contains("ballistic")
			or modifiers.contains("melee")
			or modifiers.contains("normal")
			or modifiers.contains("pierce_exit")
			or modifiers.contains("critical")
		).is_false()
	assert_int(_unique_count(actual_ids)).is_equal(12)
	assert_int(selected_options).is_equal(1)
	actual_id_strings.sort()
	expected_ids.sort()
	assert_array(actual_id_strings).is_equal(expected_ids)
	actual_names.sort()
	expected_names.sort()
	assert_array(actual_names).is_equal(expected_names)
	assert_int(screen.find_children("*", "PanelContainer", true, false).size()).is_equal(0)
	assert_bool(_fits_native_capture(strip)).is_true()


func test_difficulty_setup_uses_only_real_standard_badge_and_canonical_multipliers() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	app.selection_draft["character_id"] = NIKO_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	assert_int(app.route(FlowRoute.DIFFICULTY_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := fixture.host.get_child(0) as GogoScreenBase
	for path in [
		^"BackButton",
		^"NikoDetail",
		^"ChangeCharacterButton",
		^"DifficultyStage",
		^"DifficultyStage/DifficultyStrip",
		^"DifficultyStage/DifficultyStrip/DifficultyOption0",
		^"DifficultyStage/DifficultyStrip/DifficultyOption0/Icon",
		^"DifficultyStage/DifficultyStrip/DifficultyOption0/Title",
		^"DifficultyStage/DifficultyStrip/DifficultyOption0/Multipliers",
		^"DifficultyStage/DifficultyStrip/DifficultyOption0/StartCue",
	]:
		assert_object(screen.get_node_or_null(path)).is_not_null()
	var strip := screen.get_node_or_null("DifficultyStage/DifficultyStrip") as HBoxContainer
	if strip == null:
		return
	assert_int(app.content_snapshot.all(&"difficulty").size()).is_equal(1)
	assert_int(strip.get_child_count()).is_equal(1)
	var option := strip.get_child(0) as Button
	assert_str(String(option.get_meta(&"content_id", &""))).is_equal(
		String(ValidationContentFactory.DIFFICULTY_ID)
	)
	var normal_style := option.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_object(normal_style).is_not_null()
	if normal_style != null:
		assert_bool(normal_style.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL)).is_true()
		assert_int(normal_style.border_width_left).is_equal(1)
		assert_int(normal_style.border_width_top).is_equal(1)
		assert_int(normal_style.border_width_right).is_equal(1)
		assert_int(normal_style.border_width_bottom).is_equal(1)
	assert_int((option.get_node("Icon") as TextureRect).texture_filter).is_equal(
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	assert_str((option.get_node("Title") as Label).text).is_equal("标准")
	var multipliers := (option.get_node("Multipliers") as Label).text
	for text in ["生命 100%", "伤害 100%"]:
		assert_str(multipliers).contains(text)
	assert_str((option.get_node("StartCue") as Label).text).is_equal("开始")
	for label_name in [&"Title", &"Multipliers", &"StartCue"]:
		var label := option.get_node(NodePath(label_name)) as Label
		assert_int(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		assert_bool(option.get_global_rect().encloses(label.get_global_rect())).is_true()
	var definition := app.content_snapshot.definition(
		ValidationContentFactory.DIFFICULTY_ID, &"difficulty"
	) as GogoDifficultyDefinition
	assert_float(definition.enemy_health_multiplier).is_equal(1.0)
	assert_float(definition.enemy_damage_multiplier).is_equal(1.0)
	assert_float(definition.enemy_speed_multiplier).is_equal(1.0)
	assert_float(definition.spawn_multiplier).is_equal(1.0)
	assert_int(screen.find_children("*", "PanelContainer", true, false).size()).is_equal(0)
	assert_bool(_fits_native_capture(strip)).is_true()


func test_setup_selection_back_draft_and_session_flow_use_real_buttons() -> void:
	var fixture := await _setup_route_fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Node
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle_ui()
	var screen := host.get_child(0) as GogoScreenBase
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	var weapon := screen.get_node("WeaponStage/WeaponColumns/Class4/WeaponOption11") as Button
	weapon.pressed.emit()
	await _settle_ui()
	var selected_weapon_id := &"gogobro.preview:weapon/heavy_bolt_sniper"
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_object(app.current_session).is_null()
	var back := screen.get_node("BackButton") as Button
	back.pressed.emit()
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_str(String(get_viewport().gui_get_focus_owner().get_meta(&"content_id"))).is_equal(String(selected_weapon_id))
	back.pressed.emit()
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.get_node("RosterStrip/NikoCell") as Button
	)
	back.pressed.emit()
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.MAIN_MENU))
	assert_object(app.current_session).is_null()
	assert_int(app.route(FlowRoute.WEAPON_SELECT)).is_equal(OK)
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	screen = host.get_child(0) as GogoScreenBase
	assert_bool((screen.get_node("RosterStrip/NikoCell") as Button).get_meta(&"selected", false)).is_true()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_str(String(get_viewport().gui_get_focus_owner().get_meta(&"content_id"))).is_equal(String(selected_weapon_id))
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_true()
	assert_object(app.current_session).is_null()
	back = screen.get_node("BackButton") as Button
	for step in 3:
		back.pressed.emit()
		await _settle_ui()
		if step < 2:
			assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.MAIN_MENU))
	assert_str(String(app.selection_draft.get("character_id", &""))).is_equal(String(NIKO_ID))
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_equal(String(selected_weapon_id))
	assert_int(app.route(FlowRoute.DIFFICULTY_SELECT)).is_equal(OK)
	await _settle_ui()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.CHARACTER_SELECT))
	var difficulty_screen := host.get_child(0) as GogoScreenBase
	assert_bool((difficulty_screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool((difficulty_screen.get_node("DifficultyStage") as Control).visible).is_true()
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_object(focus).is_not_null()
	if focus != null:
		assert_bool(focus.is_visible_in_tree()).is_true()
		assert_bool(focus != difficulty_screen.get_node("RosterStrip/NikoCell")).is_true()
	(difficulty_screen.get_node("DifficultyStage/DifficultyStrip/DifficultyOption0") as Button).pressed.emit()
	await _settle_ui()
	assert_str(String(app.selection_draft.get("difficulty_id", &""))).is_equal(String(ValidationContentFactory.DIFFICULTY_ID))
	assert_object(app.current_session).is_not_null()
	assert_str(app.scene_flow.current_route()).is_equal(String(FlowRoute.COMBAT))
	assert_str(String(app.current_session.run_state.player().character_id)).is_equal(String(NIKO_ID))
	assert_array(app.current_session.run_state.player().weapon_ids).is_equal([selected_weapon_id])


func test_shop_has_four_low_border_offers_stats_loadout_and_native_safe_actions() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var required_paths: Array[NodePath] = [
		^"TopBand/Wave",
		^"TopBand/Materials",
		^"TopBand/Reroll",
		^"OfferRow",
		^"OfferDescription",
		^"OfferFlavor",
		^"StatsColumn",
		^"LoadoutBar",
		^"ContinueButton",
	]
	var has_every_node := true
	for path in required_paths:
		has_every_node = has_every_node and shop.get_node_or_null(path) != null
	assert_bool(has_every_node).is_true()
	if not has_every_node:
		return

	var top_band := shop.get_node("TopBand") as Control
	assert_bool(top_band.get_rect().is_equal_approx(Rect2(32, 20, 1216, 64))).is_true()
	var offer_row := shop.get_node("OfferRow") as HBoxContainer
	assert_int(offer_row.get_child_count()).is_equal(4)
	assert_bool(offer_row.get_rect().is_equal_approx(Rect2(32, 100, 927, 384))).is_true()
	assert_float((shop.get_node("TopBand/Reroll") as Button).custom_minimum_size.y).is_equal(
		HUD_SKIN.BUTTON_HEIGHT_STANDARD
	)
	assert_float((shop.get_node("ContinueButton") as Button).custom_minimum_size.y).is_equal(
		HUD_SKIN.BUTTON_HEIGHT_PRIMARY
	)
	var item_card: Button
	for slot_index in 4:
		var slot := offer_row.get_child(slot_index) as VBoxContainer
		assert_bool(slot != null).is_true()
		if slot == null or not slot.has_node("Card") or not slot.has_node("Lock"):
			continue
		var card := slot.get_node("Card") as Button
		var lock := slot.get_node("Lock") as Button
		assert_bool(lock.clip_text).is_true()
		assert_int(lock.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_float(lock.custom_minimum_size.y).is_equal(HUD_SKIN.BUTTON_HEIGHT_STANDARD)
		assert_bool(lock.get_combined_minimum_size().y <= lock.custom_minimum_size.y).is_true()
		assert_bool(card.size.x >= 216.0 and card.size.x <= 235.0).is_true()
		assert_bool(is_equal_approx(card.size.y, 320.0)).is_true()
		assert_bool(lock.position.y >= card.get_rect().end.y).is_true()
		assert_bool((card.get_node("Icon") as TextureRect).size.is_equal_approx(Vector2(128, 128))).is_true()
		assert_bool(is_equal_approx((card.get_node("Icon") as TextureRect).size.x / 64.0, 2.0)).is_true()
		var type_badge := card.get_node("TypeBadge") as Label
		assert_bool(type_badge.visible).is_true()
		assert_bool(type_badge.text.begins_with("武器 · ") or type_badge.text == "道具").is_true()
		assert_str(String(card.get_meta(&"content_kind", &""))).is_equal(
			"weapon" if type_badge.text.begins_with("武器 · ") else "item"
		)
		if item_card == null and String(card.get_meta(&"content_kind", &"")) == "item":
			item_card = card
		assert_int((card.get_node("Icon") as TextureRect).texture_filter).is_equal(
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
		assert_int(card.find_children("RarityAccent", "ColorRect", true, false).size()).is_zero()
		var normal_style := card.get_theme_stylebox(&"normal") as StyleBoxTexture
		assert_object(normal_style).is_not_null()
		if normal_style != null:
			assert_object(normal_style.texture).is_same(HUD_SKIN.SHOP_CARD_TEXTURE)
		assert_bool(card.get_theme_stylebox(&"focus") is StyleBoxFlat).is_true()
		assert_bool(card.find_children("*", "PanelContainer", true, false).is_empty()).is_true()
		assert_bool(_fits_native_capture(card) and _fits_native_capture(lock)).is_true()

	var offer_description := shop.get_node("OfferDescription") as Label
	var offer_flavor := shop.get_node("OfferFlavor") as Label
	assert_object(shop.get_node_or_null("OfferDetailsBacking")).is_not_null()
	assert_object(shop.get_node_or_null("OfferRowVeil")).is_not_null()
	assert_int(offer_description.get_theme_font_size(&"font_size")).is_greater_equal(17)
	assert_int(offer_flavor.get_theme_font_size(&"font_size")).is_greater_equal(15)
	assert_bool(_fits_native_capture(offer_description)).is_true()
	assert_bool(_fits_native_capture(offer_flavor)).is_true()
	assert_bool(offer_description.get_rect().end.y <= offer_flavor.position.y).is_true()
	assert_bool(offer_flavor.get_rect().end.y < 570.0).is_true()
	assert_object(item_card).is_not_null()
	if item_card != null:
		item_card.grab_focus()
		await _settle_ui()
		var content_id := item_card.get_meta(&"content_id", &"") as StringName
		var definition := (
			(fixture.session as GameSession).content_snapshot.definition(content_id, &"item")
			as GogoItemDefinition
		)
		assert_object(definition).is_not_null()
		if definition != null:
			assert_str(offer_description.text).contains(definition.display_name)
			assert_str(offer_description.text).contains(
				String(definition.get_meta(&"description", "")).get_slice("。", 0)
			)
			assert_str(offer_flavor.text).is_equal(String(definition.get_meta(&"flavor", "")))

	var stats := shop.get_node("StatsColumn") as Control
	assert_bool(stats.get_rect().is_equal_approx(Rect2(983, 100, 265, 394))).is_true()
	assert_bool(stats.has_node("StatList")).is_true()
	var loadout := shop.get_node("LoadoutBar") as Control
	assert_bool(loadout.get_rect().is_equal_approx(Rect2(32, 570, 1216, 118))).is_true()
	assert_int((loadout.get_node("Weapons") as HBoxContainer).get_child_count()).is_equal(3)
	assert_bool(
		(loadout.get_node("Items") as HBoxContainer).size.x
		> (loadout.get_node("Weapons") as HBoxContainer).size.x
	).is_true()
	assert_bool(_fits_native_capture(shop.get_node("ContinueButton") as Control)).is_true()
	_assert_authored_button_states(shop.get_node("ContinueButton") as Button)
	assert_int(shop.find_children("StaticNineSlicePanel", "*", true, false).size()).is_equal(0)


func test_shop_buy_lock_and_reroll_mutate_canonical_state_and_restore_content_focus() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var player := session.run_state.player()
	var offer_row := shop.get_node_or_null("OfferRow") as HBoxContainer
	assert_object(offer_row).is_not_null()
	if offer_row == null:
		return
	var first_slot := offer_row.get_child(0) as VBoxContainer
	var first_card := first_slot.get_node("Card") as Button
	var first_lock := first_slot.get_node("Lock") as Button
	var locked_id := first_card.get_meta(&"content_id", &"") as StringName
	first_lock.grab_focus()
	first_lock.pressed.emit()
	await _settle_ui()
	assert_array(session.run_state.locked_shop_offer_ids).contains([locked_id])
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(
		focus_owner != null and focus_owner.get_meta(&"content_id", &"") == locked_id
	).is_true()

	var materials_before_reroll := player.materials
	var reroll := shop.get_node("TopBand/Reroll") as Button
	reroll.grab_focus()
	reroll.pressed.emit()
	await _settle_ui()
	assert_int(session.run_state.reroll_count).is_equal(1)
	assert_int(player.materials).is_equal(materials_before_reroll - 1)
	assert_str((shop.get_node("TopBand/Reroll") as Button).text).contains("2")
	assert_bool(_offer_row_contains(shop, locked_id)).is_true()

	var buy_card := _first_offer_card(shop)
	assert_object(buy_card).is_not_null()
	if buy_card == null:
		return
	var buy_id := buy_card.get_meta(&"content_id", &"") as StringName
	var definition := _content_definition(fixture.content as ContentSnapshot, buy_id)
	var owned_before := (
		player.item_ids.count(buy_id)
		if definition is GogoItemDefinition
		else player.weapon_ids.count(buy_id)
	)
	var materials_before_buy := player.materials
	assert_str((buy_card.get_node("PriceOrState") as Label).text).ends_with(" 金币")
	buy_card.pressed.emit()
	await _settle_ui()
	var focused_cards_after_buy := _focused_non_empty_offer_cards(shop)
	assert_int(focused_cards_after_buy.size()).is_equal(1)
	if focused_cards_after_buy.size() == 1:
		assert_object(get_viewport().gui_get_focus_owner()).is_same(focused_cards_after_buy[0])
	var owned_after := (
		player.item_ids.count(buy_id)
		if definition is GogoItemDefinition
		else player.weapon_ids.count(buy_id)
	)
	assert_int(owned_after).is_equal(owned_before + 1)
	assert_bool(player.materials < materials_before_buy).is_true()
	assert_bool((shop.get_node("TopBand/Materials") as Label).text.begins_with(
		"金币 %d   " % player.materials
	)).is_true()
	assert_str((shop.get_node("Status") as Label).text).is_equal("购买成功")


func test_shop_loadout_sell_combine_and_continue_use_real_services() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var player := session.run_state.player()
	var weapon_id := ValidationContentFactory.RANGED_ID
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(3)

	var slot := shop.get_node_or_null("LoadoutBar/Weapons/WeaponSlot0") as Button
	assert_object(slot).is_not_null()
	if slot == null:
		return
	slot.pressed.emit()
	await _settle_ui()
	var combine := shop.get_node_or_null("WeaponActionMenu/Panel/CombineButton") as Button
	assert_object(combine).is_not_null()
	if combine == null:
		return
	combine.grab_focus()
	combine.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(2)
	assert_int(player.weapon_inventory.record(1).quality).is_equal(2)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(
		focus_owner != null
		and focus_owner.get_meta(&"content_id", &"") == weapon_id
	).is_true()

	var materials_before_sell := player.materials
	(shop.get_node("LoadoutBar/Weapons/WeaponSlot0") as Button).pressed.emit()
	await _settle_ui()
	var sell := shop.get_node_or_null("WeaponActionMenu/Panel/SellButton") as Button
	assert_object(sell).is_not_null()
	if sell == null:
		return
	sell.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(1)
	assert_bool(player.materials > materials_before_sell).is_true()
	assert_str((shop.get_node("Status") as Label).text).is_equal("出售成功")
	var remaining_slot := shop.get_node("LoadoutBar/Weapons/WeaponSlot0") as Button
	remaining_slot.pressed.emit()
	await _settle_ui()
	var final_sell := shop.get_node_or_null("WeaponActionMenu/Panel/SellButton") as Button
	assert_object(final_sell).is_not_null()
	if final_sell == null:
		return
	final_sell.pressed.emit()
	await _settle_ui()
	assert_array(player.weapon_ids).is_empty()
	var empty_weapons := shop.get_node("LoadoutBar/Weapons") as HBoxContainer
	assert_int(empty_weapons.find_children("WeaponSlot*", "Button", false, false).size()).is_zero()
	assert_bool(empty_weapons.has_node("WeaponSlot0")).is_false()
	assert_str((empty_weapons.get_node("EmptyWeapons") as Label).text).is_equal("尚未装备武器")
	assert_int(empty_weapons.find_children("Actions", "HBoxContainer", true, false).size()).is_zero()

	var wave_before := session.run_state.current_wave
	(shop.get_node("ContinueButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_int(session.run_state.current_wave).is_equal(wave_before + 1)
	assert_str(String(session.run_state.phase)).is_equal("combat")


func test_shop_and_pause_loadouts_match_actual_weapon_capacity() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var player := (fixture.session as GameSession).run_state.player()
	var pause := auto_free(PAUSE_OVERLAY.new()) as Control
	add_child(pause)
	for count in [0, 1, 3, 6]:
		player.weapon_inventory = preload("res://game/session/weapon_inventory.gd").new()
		for index in count:
			player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, fixture.content as ContentSnapshot)
		shop.call(&"_rebuild")
		await _settle_ui()
		var shop_weapons := shop.get_node("LoadoutBar/Weapons") as HBoxContainer
		assert_str((shop.get_node("LoadoutBar/WeaponsTitle") as Label).text).is_equal(
			"武器 %d/6" % count
		)
		assert_int(shop_weapons.find_children("WeaponSlot*", "Button", false, false).size()).is_equal(count)
		assert_bool(shop_weapons.has_node("EmptyWeapons")).is_equal(count == 0)
		if count == 0:
			var shop_empty := shop_weapons.get_node_or_null("EmptyWeapons") as Label
			if shop_empty != null:
				assert_str(shop_empty.text).is_equal("尚未装备武器")

		pause.call("configure", player, fixture.content as ContentSnapshot, null, 3, 8, 17.2)
		var pause_weapons := pause.get_node("Loadout/Weapons") as HBoxContainer
		assert_str((pause.get_node("Loadout/WeaponsTitle") as Label).text).is_equal(
			"武器 %d/6" % count
		)
		assert_int(pause_weapons.find_children("WeaponSlot*", "Button", false, false).size()).is_equal(count)
		assert_bool(pause_weapons.has_node("EmptyWeapons")).is_equal(count == 0)
		for button: Button in pause_weapons.find_children("WeaponSlot*", "Button", false, false):
			assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
		if count == 0:
			var pause_empty := pause_weapons.get_node_or_null("EmptyWeapons") as Label
			if pause_empty != null:
				assert_str(pause_empty.text).is_equal("尚未装备武器")
				assert_int(pause_empty.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_shop_initial_focus_starts_on_the_first_enabled_offer() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var focused_cards := _focused_non_empty_offer_cards(shop)
	assert_int(focused_cards.size()).is_equal(1)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and shop.is_ancestor_of(focus_owner)).is_true()
	if focus_owner == null or focused_cards.size() != 1:
		return
	assert_object(focus_owner).is_same(focused_cards[0])
	assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("buy")
	assert_int(int(focus_owner.get_meta(&"offer_index", -1))).is_equal(0)
	var focus_style := (focus_owner as Button).get_theme_stylebox(&"focus") as StyleBoxFlat
	assert_object(focus_style).is_not_null()
	if focus_style != null:
		assert_bool(focus_style.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_FOCUS)).is_true()
	for label in focus_owner.find_children("*", "Label", true, false):
		if label.name == &"PriceOrState":
			assert_str((label as Label).text).contains("金币")
			assert_int((label as Label).text.get_slice(" ", 0).to_int()).is_greater(0)
			assert_bool((focus_owner as Control).get_global_rect().encloses((label as Label).get_global_rect())).is_true()
		assert_bool(
			(label as Label).get_theme_color(&"font_color").is_equal_approx(
				HUD_SKIN.COLOR_TEXT_FOCUS
			)
		).is_true()


func test_shop_compact_stats_keep_every_canonical_row_inside_the_right_column() -> void:
	var fixture := await _shop_fixture(true)
	var shop := fixture.screen as GogoScreenBase
	var column := shop.get_node("StatsColumn") as Control
	var list := column.get_node("StatList") as VBoxContainer
	assert_int(list.get_child_count()).is_equal(STAT_LIST_PRESENTER.STAT_SPECS.size())
	assert_bool(column.get_rect().is_equal_approx(Rect2(983, 100, 265, 394))).is_true()
	for row in list.get_children():
		assert_bool(column.get_global_rect().encloses((row as Control).get_global_rect())).is_true()
	assert_bool(
		column.get_global_rect().end.y
		< (shop.get_node("ContinueButton") as Control).get_global_rect().position.y
	).is_true()


func test_shop_two_copy_combine_restores_focus_to_the_surviving_weapon() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var player := (fixture.session as GameSession).run_state.player()
	var weapon_id := ValidationContentFactory.RANGED_ID
	player.weapon_inventory = preload("res://game/session/weapon_inventory.gd").new()
	player.weapon_inventory.add_weapon(weapon_id, fixture.content as ContentSnapshot)
	player.weapon_inventory.add_weapon(weapon_id, fixture.content as ContentSnapshot)
	shop.call(&"_rebuild")
	await _settle_ui()
	(shop.get_node("LoadoutBar/Weapons/WeaponSlot0") as Button).pressed.emit()
	await _settle_ui()
	var combine := shop.get_node_or_null("WeaponActionMenu/Panel/CombineButton") as Button
	assert_object(combine).is_not_null()
	if combine == null:
		return
	combine.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(1)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and focus_owner.get_meta(&"content_id", &"") == weapon_id).is_true()
	if focus_owner != null:
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("weapon")


func test_shop_interleaved_combine_tracks_the_selected_inventory_copy() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var player := (fixture.session as GameSession).run_state.player()
	var weapon_id := ValidationContentFactory.RANGED_ID
	var others := _other_weapon_ids(fixture.content as ContentSnapshot, weapon_id, 2)
	assert_int(others.size()).is_equal(2)
	if others.size() < 2:
		return
	player.weapon_inventory = preload("res://game/session/weapon_inventory.gd").new()
	for id: StringName in [weapon_id, others[0], weapon_id, others[1], weapon_id]:
		player.weapon_inventory.add_weapon(id, fixture.content as ContentSnapshot)
	shop.call(&"_rebuild")
	await _settle_ui()
	(shop.get_node("LoadoutBar/Weapons/WeaponSlot2") as Button).pressed.emit()
	await _settle_ui()
	var combine := shop.get_node_or_null("WeaponActionMenu/Panel/CombineButton") as Button
	assert_object(combine).is_not_null()
	if combine == null:
		return
	combine.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(2)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and focus_owner.get_meta(&"content_id", &"") == weapon_id).is_true()
	if focus_owner != null:
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("weapon")
		assert_int(int(focus_owner.get_meta(&"inventory_instance_id", 0))).is_equal(3)
		assert_int(int(focus_owner.get_meta(&"slot_index", -1))).is_equal(1)


func test_shop_rightmost_purchase_keeps_canonical_offers_and_nearest_focus() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var shop_runtime := shop.get("_shop") as ShopRuntimeService
	var ids_before: Array[StringName] = []
	for offer in shop_runtime.offers:
		ids_before.append((offer as GogoContentDefinition).content_id)
	var bought_id := ids_before[3]
	var offer_row_before := shop.get_node("OfferRow") as HBoxContainer
	var offer_row_rect_before := offer_row_before.get_rect()
	var slot_rects_before: Array[Rect2] = []
	for slot_index in offer_row_before.get_child_count():
		slot_rects_before.append((offer_row_before.get_child(slot_index) as Control).get_rect())
	(shop.get_node("OfferRow/OfferSlot3/Card") as Button).pressed.emit()
	await _settle_ui()
	assert_int(shop_runtime.offers.size()).is_equal(4)
	assert_int(session.run_state.reroll_count).is_equal(0)
	var offer_row_after := shop.get_node("OfferRow") as HBoxContainer
	assert_int(offer_row_after.get_child_count()).is_equal(4)
	assert_bool(offer_row_after.get_rect().is_equal_approx(offer_row_rect_before)).is_true()
	for slot_index in offer_row_after.get_child_count():
		assert_bool(
			(offer_row_after.get_child(slot_index) as Control).get_rect().is_equal_approx(
				slot_rects_before[slot_index]
			)
		).is_true()
	assert_object(shop_runtime.offers[3]).is_null()
	var ids_after: Array[StringName] = []
	for offer_index in 3:
		ids_after.append((shop_runtime.offers[offer_index] as GogoContentDefinition).content_id)
	assert_array(ids_after).is_equal(ids_before.slice(0, 3))
	var empty_slot := shop.get_node("OfferRow/OfferSlot3") as VBoxContainer
	assert_bool(empty_slot.get_meta(&"empty_offer_slot", false) as bool).is_true()
	assert_bool(
		empty_slot.custom_minimum_size.is_equal_approx(Vector2(216, offer_row_rect_before.size.y))
	).is_true()
	assert_bool(empty_slot.get_rect().is_equal_approx(slot_rects_before[3])).is_true()
	assert_int(empty_slot.get_child_count()).is_equal(0)
	assert_int(empty_slot.find_children("*", "Label", true, false).size()).is_equal(0)
	assert_int(empty_slot.find_children("*", "Button", true, false).size()).is_equal(0)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null).is_true()
	var focused_cards := _focused_non_empty_offer_cards(shop)
	assert_int(focused_cards.size()).is_equal(1)
	if focus_owner != null:
		assert_object(focus_owner).is_same(focused_cards[0])
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("buy")
		assert_int(int(focus_owner.get_meta(&"offer_index", -1))).is_equal(2)


func test_shop_purchase_keeps_each_quote_position_as_its_own_hole() -> void:
	var fixture := await _shop_fixture()
	var app := fixture.app as AppKernel
	var content := fixture.content as ContentSnapshot
	var shop := fixture.screen as GogoScreenBase
	for purchase_index in [0, 1, 2, 3]:
		if purchase_index > 0:
			shop.queue_free()
			await get_tree().process_frame
			var fresh_session := _shop_session(content)
			app.current_session = fresh_session
			shop = auto_free(SHOP_SCREEN.new()) as GogoScreenBase
			shop.static_asset_snapshot_override = _empty_static_snapshot()
			add_child(shop)
			await _settle_ui()
		var session := app.current_session as GameSession
		var player := session.run_state.player()
		var shop_runtime := shop.get("_shop") as ShopRuntimeService
		var offer_row_before := shop.get_node("OfferRow") as HBoxContainer
		var offer_row_rect_before := offer_row_before.get_rect()
		var definitions_before: Array[GogoContentDefinition] = []
		var ids_before: Array[StringName] = []
		var slot_rects_before: Array[Rect2] = []
		var cache_before: Array[StringName] = session.run_state.shop_offer_ids.duplicate()
		var locked_before: Array[StringName] = session.run_state.locked_shop_offer_ids.duplicate()
		for slot_index in 4:
			var definition := shop_runtime.offers[slot_index] as GogoContentDefinition
			assert_object(definition).is_not_null()
			if definition == null:
				return
			definitions_before.append(definition)
			ids_before.append(definition.content_id)
			slot_rects_before.append((offer_row_before.get_child(slot_index) as Control).get_rect())
			var card := shop.get_node("OfferRow/OfferSlot%d/Card" % slot_index) as Button
			assert_str(String(card.get_meta(&"content_id", &""))).is_equal(String(definition.content_id))
			assert_bool(card.disabled).is_false()

		var purchased := definitions_before[purchase_index]
		var owned_before := (
			player.item_ids.count(purchased.content_id)
			if purchased is GogoItemDefinition
			else player.weapon_ids.count(purchased.content_id)
		)
		var materials_before := player.materials
		(shop.get_node("OfferRow/OfferSlot%d/Card" % purchase_index) as Button).pressed.emit()
		await _settle_ui()

		assert_int(shop_runtime.offers.size()).is_equal(4)
		assert_int(session.run_state.reroll_count).is_equal(0)
		assert_bool(player.materials < materials_before).is_true()
		var owned_after := (
			player.item_ids.count(purchased.content_id)
			if purchased is GogoItemDefinition
			else player.weapon_ids.count(purchased.content_id)
		)
		assert_int(owned_after).is_equal(owned_before + 1)
		var offer_row_after := shop.get_node("OfferRow") as HBoxContainer
		assert_int(offer_row_after.get_child_count()).is_equal(4)
		assert_bool(offer_row_after.get_rect().is_equal_approx(offer_row_rect_before)).is_true()
		for slot_index in 4:
			var slot := offer_row_after.get_child(slot_index) as VBoxContainer
			assert_bool(slot.get_rect().is_equal_approx(slot_rects_before[slot_index])).is_true()
			if slot_index == purchase_index:
				assert_object(shop_runtime.offers[slot_index]).is_null()
				assert_str(String(session.run_state.shop_offer_ids[slot_index])).is_equal("")
				assert_bool(session.run_state.locked_shop_offer_ids.has(purchased.content_id)).is_false()
				assert_bool(slot.get_meta(&"empty_offer_slot", false) as bool).is_true()
				assert_int(slot.get_child_count()).is_zero()
				assert_int(slot.find_children("*", "Button", true, false).size()).is_zero()
				continue
			assert_object(shop_runtime.offers[slot_index]).is_same(definitions_before[slot_index])
			assert_str(String(session.run_state.shop_offer_ids[slot_index])).is_equal(
				String(cache_before[slot_index])
			)
			assert_bool(session.run_state.locked_shop_offer_ids.has(ids_before[slot_index])).is_equal(
				locked_before.has(ids_before[slot_index])
			)
			var retained_card := slot.get_node("Card") as Button
			assert_str(String(retained_card.get_meta(&"content_id", &""))).is_equal(String(ids_before[slot_index]))
			assert_bool(retained_card.disabled).is_false()


func test_upgrade_reward_has_exactly_four_real_choices() -> void:
	var fixture := await _route_upgrade()
	var screen := fixture.screen as GogoScreenBase
	var choices := screen.get_node_or_null("UpgradeChoiceRow") as HBoxContainer
	assert_object(choices).is_not_null()
	if choices != null:
		assert_int(choices.get_child_count()).is_equal(4)
	assert_bool(screen.has_node("StatsColumn")).is_true()
	assert_bool(screen.has_node("RerollButton")).is_true()


func test_upgrade_reroll_charges_its_own_canonical_counter_without_duplicate_choices() -> void:
	var fixture := await _route_upgrade()
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var player := session.run_state.player()
	var choices := screen.get_node("UpgradeChoiceRow") as HBoxContainer
	var before_ids := _upgrade_choice_ids(choices)
	assert_int(before_ids.size()).is_equal(4)
	assert_int(_unique_count(before_ids)).is_equal(4)
	assert_str((screen.get_node("RerollButton") as Button).text).contains("1")
	var materials_before := player.materials
	(screen.get_node("RerollButton") as Button).pressed.emit()
	await _settle_ui()
	screen = fixture.app.get_node("UpgradeRouteHost").get_child(0) as GogoScreenBase
	assert_int(session.run_state.reroll_count).is_equal(0)
	assert_int(session.run_state.upgrade_reroll_count).is_equal(1)
	assert_int(player.materials).is_equal(materials_before - 1)
	var after_ids := _upgrade_choice_ids(screen.get_node("UpgradeChoiceRow") as HBoxContainer)
	assert_int(after_ids.size()).is_equal(4)
	assert_int(_unique_count(after_ids)).is_equal(4)
	assert_array(after_ids).is_not_equal(before_ids)
	var reward_status := screen.get_node("RewardStatus") as Label
	assert_str(reward_status.text).contains("刷新完成")
	assert_str(reward_status.text).contains("剩余 1 次")
	assert_str(reward_status.text).contains("金币 %d" % player.materials)
	assert_str((screen.get_node("RerollButton") as Button).text).is_equal("刷新 1")
	var reroll_button := screen.get_node("RerollButton") as Button
	var choice_row := screen.get_node("UpgradeChoiceRow") as HBoxContainer
	assert_bool(
		is_equal_approx(reroll_button.get_global_rect().position.y, choice_row.get_global_rect().end.y + 16.0)
	).is_true()
	assert_float(reroll_button.get_global_rect().get_center().x).is_equal_approx(
		choice_row.get_global_rect().get_center().x,
		0.001
	)
	assert_bool(NATIVE_CAPTURE_RECT.encloses(reroll_button.get_global_rect())).is_true()
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and focus_owner.get_meta(&"focus_role", &"") == &"upgrade_choice").is_true()


func test_upgrade_reroll_with_insufficient_materials_keeps_offers_and_state_unchanged() -> void:
	var fixture := await _route_upgrade()
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var player := session.run_state.player()
	player.materials = 0
	var before_ids := _upgrade_choice_ids(screen.get_node("UpgradeChoiceRow") as HBoxContainer)
	(screen.get_node("RerollButton") as Button).pressed.emit()
	await _settle_ui()
	screen = fixture.app.get_node("UpgradeRouteHost").get_child(0) as GogoScreenBase
	assert_int(session.run_state.upgrade_reroll_count).is_equal(0)
	assert_int(player.materials).is_equal(0)
	assert_array(_upgrade_choice_ids(screen.get_node("UpgradeChoiceRow") as HBoxContainer)).is_equal(before_ids)
	var reward_status := screen.get_node("RewardStatus") as Label
	assert_str(reward_status.text).contains("金币不足")
	assert_str(reward_status.text).contains("剩余 1 次")
	assert_str(reward_status.text).contains("金币 0")


func test_upgrade_choice_decrements_pending_rewards_then_routes_to_shop() -> void:
	var battlefield_backdrop := _texture(Vector2i(1280, 720))
	var fixture := await _route_upgrade(2, null, battlefield_backdrop)
	var screen := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var player := session.run_state.player()
	var first_choice := screen.get_node("UpgradeChoiceRow/UpgradeChoice0") as Button
	var chosen_id := first_choice.get_meta(&"content_id", &"") as StringName
	first_choice.pressed.emit()
	await _settle_ui()
	screen = fixture.app.get_node("UpgradeRouteHost").get_child(0) as GogoScreenBase
	assert_int(session.run_state.pending_upgrade_count).is_equal(1)
	assert_array(player.upgrade_ids).contains([chosen_id])
	assert_bool(screen.get_script().resource_path == "res://game/ui/upgrade_screen.gd").is_true()
	assert_int((screen.get_node("UpgradeChoiceRow") as HBoxContainer).get_child_count()).is_equal(4)
	(screen.get_node("UpgradeChoiceRow/UpgradeChoice0") as Button).pressed.emit()
	await _settle_ui()
	assert_int(session.run_state.pending_upgrade_count).is_equal(0)
	assert_str(String(session.run_state.phase)).is_equal("shop")
	assert_str((fixture.app as AppKernel).scene_flow.current_route()).is_equal("shop")
	var shop := fixture.app.get_node("UpgradeRouteHost").get_child(0) as GogoScreenBase
	assert_bool(shop.has_node("BattlefieldBackdrop")).is_true()
	assert_object((shop.get_node("BattlefieldBackdrop") as TextureRect).texture).is_same(
		battlefield_backdrop
	)


func test_upgrade_reroll_counter_resets_on_entry_and_loads_legacy_saves_as_zero() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	session.run_state.reroll_count = 7
	session.run_state.upgrade_reroll_count = 3
	assert_int(session.transition(&"upgrade")).is_equal(OK)
	assert_int(session.run_state.reroll_count).is_equal(7)
	assert_int(session.run_state.upgrade_reroll_count).is_equal(0)
	var serialized := session.run_state.to_dictionary()
	serialized.schema_version = 1
	serialized.players[0].erase("weapons")
	serialized.players[0].erase("next_weapon_instance_id")
	serialized.players[0].weapon_ids = session.run_state.player().weapon_ids.map(func(id: StringName) -> String: return String(id))
	serialized.erase("upgrade_reroll_count")
	var restored := GogoRunState.from_dictionary(serialized, session.content_snapshot)
	assert_int(restored.upgrade_reroll_count).is_equal(0)


func test_upgrade_route_rejects_content_with_fewer_than_four_real_rewards() -> void:
	var fixture := await _route_upgrade(1, _upgrade_content_with_count(3))
	var screen := fixture.app.get_node("UpgradeRouteHost").get_child(0) as GogoScreenBase
	assert_str(screen.get_script().resource_path).is_equal("res://game/ui/diagnostic_screen.gd")
	assert_str((screen.get_node("TitleBand/Subtitle") as Label).text).contains("升级奖励不可用")


func test_upgrade_reward_service_returns_no_partial_choice_set() -> void:
	var content := _upgrade_content_with_count(3)
	var session := GameSession.new()
	session.content_snapshot = content
	session.run_state = GogoRunState.new()
	session.run_state.run_seed = 9137
	session.run_state.players.append(SessionPlayerState.new())
	var service := PlayerBuildService.new()
	assert_array(service.upgrade_reward_offers(session)).is_empty()


func _loadout_content() -> ContentSnapshot:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"fixture.ui"
	pack.pack_kind = &"core"
	for spec in [
		[&"fixture:weapon/ak", "AK-47", &"fixture_ak", 3],
		[&"fixture:weapon/knife", "爪子刀", &"fixture_knife", 2],
	]:
		var weapon := GogoWeaponDefinition.new()
		weapon.content_id = spec[0]
		weapon.display_name = spec[1]
		weapon.icon_asset_id = spec[2]
		weapon.tier = spec[3]
		pack.definitions.append(weapon)
	for index in 12:
		var item := GogoItemDefinition.new()
		item.content_id = StringName("fixture:item/%02d" % index)
		item.display_name = "道具 %02d" % index
		item.icon_asset_id = StringName("fixture_item_%02d" % index)
		item.tier = 1 + index % 4
		pack.definitions.append(item)
	var snapshot := ContentSnapshot.new()
	assert_int(snapshot.install_pack(pack)).is_equal(OK)
	snapshot.seal()
	return snapshot


func _loadout_static_snapshot() -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	for asset_id: StringName in [&"fixture_ak", &"fixture_item_00"]:
		var key := "%s|icon|icon" % asset_id
		var handle := GogoStaticAssetHandle.new()
		handle._configure({
			"binding_key": StringName(key),
			"asset_id": asset_id,
			"role": &"icon",
			"selector": &"icon",
			"display_size_px": Vector2i(64, 64),
			"display_scale": Vector2.ONE,
			"pivot_px": Vector2i(32, 32),
			"anchors_px": {},
			"atlas_rect_px": Rect2i(0, 0, 64, 64),
		}, _texture(Vector2i(64, 64)))
		handles[key] = handle
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "fixture", 70, {}, handles, {}, {}, {}, [])
	return snapshot


func _empty_static_snapshot() -> GogoStaticAssetSnapshot:
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "empty", 70, {}, {}, {}, {}, {}, [])
	return snapshot


func _texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("d89a54"))
	return ImageTexture.create_from_image(image)


func _push_pointer_click(viewport: Viewport, at: Vector2) -> void:
	var pressed := InputEventMouseButton.new()
	pressed.position = at
	pressed.global_position = at
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	viewport.push_input(pressed)
	await get_tree().process_frame
	var released := pressed.duplicate() as InputEventMouseButton
	released.pressed = false
	viewport.push_input(released)
	await get_tree().process_frame


func _shop_fixture(include_all_stats: bool = false) -> Dictionary:
	var content := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs()
	)
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	assert_int(app.profile_service.load_profile(content)).is_equal(OK)
	add_child(app)
	var session := _shop_session(content)
	if include_all_stats:
		var player := session.run_state.player()
		for spec: Array in STAT_LIST_PRESENTER.STAT_SPECS:
			var key := spec[0] as StringName
			player.base_stats[key] = 0.0
			player.final_stats[key] = 1.0
	app.current_session = session
	var screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	await _settle_ui()
	return {
		"app": app,
		"content": content,
		"session": session,
		"screen": screen,
	}


func _setup_route_fixture() -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.name = "SetupApp"
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
	var host := Node.new()
	host.name = "SetupRouteHost"
	var flow := SceneFlow.new()
	flow.name = "SetupSceneFlow"
	add_child(app)
	app.add_child(host)
	app.add_child(flow)
	flow.configure(host, {
		FlowRoute.MAIN_MENU: _packed_control_scene("MainMenuStub"),
		FlowRoute.CHARACTER_SELECT: preload("res://game/ui/character_select_screen.tscn"),
		FlowRoute.WEAPON_SELECT: preload("res://game/ui/weapon_select_screen.tscn"),
		FlowRoute.DIFFICULTY_SELECT: preload("res://game/ui/difficulty_select_screen.tscn"),
		FlowRoute.COMBAT: _packed_control_scene("CombatStub"),
		FlowRoute.DIAGNOSTIC: preload("res://game/ui/diagnostic_screen.tscn"),
	})
	app.configure(flow, null)
	app.begin_selection()
	await _settle_ui()
	return {"app": app, "host": host}


func _packed_control_scene(node_name: String) -> PackedScene:
	var node := Control.new()
	node.name = node_name
	var packed := PackedScene.new()
	assert_int(packed.pack(node)).is_equal(OK)
	node.free()
	return packed


func _route_upgrade(
	pending_choices: int = 1,
	content: ContentSnapshot = null,
	battlefield_backdrop: Texture2D = null
) -> Dictionary:
	if content == null:
		content = GogoContentRegistry.new().build_snapshot(
			ValidationContentFactory.create_packs()
		)
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	var host := Node.new()
	host.name = "UpgradeRouteHost"
	var flow := SceneFlow.new()
	add_child(app)
	app.add_child(host)
	app.add_child(flow)
	flow.configure(host, {
		FlowRoute.UPGRADE: preload("res://game/ui/upgrade_screen.tscn"),
		FlowRoute.SHOP: preload("res://game/ui/shop_screen.tscn"),
		FlowRoute.DIAGNOSTIC: preload("res://game/ui/diagnostic_screen.tscn"),
	})
	app.configure(flow, null)
	var session := GameSession.new()
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	assert_int(session.start(config, content)).is_equal(OK)
	session.run_state.pending_upgrade_count = pending_choices
	assert_int(session.transition(&"upgrade")).is_equal(OK)
	app.current_session = session
	assert_int(app.route(FlowRoute.UPGRADE, {
		"battlefield_backdrop": battlefield_backdrop,
	})).is_equal(OK)
	await _settle_ui()
	return {"app": app, "session": session, "screen": host.get_child(0)}


func _upgrade_content_with_count(count: int) -> ContentSnapshot:
	var packs := ValidationContentFactory.create_packs()
	var core_pack := packs[0]
	var retained := 0
	for index in range(core_pack.definitions.size() - 1, -1, -1):
		if not core_pack.definitions[index] is GogoUpgradeDefinition:
			continue
		retained += 1
		if retained > count:
			core_pack.definitions.remove_at(index)
	return GogoContentRegistry.new().build_snapshot(packs)


func _shop_session(content: ContentSnapshot) -> GameSession:
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	var player := session.run_state.player()
	player.materials = 500
	player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, content)
	player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, content)
	var items := content.all(&"item")
	if not items.is_empty():
		player.item_ids.append((items[0] as GogoContentDefinition).content_id)
	assert_int(session.transition(&"shop")).is_equal(OK)
	return session


func _settle_ui() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _fits_native_capture(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	return NATIVE_CAPTURE_RECT.encloses(rect)


func _assert_authored_button_states(button: Button) -> void:
	var expected_textures := {
		&"normal": HUD_SKIN.BUTTON_NORMAL,
		&"hover": HUD_SKIN.BUTTON_FOCUS,
		&"focus": HUD_SKIN.BUTTON_FOCUS,
		&"pressed": HUD_SKIN.BUTTON_PRESSED,
		&"disabled": HUD_SKIN.BUTTON_DISABLED,
	}
	for state: StringName in expected_textures:
		_assert_authored_texture_style(
			button.get_theme_stylebox(state),
			expected_textures[state] as Texture2D,
			HUD_SKIN.BUTTON_PATCH_MARGIN,
			18.0,
			8.0
		)
	assert_int(button.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_bool(button.get_node_or_null("ButtonFill") == null).is_true()


func _assert_authored_texture_style(
	style_box: StyleBox,
	expected_texture: Texture2D,
	patch_margin: float,
	horizontal_content_margin: float,
	vertical_content_margin: float
) -> void:
	var style := style_box as StyleBoxTexture
	assert_object(style).is_not_null()
	if style == null:
		return
	assert_object(style.texture).is_same(expected_texture)
	assert_bool(style.draw_center).is_true()
	assert_int(style.axis_stretch_horizontal).is_equal(
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)
	assert_int(style.axis_stretch_vertical).is_equal(
		StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_float(style.get_texture_margin(side)).is_equal(patch_margin)
		assert_float(style.get_expand_margin(side)).is_equal(0.0)
	assert_float(style.get_content_margin(SIDE_LEFT)).is_equal(horizontal_content_margin)
	assert_float(style.get_content_margin(SIDE_TOP)).is_equal(vertical_content_margin)
	assert_float(style.get_content_margin(SIDE_RIGHT)).is_equal(horizontal_content_margin)
	assert_float(style.get_content_margin(SIDE_BOTTOM)).is_equal(vertical_content_margin)


func _upgrade_choice_ids(choices: HBoxContainer) -> Array[StringName]:
	var ids: Array[StringName] = []
	for card in choices.get_children():
		ids.append((card as Button).get_meta(&"content_id", &"") as StringName)
	return ids


func _unique_count(ids: Array[StringName]) -> int:
	var unique := {}
	for content_id in ids:
		unique[content_id] = true
	return unique.size()


func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2).trim_suffix("0")


func _localized_damage_kind(kind: StringName) -> String:
	return "近战" if kind == &"melee" else "弹道"


func _localized_impact_kind(kind: StringName) -> String:
	return {
		&"critical": "暴击",
		&"pierce_exit": "穿透",
		&"normal": "普通",
	}.get(kind, "普通") as String


func _offer_row_contains(shop: Node, content_id: StringName) -> bool:
	var row := shop.get_node_or_null("OfferRow") as HBoxContainer
	if row == null:
		return false
	for slot in row.get_children():
		var card := (slot as Node).get_node_or_null("Card") as Button
		if card != null and card.get_meta(&"content_id", &"") == content_id:
			return true
	return false


func _first_offer_card(shop: Node) -> Button:
	var row := shop.get_node_or_null("OfferRow") as HBoxContainer
	if row == null:
		return null
	for slot in row.get_children():
		var card := (slot as Node).get_node_or_null("Card") as Button
		if card != null and not (card as Button).disabled:
			return card
	return null


func _focused_non_empty_offer_cards(shop: Node) -> Array[Button]:
	var result: Array[Button] = []
	var row := shop.get_node_or_null("OfferRow") as HBoxContainer
	if row == null:
		return result
	for slot in row.get_children():
		var card := (slot as Node).get_node_or_null("Card") as Button
		if card != null and not card.disabled and card.has_focus():
			result.append(card)
	return result


func _content_definition(
	content: ContentSnapshot,
	content_id: StringName
) -> GogoContentDefinition:
	var item := content.definition(content_id, &"item")
	if item != null:
		return item
	return content.definition(content_id, &"weapon")


func _other_weapon_ids(
	content: ContentSnapshot,
	excluded_id: StringName,
	count: int
) -> Array[StringName]:
	var result: Array[StringName] = []
	for definition in content.all(&"weapon"):
		var content_id := (definition as GogoContentDefinition).content_id
		if content_id == excluded_id:
			continue
		result.append(content_id)
		if result.size() == count:
			break
	return result
