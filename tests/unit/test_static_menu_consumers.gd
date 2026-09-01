extends GdUnitTestSuite


const CARD_PRESENTER_PATH := "res://game/ui/static_card_presenter.gd"
const MAIN_MENU := preload("res://game/ui/main_menu_screen.gd")
const DIAGNOSTIC_SCREEN := preload("res://game/ui/diagnostic_screen.gd")
const CHARACTER_SELECT := preload("res://game/ui/character_select_screen.gd")
const WEAPON_SELECT := preload("res://game/ui/weapon_select_screen.gd")
const DIFFICULTY_SELECT := preload("res://game/ui/difficulty_select_screen.gd")
const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const UPGRADE_SCREEN := preload("res://game/ui/upgrade_screen.gd")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")


func test_shared_static_card_presenter_exists() -> void:
	assert_bool(FileAccess.file_exists(CARD_PRESENTER_PATH)).is_true()


func test_main_menu_consumes_background_wordmark_and_button_without_a_viewport_frame() -> void:
	var snapshot := _static_ui_snapshot()
	var screen := auto_free(MAIN_MENU.new()) as GogoScreenBase
	screen.set("static_asset_snapshot_override", snapshot)
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var background := screen.get_node("StaticMenuBackground") as TextureRect
	var content_root := screen.get_node("ContentRoot") as Control
	var wordmark := screen.get_node("ContentRoot/Body/Wordmark") as TextureRect
	var actions := screen.get_node_or_null("ContentRoot/Body/MenuActions") as VBoxContainer
	assert_object(actions).is_not_null()
	if actions == null:
		return
	var start_button := actions.get_node("StartButton") as Button
	var exit_button := actions.get_node("ExitButton") as Button
	assert_object(background.texture).is_not_null()
	assert_object(content_root).is_not_null()
	assert_int(screen.find_children("StaticNineSlicePanel", "*", true, false).size()).is_equal(0)
	assert_object(wordmark.texture).is_not_null()
	assert_int(actions.get_child_count()).is_equal(5)
	assert_int(actions.size_flags_horizontal).is_equal(Control.SIZE_SHRINK_BEGIN)
	assert_bool(Rect2(0, 0, 1280, 720).encloses(actions.get_global_rect())).is_true()
	assert_vector(start_button.custom_minimum_size).is_equal(Vector2(360, 64))
	assert_vector(exit_button.custom_minimum_size).is_equal(Vector2(360, 64))
	assert_bool(start_button.has_node("ButtonFill")).is_false()
	_assert_button_uses_authored_states(start_button)
	_assert_button_uses_authored_states(exit_button)
	assert_object(screen.theme).is_not_null()
	assert_bool(start_button.disabled).is_false()


