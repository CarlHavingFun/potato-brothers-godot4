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


func test_main_menu_consumes_background_wordmark_panel_and_button_without_losing_fallbacks() -> void:
	var screen := auto_free(MAIN_MENU.new()) as GogoScreenBase
	screen.set("static_asset_snapshot_override", _static_ui_snapshot())
	add_child(screen)
	var background := screen.get_node("StaticMenuBackground") as TextureRect
	var panel := screen.get_node("Center/StaticNineSlicePanel") as Control
	var wordmark := screen.get_node("Center/StaticNineSlicePanel/Body/Wordmark") as TextureRect
	var start_button := screen.get_node("Center/StaticNineSlicePanel/Body/StartButton") as Button
	assert_object(background.texture).is_not_null()
	assert_object(panel).is_not_null()
	assert_object(wordmark.texture).is_not_null()
	assert_object(start_button.get_meta(&"static_four_state_texture", null)).is_not_null()
	assert_object(screen.theme).is_not_null()
	assert_bool(start_button.disabled).is_false()


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
	assert_bool(card.has_node("Tier")).is_true()
	assert_bool(card.has_node("StatLine")).is_true()
	assert_bool(card.has_node("PriceOrState")).is_true()
	assert_bool(card.mouse_filter != Control.MOUSE_FILTER_IGNORE).is_true()
	assert_str((card.get_node("Name") as Label).text).is_equal("无贴图道具")
	assert_str((card.get_node("PriceOrState") as Label).text).is_equal("12 材料")
	assert_object((card.get_node("Icon") as TextureRect).texture).is_null()


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
		"Center/StaticNineSlicePanel/Body/ZoneThumbnail"
	) as TextureRect).texture).is_not_null()

	var weapon_screen := auto_free(WEAPON_SELECT.new()) as GogoScreenBase
	weapon_screen.static_asset_snapshot_override = static_snapshot
	add_child(weapon_screen)
	assert_int(weapon_screen.get_node(
		"Center/StaticNineSlicePanel/Body/WeaponCardGrid"
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
	assert_int(shop_screen.find_children("StaticCard", "Button", true, false).size()).is_equal(4)

	var upgrade_session := _session(content)
	upgrade_session.run_state.pending_upgrade_count = 1
	assert_int(upgrade_session.transition(&"upgrade")).is_equal(OK)
	app.current_session = upgrade_session
	var upgrade_screen := auto_free(UPGRADE_SCREEN.new()) as GogoScreenBase
	upgrade_screen.static_asset_snapshot_override = static_snapshot
	add_child(upgrade_screen)
	assert_int(upgrade_screen.get_node(
		"Center/StaticNineSlicePanel/Body/UpgradeCardGrid"
	).get_child_count()).is_equal(3)


func _static_ui_snapshot() -> GogoStaticAssetSnapshot:
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
	}, _texture(display_size))
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


func _texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color8(51, 59, 62, 255))
	return ImageTexture.create_from_image(image)
