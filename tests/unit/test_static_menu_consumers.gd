extends GdUnitTestSuite


const CARD_PRESENTER_PATH := "res://game/ui/static_card_presenter.gd"
const MAIN_MENU := preload("res://game/ui/main_menu_screen.gd")
const CHARACTER_SELECT := preload("res://game/ui/character_select_screen.gd")
const WEAPON_SELECT := preload("res://game/ui/weapon_select_screen.gd")
const DIFFICULTY_SELECT := preload("res://game/ui/difficulty_select_screen.gd")
const SHOP_SCREEN := preload("res://game/ui/shop_screen.gd")
const UPGRADE_SCREEN := preload("res://game/ui/upgrade_screen.gd")


func test_shared_static_card_presenter_exists() -> void:
	assert_bool(FileAccess.file_exists(CARD_PRESENTER_PATH)).is_true()


func test_main_menu_consumes_background_wordmark_and_button_without_a_viewport_frame() -> void:
	var snapshot := _static_ui_snapshot()
	var screen := auto_free(MAIN_MENU.new()) as GogoScreenBase
	screen.set("static_asset_snapshot_override", snapshot)
	add_child(screen)
	var background := screen.get_node("StaticMenuBackground") as TextureRect
	var content_root := screen.get_node("ContentRoot") as Control
	var wordmark := screen.get_node("ContentRoot/Body/Wordmark") as TextureRect
	var start_button := screen.get_node("ContentRoot/Body/StartButton") as Button
	assert_object(background.texture).is_not_null()
	assert_object(content_root).is_not_null()
	assert_int(screen.find_children("StaticNineSlicePanel", "*", true, false).size()).is_equal(0)
	assert_object(wordmark.texture).is_not_null()
	var all_states_use_textures := true
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		all_states_use_textures = (
			all_states_use_textures
			and start_button.get_theme_stylebox(state) is StyleBoxTexture
		)
	assert_bool(all_states_use_textures).is_true()
	if all_states_use_textures:
		for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
			var style := start_button.get_theme_stylebox(state) as StyleBoxTexture
			assert_object((style as StyleBoxTexture).texture).is_same(
				snapshot.resolve_global(&"four_state_button", state).texture
			)
	assert_object(screen.theme).is_not_null()
	assert_bool(start_button.disabled).is_false()


func test_action_button_uses_empty_selector_texture_for_all_states_when_atlas_has_no_selectors() -> void:
	var snapshot := _static_ui_snapshot(false)
	var screen := auto_free(GogoScreenBase.new()) as GogoScreenBase
	screen.static_asset_snapshot_override = snapshot
	add_child(screen)
	screen.build_screen("兼容按钮")
	var button := screen.add_action("开始", func() -> void: pass)
	var fallback := snapshot.resolve_global(&"four_state_button").texture
	var all_states_use_fallback := true
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style := button.get_theme_stylebox(state)
		all_states_use_fallback = (
			all_states_use_fallback
			and style is StyleBoxTexture
			and (style as StyleBoxTexture).texture == fallback
		)
	assert_bool(all_states_use_fallback).is_true()


func test_missing_icon_keeps_shared_text_card_selectable_and_complete() -> void:
	if not FileAccess.file_exists(CARD_PRESENTER_PATH):
		return
	var presenter := load(CARD_PRESENTER_PATH) as GDScript
	var definition := GogoItemDefinition.new()
	definition.content_id = &"fixture:item/no_texture"
	definition.display_name = "无贴图道具"
	definition.tier = 2
	definition.stat_modifiers = {&"armor": 1.0}
	var card := auto_free(presenter.build_card(definition, "12 材料", _empty_snapshot())) as Control
	assert_bool(card.has_node("Icon")).is_true()
	assert_bool(card.has_node("Name")).is_true()
	assert_bool(card.has_node("RarityAccent")).is_true()
	assert_bool(card.has_node("RarityLabel")).is_true()
	assert_bool(card.has_node("StatRows/Stat1")).is_true()
	assert_bool(card.has_node("StatRows/Stat2")).is_true()
	assert_bool(card.has_node("PriceOrState")).is_true()
	assert_bool(card.mouse_filter != Control.MOUSE_FILTER_IGNORE).is_true()
	assert_str((card.get_node("Name") as Label).text).is_equal("无贴图道具")
	assert_str((card.get_node("PriceOrState") as Label).text).is_equal("12 材料")
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


func test_shared_card_uses_one_flat_rarity_accent_without_an_authored_frame() -> void:
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
		assert_int((normal as StyleBoxFlat).border_width_left).is_equal(1)
		assert_bool((normal as StyleBoxFlat).anti_aliasing).is_false()


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


func test_real_selection_shop_and_upgrade_routes_use_zone_badge_and_shared_cards() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = content
	add_child(app)
	var static_snapshot := _static_ui_snapshot()

	var character_screen := auto_free(CHARACTER_SELECT.new()) as GogoScreenBase
	character_screen.static_asset_snapshot_override = static_snapshot
	add_child(character_screen)
	assert_object((character_screen.get_node(
		"ContentRoot/Body/ZoneThumbnail"
	) as TextureRect).texture).is_not_null()

	var weapon_screen := auto_free(WEAPON_SELECT.new()) as GogoScreenBase
	weapon_screen.static_asset_snapshot_override = static_snapshot
	add_child(weapon_screen)
	assert_int(weapon_screen.get_node(
		"ContentRoot/Body/WeaponCardGrid"
	).get_child_count()).is_equal(12)

	var difficulty_screen := auto_free(DIFFICULTY_SELECT.new()) as GogoScreenBase
	difficulty_screen.static_asset_snapshot_override = static_snapshot
	add_child(difficulty_screen)
	var difficulty_buttons := difficulty_screen.find_children("*", "Button", true, false)
	assert_bool(difficulty_buttons.size() >= 2).is_true()
	assert_object((difficulty_buttons[0] as Button).icon).is_not_null()

	var session := _session(content)
	app.current_session = session
	assert_int(session.transition(&"shop")).is_equal(OK)
	var shop_screen := auto_free(SHOP_SCREEN.new()) as GogoScreenBase
	shop_screen.static_asset_snapshot_override = static_snapshot
	add_child(shop_screen)
	var offer_row := shop_screen.get_node("OfferRow") as HBoxContainer
	assert_int(offer_row.get_child_count()).is_equal(4)
	for slot in offer_row.get_children():
		assert_object((slot as Node).get_node_or_null("Card") as Button).is_not_null()

	var upgrade_session := _session(content)
	upgrade_session.run_state.pending_upgrade_count = 1
	assert_int(upgrade_session.transition(&"upgrade")).is_equal(OK)
	app.current_session = upgrade_session
	var upgrade_screen := auto_free(UPGRADE_SCREEN.new()) as GogoScreenBase
	upgrade_screen.static_asset_snapshot_override = static_snapshot
	add_child(upgrade_screen)
	assert_int(upgrade_screen.get_node(
		"ContentRoot/Body/UpgradeCardGrid"
	).get_child_count()).is_equal(3)


func _static_ui_snapshot(include_selectors: bool = true) -> GogoStaticAssetSnapshot:
	var handles: Dictionary = {}
	var global_bindings: Dictionary = {}
	for spec in [
		[&"menu_background", Vector2i(1920, 1080)],
		[&"nine_slice_panel", Vector2i(64, 64)],
		[&"gogobro_wordmark", Vector2i(1024, 256)],
		[&"four_state_button", Vector2i(64, 64)],
		[&"card_and_rarity_frame_kit", Vector2i(64, 64)],
		[&"zone_thumbnail", Vector2i(512, 288)],
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