func test_main_menu_starts_with_a_visible_keyboard_and_gamepad_focus() -> void:
	var screen := auto_free(MAIN_MENU.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _static_ui_snapshot()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var start_button := screen.get_node(
		"ContentRoot/Body/MenuActions/StartButton"
	) as Button
	assert_object(get_viewport().gui_get_focus_owner()).is_same(start_button)
	assert_bool(start_button.has_focus()).is_true()


func test_difficulty_route_uses_inline_task_option_with_the_real_zone_icon() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	add_child(app)
	app.begin_selection()
	var screen := auto_free(DIFFICULTY_SELECT.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _static_ui_snapshot()
	add_child(screen)
	var task_option := screen.get_node_or_null("TaskOptionButton") as OptionButton
	var difficulty_stage := screen.get_node_or_null("DifficultyStage") as Control
	assert_object(task_option).is_not_null()
	assert_object(difficulty_stage).is_not_null()
	assert_object(screen.get_node_or_null("SelectedDifficultyDetail")).is_null()
	assert_object(screen.get_node_or_null("ZoneStage")).is_null()
	if task_option == null or difficulty_stage == null:
		return
	assert_int(task_option.item_count).is_equal(content.all(&"zone").size())
	assert_int(task_option.item_count).is_equal(1)
	assert_int(task_option.selected).is_equal(0)
	assert_str(String(task_option.get_item_metadata(0))).is_equal(
		String(ValidationContentFactory.ZONE_ID)
	)
	assert_str(task_option.get_item_text(0)).is_equal("任务 · 训练场")
	assert_str(task_option.get_item_tooltip(0)).is_equal("训练场 · 20 波 · 从第 1 波开始")
	assert_object(task_option.get_item_icon(0)).is_not_null()
	assert_int(task_option.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	var zone := content.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	assert_object(zone).is_not_null()
	if zone != null:
		assert_str(String(zone.icon_asset_id)).is_equal("zone_thumbnail")
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_bool(difficulty_stage.visible).is_false()
	assert_object(app.current_session).is_null()


func test_diagnostic_route_uses_one_centered_principal_surface() -> void:
	var snapshot := _static_ui_snapshot()
	var screen := auto_free(DIAGNOSTIC_SCREEN.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = snapshot
	screen.receive_route_payload({"message": "测试错误", "details": ["细节一"]})
	add_child(screen)
	var direct_surface := screen.get_node_or_null("PrincipalSurface")
	assert_object(direct_surface).is_not_null()
	var surface_count := 0
	for child: Node in screen.get_children():
		if child.name == &"PrincipalSurface":
			surface_count += 1
	assert_int(surface_count).is_equal(1)
	if direct_surface == null:
		return
	var surface := direct_surface as Panel
	assert_object(surface).is_not_null()
	if surface == null:
		return
	assert_vector(surface.position).is_equal(Vector2(272, 184))
	assert_vector(surface.size).is_equal(Vector2(736, 352))
	var surface_style := surface.get_theme_stylebox(&"panel") as StyleBoxTexture
	assert_object(surface_style).is_not_null()
	if surface_style != null:
		assert_object(surface_style.texture).is_same(HUD_SKIN.SURFACE_TEXTURE)
		assert_float(surface_style.get_texture_margin(SIDE_LEFT)).is_equal(
			HUD_SKIN.PANEL_PATCH_MARGIN
		)
	assert_bool(surface.has_node("DiagnosticContent")).is_true()


func test_diagnostic_many_details_scroll_inside_panel_and_keep_return_reachable() -> void:
	var details: Array[String] = []
	for index in 40:
		details.append("诊断细节 %02d：候选素材校验失败，需要保留完整来源与哈希。" % index)
	var screen := auto_free(DIAGNOSTIC_SCREEN.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = _static_ui_snapshot()
	screen.receive_route_payload({"message": "批量诊断", "details": details})
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var surface := screen.get_node("PrincipalSurface") as Panel
	var content := surface.get_node("DiagnosticContent") as VBoxContainer
	var scroll := content.get_node_or_null("DetailsScroll") as ScrollContainer
	var return_button := content.get_node_or_null("ReturnButton") as Button
	assert_vector(surface.position).is_equal(Vector2(272, 184))
	assert_vector(surface.size).is_equal(Vector2(736, 352))
	assert_object(scroll).is_not_null()
	assert_object(return_button).is_not_null()
	if scroll == null or return_button == null:
		return
	var content_bounds := Rect2(Vector2.ZERO, content.size)
	assert_bool(content_bounds.encloses(Rect2(scroll.position, scroll.size))).is_true()
	assert_bool(content_bounds.encloses(Rect2(return_button.position, return_button.size))).is_true()
	assert_bool(return_button.is_visible_in_tree()).is_true()
	assert_bool(scroll.has_node("DetailsList")).is_true()
	assert_int(scroll.get_node("DetailsList").get_child_count()).is_equal(40)
	var scrollbar := scroll.get_v_scroll_bar()
	assert_bool(scrollbar.max_value > scrollbar.page).is_true()
	scroll.scroll_vertical = int(scrollbar.max_value)
	await get_tree().process_frame
	assert_bool(scroll.scroll_vertical > 0).is_true()


func test_action_button_uses_the_hud_skin_even_when_legacy_atlas_has_no_selectors() -> void:
	var snapshot := _static_ui_snapshot(false)
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = snapshot
	add_child(screen)
	screen.build_screen("兼容按钮")
	var button := screen.add_action("开始", func() -> void: pass)
	var expected_colors := {
		&"normal": HUD_SKIN.COLOR_CONTROL,
		&"hover": HUD_SKIN.COLOR_CONTROL_FOCUS,
		&"pressed": HUD_SKIN.COLOR_CONTROL_PRESSED,
		&"disabled": HUD_SKIN.COLOR_CONTROL_DISABLED,
	}
	var all_states_use_hud_skin := true
	for state: StringName in expected_colors:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		all_states_use_hud_skin = (
			all_states_use_hud_skin
			and style != null
			and style.bg_color.is_equal_approx(expected_colors[state] as Color)
			and style.border_width_left == 1
		)
	assert_bool(all_states_use_hud_skin).is_true()


func test_missing_icon_keeps_shared_text_card_selectable_and_complete() -> void:
	if not FileAccess.file_exists(CARD_PRESENTER_PATH):
		return
	var presenter := load(CARD_PRESENTER_PATH) as GDScript
	var definition := GogoItemDefinition.new()
	definition.content_id = &"fixture:item/no_texture"
	definition.display_name = "无贴图道具"
	definition.tier = 2
	definition.stat_modifiers = {&"armor": 1.0}
	var card := auto_free(presenter.build_card(definition, "12 金币", _empty_snapshot())) as Control
	assert_bool(card.has_node("Icon")).is_true()
	assert_bool(card.has_node("Name")).is_true()
	assert_bool(card.has_node("RarityAccent")).is_true()
	assert_bool(card.has_node("RarityLabel")).is_true()
	assert_bool(card.has_node("StatRows/Stat1")).is_true()
	assert_bool(card.has_node("StatRows/Stat2")).is_true()
	assert_bool(card.has_node("PriceOrState")).is_true()
	assert_bool(card.mouse_filter != Control.MOUSE_FILTER_IGNORE).is_true()
	assert_str((card.get_node("Name") as Label).text).is_equal("无贴图道具")
	assert_str((card.get_node("PriceOrState") as Label).text).is_equal("12 金币")
	assert_object((card.get_node("Icon") as TextureRect).texture).is_null()
	assert_bool((card.get_node("IconFallback") as ColorRect).visible).is_true()
	var icon := card.get_node("Icon") as TextureRect
	var price_or_state := card.get_node("PriceOrState") as Label
	assert_bool(
		icon.size.x >= 64.0
		and icon.size.y >= 64.0
		and icon.position.x + icon.size.x <= card.size.x
		and icon.position.y + icon.size.y <= card.size.y
		and (
			price_or_state.clip_text
			or price_or_state.autowrap_mode != TextServer.AUTOWRAP_OFF
		)
		and price_or_state.position.x + price_or_state.size.x <= card.size.x
		and price_or_state.position.y + price_or_state.size.y <= card.size.y
	).is_true()


func test_shared_card_uses_one_rarity_accent_and_the_shared_hud_surface() -> void:
	if not FileAccess.file_exists(CARD_PRESENTER_PATH):
		return
	var presenter := load(CARD_PRESENTER_PATH) as GDScript
	var definition := GogoItemDefinition.new()
	definition.content_id = &"fixture:item/rare"
	definition.display_name = "稀有道具"
	definition.tier = 3
	var snapshot := _static_ui_snapshot()
	var card := auto_free(presenter.build_card(definition, "已装备", snapshot)) as Control
	assert_bool(card.has_node("Frame")).is_false()
	assert_bool(
		(card.get_node("RarityAccent") as ColorRect).color.is_equal_approx(Color("c65ce2"))
	).is_true()
	var normal := (card as Button).get_theme_stylebox(&"normal")
	assert_bool(normal is StyleBoxFlat).is_true()
	if normal is StyleBoxFlat:
		assert_bool(
			(normal as StyleBoxFlat).bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL)
		).is_true()
		assert_int((normal as StyleBoxFlat).border_width_left).is_equal(1)
	var focus := (card as Button).get_theme_stylebox(&"focus") as StyleBoxFlat
	assert_object(focus).is_not_null()
	if focus != null:
		assert_bool(focus.bg_color.is_equal_approx(HUD_SKIN.COLOR_CONTROL_FOCUS)).is_true()
		assert_int(focus.border_width_left).is_equal(1)


func test_shared_card_keeps_the_rarity_palette_when_ui_textures_are_missing() -> void:
	if not FileAccess.file_exists(CARD_PRESENTER_PATH):
		return
	var presenter := load(CARD_PRESENTER_PATH) as GDScript
	var snapshot := _static_ui_snapshot(false)
	var expected_by_tier := {
		2: Color("4c88df"),
		3: Color("c65ce2"),
		4: Color("f1ca52"),
	}
	for tier_variant: Variant in expected_by_tier:
		var tier := int(tier_variant)
		var definition := GogoItemDefinition.new()
		definition.content_id = StringName("fixture:item/tier_%d" % tier)
		definition.display_name = "回退稀有度 %d" % tier
		definition.tier = tier
		var card := auto_free(presenter.build_card(definition, "已装备", snapshot)) as Control
		assert_bool(
			(card.get_node("RarityAccent") as ColorRect).color.is_equal_approx(
				expected_by_tier[tier] as Color
			)
		).is_true()


func test_real_selection_shop_and_upgrade_routes_use_structured_setup_consumers() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	add_child(app)
	app.begin_selection()
	var static_snapshot := _static_ui_snapshot()

	var character_screen := auto_free(CHARACTER_SELECT.new()) as GogoScreenBase
	character_screen.static_asset_snapshot_override = static_snapshot
	add_child(character_screen)
	var roster := character_screen.get_node("RosterStrip") as GridContainer
	assert_int(roster.columns).is_equal(6)
	assert_int(roster.get_child_count()).is_equal(24)
	assert_str(String(
		(character_screen.get_node("RosterStrip/NikoCell") as Button).get_meta(&"content_id", &"")
	)).is_equal(String(NikoContentFactory.CHARACTER_ID))
	var unavailable_count := 0
	for child in roster.get_children():
		var cell := child as Button
		if cell.name == &"NikoCell":
			continue
		unavailable_count += 1
		assert_str(cell.text).is_empty()
		assert_str((cell.get_node("Status") as Label).text).is_equal("未开放")
		assert_bool(cell.disabled).is_true()
		assert_int(cell.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(cell.has_meta(&"content_id")).is_false()
		assert_bool(cell.has_meta(&"definition")).is_false()
		assert_int(cell.get_signal_connection_list(&"pressed").size()).is_equal(0)
	assert_int(unavailable_count).is_equal(23)
	assert_object((character_screen.get_node("NikoDetail/Preview") as TextureRect).texture).is_not_null()
	assert_int((character_screen.get_node("NikoDetail/Preview") as TextureRect).texture_filter).is_equal(
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	_assert_button_uses_authored_states(character_screen.get_node("BackButton") as Button)
	var change := character_screen.get_node("ChangeCharacterButton") as Button
	assert_bool(change.visible).is_false()
	assert_bool(change.disabled).is_true()
	_assert_button_uses_authored_states(change)

	var niko_cell := character_screen.get_node("RosterStrip/NikoCell") as Button
	niko_cell.pressed.emit()
	assert_bool(roster.visible).is_false()
	assert_bool((character_screen.get_node("WeaponStage") as Control).visible).is_true()
	var weapon_strip := character_screen.get_node("WeaponStage/WeaponColumns") as HBoxContainer
	var weapon_options := weapon_strip.find_children("WeaponOption*", "Button", true, false)
	assert_int(weapon_options.size()).is_equal(12)
	assert_bool(character_screen.has_node("WeaponStage/SelectedWeaponDetail/Mode")).is_true()
	var ranged_option: Button = null
	for option in weapon_options:
		var button := option as Button
		assert_bool(
			(button.get_node("Icon") as TextureRect).texture != null
			or (button.get_node("IconFallback") as Control).visible
		).is_true()
		if StringName(button.get_meta(&"content_id", &"")) == ValidationContentFactory.RANGED_ID:
			ranged_option = button
	assert_object(ranged_option).is_not_null()
	if ranged_option == null:
		return
	ranged_option.pressed.emit()
	assert_str(String(app.selection_draft.get("character_id", &""))).is_equal(
		String(NikoContentFactory.CHARACTER_ID)
	)
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_equal(
		String(ValidationContentFactory.RANGED_ID)
	)
	assert_object(app.current_session).is_null()
	assert_bool((character_screen.get_node("DifficultyStage") as Control).visible).is_true()
	var difficulty_strip := character_screen.get_node("DifficultyStage/DifficultyStrip") as HBoxContainer
	assert_int(difficulty_strip.get_child_count()).is_equal(1)
	var difficulty_option := difficulty_strip.get_child(0) as Button
	var difficulty_badge := static_snapshot.resolve_global(&"difficulty_badge_kit", &"standard")
	assert_object(difficulty_badge).is_not_null()
	if difficulty_badge != null:
		assert_object((difficulty_option.get_node("Icon") as TextureRect).texture).is_same(
			difficulty_badge.texture
		)
	assert_str(String(difficulty_option.get_meta(&"content_id", &""))).is_equal(
		String(ValidationContentFactory.DIFFICULTY_ID)
	)
	assert_str((difficulty_option.get_node("Title") as Label).text).is_equal("标准")
	var difficulty_multipliers := (difficulty_option.get_node("Multipliers") as Label).text
	assert_str(difficulty_multipliers).contains("生命 100%")
	assert_str(difficulty_multipliers).contains("伤害 100%")
	assert_str((difficulty_option.get_node("StartCue") as Label).text).is_equal("开始")
	var difficulty_definition := content.definition(
		ValidationContentFactory.DIFFICULTY_ID, &"difficulty"
	) as GogoDifficultyDefinition
	assert_float(difficulty_definition.enemy_health_multiplier).is_equal(1.0)
	assert_float(difficulty_definition.enemy_damage_multiplier).is_equal(1.0)
	assert_float(difficulty_definition.enemy_speed_multiplier).is_equal(1.0)
	assert_float(difficulty_definition.spawn_multiplier).is_equal(1.0)
	assert_object(app.current_session).is_null()

	var session := _session(content)
	app.current_session = session
	assert_int(session.transition(&"shop")).is_equal(OK)
	var shop_screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	shop_screen.static_asset_snapshot_override = static_snapshot
	add_child(shop_screen)
	var offer_row := shop_screen.get_node("OfferRow") as HBoxContainer
	assert_int(offer_row.get_child_count()).is_equal(4)
	for slot in offer_row.get_children():
		var card := (slot as Node).get_node_or_null("Card") as Button
		var lock := (slot as Node).get_node_or_null("Lock") as Button
		assert_object(card).is_not_null()
		assert_object(lock).is_not_null()
		if card != null:
			var shop_style := card.get_theme_stylebox(&"normal") as StyleBoxTexture
			assert_object(shop_style).is_not_null()
			if shop_style != null:
				assert_object(shop_style.texture).is_same(HUD_SKIN.SHOP_CARD_TEXTURE)
			assert_bool(card.get_theme_stylebox(&"focus") is StyleBoxFlat).is_true()
			assert_bool(card.has_node("RarityAccent")).is_false()
		if lock != null:
			_assert_button_uses_authored_states(lock)
			_assert_shop_button_matches_continue_typography_and_fit(
				lock,
				shop_screen.get_node("ContinueButton") as Button
			)
	_assert_button_uses_authored_states(
		shop_screen.get_node("TopBand/Reroll") as Button,
	)
	var continue_button := shop_screen.get_node("ContinueButton") as Button
	_assert_button_uses_authored_states(continue_button)
	_assert_shop_button_matches_continue_typography_and_fit(
		shop_screen.get_node("TopBand/Reroll") as Button,
		continue_button
	)

	var upgrade_session := _session(content)
	upgrade_session.run_state.pending_upgrade_count = 1
	assert_int(upgrade_session.transition(&"upgrade")).is_equal(OK)
	app.current_session = upgrade_session
	var upgrade_screen := auto_free(UPGRADE_SCREEN.new()) as GogoScreenBase
	upgrade_screen.static_asset_snapshot_override = static_snapshot
	add_child(upgrade_screen)
	var upgrade_choices := upgrade_screen.get_node("UpgradeChoiceRow") as HBoxContainer
	assert_int(upgrade_choices.get_child_count()).is_equal(4)
	for choice in upgrade_choices.get_children():
		assert_bool((choice as Button).get_theme_stylebox(&"normal") is StyleBoxFlat).is_true()
	_assert_button_uses_expected_static_states(
		upgrade_screen.get_node("RerollButton") as Button,
		static_snapshot
	)


func _static_ui_snapshot(include_selectors: bool = true) -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	var global_bindings: Dictionary = {}
	for spec in [
		[&"menu_background", Vector2i(1920, 1080)],
		[&"nine_slice_panel", Vector2i(64, 64)],
		[&"gogobro_wordmark", Vector2i(1024, 256)],
		[&"four_state_button", Vector2i(64, 64)],
		[&"card_and_rarity_frame_kit", Vector2i(64, 64)],
		[&"zone_thumbnail", Vector2i(256, 144)],
	]:
		_add_global_handle(handles, global_bindings, spec[0], spec[1])
	if include_selectors:
		for selector: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
			_add_global_handle(
				handles,
				global_bindings,
				&"four_state_button",
				Vector2i(64, 64),
				selector
			)
		for selector: StringName in [
			&"common",
			&"uncommon",
			&"rare",
			&"legendary",
		]:
			_add_global_handle(
				handles,
				global_bindings,
				&"card_and_rarity_frame_kit",
				Vector2i(64, 64),
				selector
			)
	_add_global_handle(
		handles,
		global_bindings,
		&"difficulty_badge_kit",
		Vector2i(64, 64),
		&"standard"
	)
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "fixture", 70, {}, handles, {}, {}, global_bindings, [])
	return snapshot


func _assert_flat_setup_back_button(button: Button) -> void:
	assert_int(button.z_index).is_equal(10)
	assert_bool(button.position.x >= 24.0 and button.position.x <= 40.0).is_true()
	assert_bool(button.get_theme_stylebox(&"normal") is StyleBoxEmpty).is_true()
	var parent := button.get_parent()
	assert_bool(parent != null and parent.has_node("BackButtonVisual/Label")).is_true()
	if parent == null or not parent.has_node("BackButtonVisual/Label"):
		return
	var visual := parent.get_node("BackButtonVisual") as Panel
	assert_str((visual.get_node("Label") as Label).text).is_equal("← 返回")
	var normal := visual.get_theme_stylebox(&"panel")
	assert_bool(normal is StyleBoxFlat).is_true()
	if not normal is StyleBoxFlat:
		return
	var flat := normal as StyleBoxFlat
	assert_int(flat.border_width_left).is_equal(1)
	assert_bool(flat.anti_aliasing).is_false()


func _assert_button_uses_expected_static_states(
	button: Button,
	_snapshot: GogoStaticAssetSnapshot
) -> void:
	var expected_colors := {
		&"normal": HUD_SKIN.COLOR_CONTROL,
		&"hover": HUD_SKIN.COLOR_CONTROL_FOCUS,
		&"pressed": HUD_SKIN.COLOR_CONTROL_PRESSED,
		&"disabled": HUD_SKIN.COLOR_CONTROL_DISABLED,
	}
	for state: StringName in expected_colors:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		assert_object(style).is_not_null()
		if style == null:
			continue
		assert_bool(style.bg_color.is_equal_approx(expected_colors[state] as Color)).is_true()
		assert_int(style.border_width_left).is_equal(1)


func _assert_button_uses_authored_states(button: Button) -> void:
	var expected_textures := {
		&"normal": HUD_SKIN.BUTTON_NORMAL,
		&"hover": HUD_SKIN.BUTTON_FOCUS,
		&"focus": HUD_SKIN.BUTTON_FOCUS,
		&"pressed": HUD_SKIN.BUTTON_PRESSED,
		&"disabled": HUD_SKIN.BUTTON_DISABLED,
	}
	for state: StringName in expected_textures:
		var style := button.get_theme_stylebox(state) as StyleBoxTexture
		assert_object(style).is_not_null()
		if style == null:
			continue
		assert_object(style.texture).is_same(expected_textures[state] as Texture2D)
		assert_float(style.get_texture_margin(SIDE_LEFT)).is_equal(
			HUD_SKIN.BUTTON_PATCH_MARGIN
		)
		assert_float(style.get_content_margin(SIDE_LEFT)).is_equal(18.0)
		assert_float(style.get_content_margin(SIDE_TOP)).is_equal(8.0)


func _assert_shop_button_matches_continue_typography_and_fit(
	button: Button,
	continue_button: Button
) -> void:
	assert_int(button.get_theme_font_size(&"font_size")).is_equal(
		continue_button.get_theme_font_size(&"font_size")
	)
	assert_vector(button.custom_minimum_size).is_equal(Vector2(216, 56))
	assert_vector(button.size).is_equal(Vector2(216, 56))
	var font := button.get_theme_font(&"font")
	assert_object(font).is_not_null()
	if font == null:
		return
	var normal_style := button.get_theme_stylebox(&"normal") as StyleBoxTexture
	assert_object(normal_style).is_not_null()
	if normal_style == null:
		return
	var available_width := (
		button.size.x
		- normal_style.get_content_margin(SIDE_LEFT)
		- normal_style.get_content_margin(SIDE_RIGHT)
	)
	var text_width := font.get_string_size(
		button.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		button.get_theme_font_size(&"font_size")
	).x
	assert_bool(text_width <= available_width).is_true()


func _add_global_handle(
	handles: Dictionary,
	global_bindings: Dictionary,
	asset_id: StringName,
	display_size: Vector2i,
	selector: StringName = &""
) -> void:
	var asset_key := "%s|%s|%s" % [asset_id, asset_id, selector]
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": StringName(asset_key),
		"asset_id": asset_id,
		"role": asset_id,
		"selector": selector,
		"display_size_px": display_size,
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(display_size / 2),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(Vector2i.ZERO, display_size),
	}, _texture(display_size, selector))
	handles[asset_key] = handle
	global_bindings["global||%s|%s" % [asset_id, selector]] = asset_key


func _session(content: ContentSnapshot) -> GameSession:
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = NikoContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	return session


func _empty_snapshot() -> GogoStaticAssetSnapshot:
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(1, "empty", 70, {}, {}, {}, {}, {}, [])
	return snapshot


func _texture(size: Vector2i, selector: StringName = &"") -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var selector_colors := {
		&"common": Color("8d9487"),
		&"uncommon": Color("4c88df"),
		&"rare": Color("c65ce2"),
		&"legendary": Color("f1ca52"),
	}
	image.fill(selector_colors.get(selector, Color8(51, 59, 62, 255)) as Color)
	return ImageTexture.create_from_image(image)
