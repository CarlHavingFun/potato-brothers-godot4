extends GdUnitTestSuite


const STAT_LIST_PATH := "res://game/ui/stat_list_presenter.gd"
const LOADOUT_STRIP_PATH := "res://game/ui/loadout_strip_presenter.gd"
const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const NATIVE_CAPTURE_RECT := Rect2(0, 0, 1280, 720)


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
			"%d 材料" % (index + 1),
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
	assert_bool(
		shop_screen.body.get_combined_minimum_size().y <= shop_screen.content_root.size.y
	).is_true()


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


func test_flat_button_fallback_has_a_hard_one_pixel_outline() -> void:
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _empty_static_snapshot()
	add_child(screen)
	screen.build_screen("按钮")
	var button := screen.add_action("继续", func() -> void: pass)
	var normal := button.get_theme_stylebox(&"normal")
	assert_bool(normal is StyleBoxFlat).is_true()
	if not normal is StyleBoxFlat:
		return
	var flat := normal as StyleBoxFlat
	assert_int(flat.border_width_left).is_equal(1)
	assert_int(flat.border_width_top).is_equal(1)
	assert_int(flat.border_width_right).is_equal(1)
	assert_int(flat.border_width_bottom).is_equal(1)
	assert_bool(flat.anti_aliasing).is_false()
	assert_int(flat.corner_radius_top_left).is_equal(0)


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
		"12 材料",
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
	var flat := normal as StyleBoxFlat
	assert_int(flat.border_width_left).is_equal(1)
	assert_int(flat.border_width_top).is_equal(1)
	assert_int(flat.border_width_right).is_equal(1)
	assert_int(flat.border_width_bottom).is_equal(1)
	assert_bool(flat.anti_aliasing).is_false()
	assert_bool((accents[0] as ColorRect).color.is_equal_approx(Color("c65ce2"))).is_true()
	var icon := card.get_node("Icon") as TextureRect
	assert_bool(icon.size.is_equal_approx(Vector2(64, 64))).is_true()
	assert_int(icon.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_int((card.get_node("Name") as Label).get_theme_font_size("font_size")).is_equal(18)
	var stat_rows := card.get_node("StatRows") as VBoxContainer
	assert_int(stat_rows.get_child_count()).is_equal(2)
	assert_str((stat_rows.get_child(0) as Label).text).is_equal("最大生命 +2")
	assert_str((stat_rows.get_child(1) as Label).text).is_equal("移动速度 -5")
	assert_bool((stat_rows.get_child(0) as Label).text.contains("max_health")).is_false()
	assert_bool((stat_rows.get_child(1) as Label).text.contains("movement_speed")).is_false()
	assert_str((card.get_node("PriceOrState") as Label).text).is_equal("12 材料")
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
	assert_str((rows.get_node("MaxHealth/Name") as Label).text).is_equal("最大生命")
	assert_str((rows.get_node("MaxHealth/Value") as Label).text).is_equal("24")
	assert_str((rows.get_node("DamageMultiplier/Name") as Label).text).is_equal("伤害")
	assert_str((rows.get_node("DamageMultiplier/Value") as Label).text).is_equal("112%")
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


func test_stat_list_names_internal_speed_bonus_without_duplicating_the_final_stat_label() -> void:
	var player := SessionPlayerState.new()
	player.final_stats = {
		&"movement_speed": 250.0,
		&"movement_speed_multiplier": 0.1,
		&"attack_speed": 1.2,
		&"attack_speed_multiplier": 0.2,
	}
	var rows := auto_free(STAT_LIST_PRESENTER.build(
		player,
		ContentSnapshot.new()
	)) as VBoxContainer
	assert_str((rows.get_node("MovementSpeed/Name") as Label).text).is_equal("移动速度")
	assert_str(
		(rows.get_node("MovementSpeedMultiplier/Name") as Label).text
	).is_equal("移动速度加成")
	assert_str((rows.get_node("AttackSpeed/Name") as Label).text).is_equal("攻击速度")
	assert_str(
		(rows.get_node("AttackSpeedMultiplier/Name") as Label).text
	).is_equal("攻击速度加成")


func test_loadout_has_six_slots_nearest_icons_fallbacks_and_selected_actions() -> void:
	assert_bool(FileAccess.file_exists(LOADOUT_STRIP_PATH)).is_true()
	if not FileAccess.file_exists(LOADOUT_STRIP_PATH):
		return
	var content := _loadout_content()
	var player := SessionPlayerState.new()
	player.weapon_ids = [&"fixture:weapon/ak", &"fixture:weapon/knife"]
	for index in 12:
		player.item_ids.append(StringName("fixture:item/%02d" % index))
	var sell_slots: Array[int] = []
	var combine_ids: Array[StringName] = []
	var selected_slots: Array[int] = []
	var actions := {
		"selected_weapon_slot": 1,
		"select": func(slot: int) -> void: selected_slots.append(slot),
		"sell": func(slot: int) -> void: sell_slots.append(slot),
		"combine": func(content_id: StringName) -> void: combine_ids.append(content_id),
	}
	var presenter := load(LOADOUT_STRIP_PATH) as GDScript
	var strip := auto_free(presenter.build(
		player,
		content,
		_loadout_static_snapshot(),
		actions
	)) as Control
	var weapons := strip.get_node("Weapons") as HBoxContainer
	assert_int(weapons.get_child_count()).is_equal(6)
	for slot_index in 6:
		var slot := weapons.get_child(slot_index) as Button
		assert_bool(slot.custom_minimum_size.is_equal_approx(Vector2(72, 72))).is_true()
	assert_int(
		(weapons.get_node("WeaponSlot0/Icon") as TextureRect).texture_filter
	).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_object((weapons.get_node("WeaponSlot0/Icon") as TextureRect).texture).is_not_null()
	assert_str(
		(weapons.get_node("WeaponSlot1/FallbackLabel") as Label).text
	).is_equal("爪子刀")
	assert_bool(weapons.get_node("WeaponSlot1").has_node("Actions")).is_true()
	assert_bool(weapons.get_node("WeaponSlot0").has_node("Actions")).is_false()
	(weapons.get_node("WeaponSlot0") as Button).pressed.emit()
	(weapons.get_node("WeaponSlot1/Actions/SellButton") as Button).pressed.emit()
	(weapons.get_node("WeaponSlot1/Actions/CombineButton") as Button).pressed.emit()
	assert_array(selected_slots).is_equal([0])
	assert_array(sell_slots).is_equal([1])
	assert_array(combine_ids).is_equal([&"fixture:weapon/knife"])
	var empty_slot := weapons.get_node("WeaponSlot2") as Button
	assert_bool(empty_slot.disabled).is_true()
	assert_int(empty_slot.focus_mode).is_equal(Control.FOCUS_NONE)
	var items := strip.get_node("Items") as HBoxContainer
	assert_int(items.find_children("ItemIcon*", "Control", false, false).size()).is_equal(8)
	assert_str((items.get_node("Overflow") as Label).text).is_equal("+4")
	assert_bool(
		(items.get_node("ItemIcon0") as Control).custom_minimum_size.is_equal_approx(Vector2(48, 48))
	).is_true()


func test_shop_has_four_low_border_offers_stats_loadout_and_native_safe_actions() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var required_paths: Array[NodePath] = [
		^"TopBand/Wave",
		^"TopBand/Materials",
		^"TopBand/Reroll",
		^"OfferRow",
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
	assert_bool(offer_row.get_rect().is_equal_approx(Rect2(32, 100, 927, 372))).is_true()
	for slot_index in 4:
		var slot := offer_row.get_child(slot_index) as VBoxContainer
		assert_bool(slot != null).is_true()
		if slot == null or not slot.has_node("Card") or not slot.has_node("Lock"):
			continue
		var card := slot.get_node("Card") as Button
		var lock := slot.get_node("Lock") as Button
		assert_bool(card.size.x >= 216.0 and card.size.x <= 235.0).is_true()
		assert_bool(is_equal_approx(card.size.y, 320.0)).is_true()
		assert_bool(lock.position.y >= card.get_rect().end.y).is_true()
		assert_bool((card.get_node("Icon") as TextureRect).size.is_equal_approx(Vector2(128, 128))).is_true()
		assert_bool(is_equal_approx((card.get_node("Icon") as TextureRect).size.x / 64.0, 2.0)).is_true()
		assert_int((card.get_node("Icon") as TextureRect).texture_filter).is_equal(
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
		assert_int(card.find_children("RarityAccent", "ColorRect", true, false).size()).is_equal(1)
		assert_bool(card.find_children("*", "PanelContainer", true, false).is_empty()).is_true()
		assert_bool(_fits_native_capture(card) and _fits_native_capture(lock)).is_true()

	var stats := shop.get_node("StatsColumn") as Control
	assert_bool(stats.get_rect().is_equal_approx(Rect2(983, 100, 265, 394))).is_true()
	assert_bool(stats.has_node("StatList")).is_true()
	var loadout := shop.get_node("LoadoutBar") as Control
	assert_bool(loadout.get_rect().is_equal_approx(Rect2(32, 570, 1216, 118))).is_true()
	assert_int((loadout.get_node("Weapons") as HBoxContainer).get_child_count()).is_equal(6)
	assert_bool(
		(loadout.get_node("Items") as HBoxContainer).size.x
		> (loadout.get_node("Weapons") as HBoxContainer).size.x
	).is_true()
	assert_bool(_fits_native_capture(shop.get_node("ContinueButton") as Control)).is_true()
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
	buy_card.pressed.emit()
	await _settle_ui()
	var owned_after := (
		player.item_ids.count(buy_id)
		if definition is GogoItemDefinition
		else player.weapon_ids.count(buy_id)
	)
	assert_int(owned_after).is_equal(owned_before + 1)
	assert_bool(player.materials < materials_before_buy).is_true()
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
	var combine := shop.get_node(
		"LoadoutBar/Weapons/WeaponSlot0/Actions/CombineButton"
	) as Button
	combine.grab_focus()
	combine.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(2)
	assert_int(int(player.weapon_levels.get(String(weapon_id), 0))).is_equal(2)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(
		focus_owner != null
		and focus_owner.get_meta(&"content_id", &"") == weapon_id
	).is_true()

	var materials_before_sell := player.materials
	var sell := shop.get_node(
		"LoadoutBar/Weapons/WeaponSlot0/Actions/SellButton"
	) as Button
	sell.pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(1)
	assert_bool(player.materials > materials_before_sell).is_true()
	assert_str((shop.get_node("Status") as Label).text).is_equal("出售成功")

	var wave_before := session.run_state.current_wave
	(shop.get_node("ContinueButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_int(session.run_state.current_wave).is_equal(wave_before + 1)
	assert_str(String(session.run_state.phase)).is_equal("combat")


func test_shop_initial_focus_starts_on_the_first_enabled_offer() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and shop.is_ancestor_of(focus_owner)).is_true()
	if focus_owner == null:
		return
	assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("buy")
	assert_int(int(focus_owner.get_meta(&"offer_index", -1))).is_equal(0)


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
	player.weapon_ids.clear()
	player.weapon_ids.append(weapon_id)
	player.weapon_ids.append(weapon_id)
	shop.call(&"_rebuild")
	await _settle_ui()
	(shop.get_node("LoadoutBar/Weapons/WeaponSlot0") as Button).pressed.emit()
	await _settle_ui()
	(shop.get_node(
		"LoadoutBar/Weapons/WeaponSlot0/Actions/CombineButton"
	) as Button).pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(1)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and focus_owner.get_meta(&"content_id", &"") == weapon_id).is_true()
	if focus_owner != null:
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("weapon")


func test_shop_interleaved_combine_tracks_the_nearest_surviving_duplicate() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var player := (fixture.session as GameSession).run_state.player()
	var weapon_id := ValidationContentFactory.RANGED_ID
	var others := _other_weapon_ids(fixture.content as ContentSnapshot, weapon_id, 2)
	assert_int(others.size()).is_equal(2)
	if others.size() < 2:
		return
	player.weapon_ids.clear()
	for id: StringName in [weapon_id, others[0], weapon_id, others[1], weapon_id]:
		player.weapon_ids.append(id)
	shop.call(&"_rebuild")
	await _settle_ui()
	(shop.get_node("LoadoutBar/Weapons/WeaponSlot2") as Button).pressed.emit()
	await _settle_ui()
	(shop.get_node(
		"LoadoutBar/Weapons/WeaponSlot2/Actions/CombineButton"
	) as Button).pressed.emit()
	await _settle_ui()
	assert_int(player.weapon_ids.count(weapon_id)).is_equal(2)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null and focus_owner.get_meta(&"content_id", &"") == weapon_id).is_true()
	if focus_owner != null:
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("combine")
		assert_int(int(focus_owner.get_meta(&"slot_index", -1))).is_equal(3)


func test_shop_rightmost_purchase_keeps_canonical_offers_and_nearest_focus() -> void:
	var fixture := await _shop_fixture()
	var shop := fixture.screen as GogoScreenBase
	var session := fixture.session as GameSession
	var shop_runtime := shop.get("_shop") as ShopRuntimeService
	var ids_before: Array[StringName] = []
	for offer in shop_runtime.offers:
		ids_before.append((offer as GogoContentDefinition).content_id)
	var bought_id := ids_before[3]
	(shop.get_node("OfferRow/OfferSlot3/Card") as Button).pressed.emit()
	await _settle_ui()
	assert_int(shop_runtime.offers.size()).is_equal(3)
	assert_int(session.run_state.reroll_count).is_equal(0)
	assert_int((shop.get_node("OfferRow") as HBoxContainer).get_child_count()).is_equal(4)
	var ids_after: Array[StringName] = []
	for offer in shop_runtime.offers:
		ids_after.append((offer as GogoContentDefinition).content_id)
	ids_before.erase(bought_id)
	assert_array(ids_after).is_equal(ids_before)
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_bool(focus_owner != null).is_true()
	if focus_owner != null:
		assert_str(String(focus_owner.get_meta(&"focus_role", &""))).is_equal("buy")
		assert_int(int(focus_owner.get_meta(&"offer_index", -1))).is_equal(2)


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
	player.weapon_ids.append(ValidationContentFactory.RANGED_ID)
	player.weapon_ids.append(ValidationContentFactory.RANGED_ID)
	player.weapon_levels[String(ValidationContentFactory.RANGED_ID)] = 1
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
