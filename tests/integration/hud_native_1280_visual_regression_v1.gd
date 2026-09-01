extends GdUnitTestSuite


const APP_SCENE := preload("res://game/app/app_root.tscn")
const CAPTURE_SIZE := Vector2i(1280, 720)
const OUTPUT_DIR_URI := "user://hud-native-1280-visual-regression-v1"
const MAIN_MENU_URI := OUTPUT_DIR_URI + "/hud-main-menu-1280x720.png"
const BUTTON_STATES_URI := OUTPUT_DIR_URI + "/hud-button-states-1280x720.png"
const CHARACTER_SELECT_URI := OUTPUT_DIR_URI + "/hud-character-select-1280x720.png"
const COMBAT_URI := OUTPUT_DIR_URI + "/hud-combat-1280x720.png"
const SHOP_FULL_URI := OUTPUT_DIR_URI + "/hud-shop-full-1280x720.png"
const SHOP_SOLD_SLOT0_URI := OUTPUT_DIR_URI + "/hud-shop-sold-slot0-1280x720.png"
const SHOP_SOLD_SLOT2_URI := OUTPUT_DIR_URI + "/hud-shop-sold-slot2-1280x720.png"
const PAUSE_ITEMS_URI := OUTPUT_DIR_URI + "/hud-pause-items-1280x720.png"
const PAUSE_CONFIRMATION_URI := OUTPUT_DIR_URI + "/hud-pause-confirmation-1280x720.png"
const REPORT_URI := OUTPUT_DIR_URI + "/hud-native-1280-visual-regression-v1.json"
const AK_ID: StringName = &"gogobro.preview:weapon/wood_stock_assault_rifle"
const KARAMBIT_ID: StringName = &"gogobro.preview:weapon/community_tapper"


func test_capture_real_main_character_shop_and_combat_pause_at_1280() -> void:
	var root_viewport := auto_free(SubViewport.new()) as SubViewport
	root_viewport.size = CAPTURE_SIZE
	root_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(root_viewport)

	var app := APP_SCENE.instantiate() as AppKernel
	root_viewport.add_child(app)
	await _settle_frames()
	assert_object(app.boot_result).is_not_null()
	assert_bool(app.boot_result != null and app.boot_result.is_ok()).is_true()
	if app.boot_result == null or not app.boot_result.is_ok():
		return
	assert_bool(_hud_component_textures_are_clean()).is_true()
	var host := app.get_node("SceneHost") as Node
	var captures: Array[Dictionary] = []

	var main_menu := _current_screen(host)
	assert_bool(_is_actual_route(main_menu, "res://game/ui/main_menu_screen.gd")).is_true()
	if main_menu == null:
		return
	var start_button := main_menu.get_node("ContentRoot/Body/MenuActions/StartButton") as Button
	var exit_button := main_menu.get_node("ContentRoot/Body/MenuActions/ExitButton") as Button
	assert_float(start_button.size.y).is_greater_equal(GogoHudSkin.BUTTON_HEIGHT_PRIMARY)
	assert_float(exit_button.size.y).is_greater_equal(GogoHudSkin.BUTTON_HEIGHT_STANDARD)
	assert_bool(_button_has_one_complete_background(start_button)).is_true()
	assert_bool(_button_has_one_complete_background(exit_button)).is_true()
	captures.append(await _capture(root_viewport, MAIN_MENU_URI, &"main_menu", main_menu))

	app.begin_selection()
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle_frames()
	var character_select := _current_screen(host)
	assert_bool(_is_actual_route(
		character_select,
		"res://game/ui/character_select_screen.gd"
	)).is_true()
	assert_bool(_fits_capture(character_select.get_node("BackButton") as Control)).is_true()
	assert_bool(_fits_capture(character_select.get_node("NikoDetail") as Control)).is_true()
	assert_bool(_fits_capture(character_select.get_node("RosterCaption") as Control)).is_true()
	var roster := character_select.get_node("RosterStrip") as GridContainer
	assert_bool(_fits_capture(roster)).is_true()
	assert_int(roster.columns).is_equal(8)
	assert_int(roster.get_child_count()).is_equal(24)
	var character_cell := character_select.get_node("RosterStrip/NikoCell") as Button
	assert_str(String(character_cell.get_meta(&"content_id", &""))).is_equal(
		String(NikoContentFactory.CHARACTER_ID)
	)
	assert_bool(character_cell.custom_minimum_size.is_equal_approx(Vector2(104, 112))).is_true()
	var unavailable_count := 0
	for child in roster.get_children():
		var cell := child as Button
		assert_bool(_fits_capture(cell)).is_true()
		if cell == character_cell:
			continue
		unavailable_count += 1
		assert_str(String(cell.name)).starts_with("UnavailableCharacterSlot")
		assert_str(cell.text).is_empty()
		assert_str((cell.get_node("Status") as Label).text).is_equal("待开放")
		assert_str((cell.get_node("Glyph") as Label).text).is_equal("空位")
		assert_bool(cell.disabled).is_true()
		assert_int(cell.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(cell.has_meta(&"content_id")).is_false()
		assert_bool(cell.has_meta(&"definition")).is_false()
		assert_int(cell.get_signal_connection_list(&"pressed").size()).is_equal(0)
	assert_int(unavailable_count).is_equal(23)
	var change_character := character_select.get_node("ChangeCharacterButton") as Button
	assert_bool(_fits_capture(change_character)).is_true()
	assert_bool(change_character.visible).is_false()
	assert_bool(change_character.disabled).is_true()
	assert_bool(_button_has_authored_states(change_character)).is_true()
	var focused_character_style := character_cell.get_theme_stylebox(&"focus")
	assert_bool(focused_character_style is StyleBoxFlat).is_true()
	if focused_character_style is StyleBoxFlat:
		assert_bool(
			(focused_character_style as StyleBoxFlat).bg_color.get_luminance() > 0.70
		).is_true()
	assert_object(root_viewport.gui_get_focus_owner()).is_same(character_cell)
	captures.append(await _capture(
		root_viewport,
		CHARACTER_SELECT_URI,
		&"character_select",
		character_select
	))

	app.selection_draft["character_id"] = ValidationContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = AK_ID
	app.selection_draft["difficulty_id"] = ValidationContentFactory.DIFFICULTY_ID
	app.selection_draft["zone_id"] = ValidationContentFactory.ZONE_ID
	assert_int(app.create_session_from_draft()).is_equal(OK)
	if app.current_session == null:
		return
	var player := app.current_session.run_state.player()
	player.materials = 9999
	player.weapon_inventory = preload("res://game/session/weapon_inventory.gd").new()
	for weapon_id in [AK_ID, ValidationContentFactory.MELEE_ID, KARAMBIT_ID]:
		player.weapon_inventory.add_weapon(weapon_id, app.content_snapshot)
	for item in app.content_snapshot.all(&"item"):
		if player.item_ids.size() >= 12:
			break
		var item_definition := item as GogoItemDefinition
		if item_definition != null and not player.item_ids.has(item_definition.content_id):
			player.item_ids.append(item_definition.content_id)

	assert_int(app.route(FlowRoute.COMBAT)).is_equal(OK)
	await _settle_frames()
	var combat := _current_screen(host)
	var combat_script_path := (
		(combat.get_script() as Script).resource_path
		if combat != null and combat.get_script() != null
		else ""
	)
	assert_bool(combat_script_path.contains("game/ui/combat_screen.gd")).is_true()
	if combat == null:
		return
	captures.append(await _capture(root_viewport, COMBAT_URI, &"combat_hud", combat))
	combat.call("_open_pause")
	await _settle_frames()
	var pause := combat.get_node("PauseCanvas/PauseOverlay") as Control
	assert_bool(pause.visible).is_true()
	assert_vector(pause.size).is_equal(Vector2(CAPTURE_SIZE))
	assert_str((pause.get_node("Loadout/ItemsTitle") as Label).text).is_equal("道具")
	assert_bool((pause.get_node("Loadout/WeaponsTitle") as Label).text.begins_with("武器")).is_true()
	assert_bool(pause.get_node_or_null("Loadout/Backing") == null).is_true()
	assert_bool(pause.has_node("Loadout/WeaponsDivider")).is_true()
	assert_bool(pause.has_node("Loadout/ItemsDivider")).is_true()
	var item_grid := pause.get_node_or_null("Loadout/ItemsScroll/ItemsGrid") as GridContainer
	assert_object(item_grid).is_not_null()
	if item_grid != null:
		assert_int(item_grid.get_child_count()).is_equal(12)
		assert_int(item_grid.columns).is_equal(8)
	var first_pause_item := pause.get_node_or_null(
		"Loadout/ItemsScroll/ItemsGrid/ItemIcon0"
	) as Control
	assert_object(first_pause_item).is_not_null()
	if first_pause_item != null:
		assert_float(first_pause_item.size.x).is_greater_equal(64.0)
		assert_float(first_pause_item.size.y).is_greater_equal(64.0)
	assert_bool(_fits_capture(pause.get_node("PauseMenu") as Control)).is_true()
	assert_bool(_fits_capture(pause.get_node("Loadout") as Control)).is_true()
	assert_bool(_fits_capture(pause.get_node("StatsColumn") as Control)).is_true()
	assert_bool(_fits_capture(pause.get_node("WaveProgress") as Control)).is_true()
	captures.append(await _capture(
		root_viewport,
		PAUSE_ITEMS_URI,
		&"pause_items",
		combat
	))
	var pause_continue := pause.get_node("PauseMenu/ContinueButton") as Button
	var pause_restart := pause.get_node("PauseMenu/RestartButton") as Button
	var pause_end_run := pause.get_node("PauseMenu/EndRunButton") as Button
	var pause_settings := pause.get_node("PauseMenu/SettingsButton") as Button
	var pause_return := pause.get_node("PauseMenu/ReturnButton") as Button
	for button in [
		pause_continue,
		pause_restart,
		pause_end_run,
		pause_settings,
		pause_return,
	]:
		assert_bool(_button_has_authored_states(button as Button)).is_true()
	pause_end_run.toggle_mode = true
	pause_end_run.button_pressed = true
	pause_return.disabled = true
	pause_continue.grab_focus()
	var hover_motion := InputEventMouseMotion.new()
	hover_motion.position = pause_settings.get_global_rect().get_center()
	root_viewport.push_input(hover_motion)
	await _settle_frames()
	assert_object(root_viewport.gui_get_focus_owner()).is_same(pause_continue)
	if DisplayServer.get_name() != "headless":
		assert_bool(pause_settings.is_hovered()).is_true()
	captures.append(await _capture(
		root_viewport,
		BUTTON_STATES_URI,
		&"button_states",
		combat
	))
	pause_end_run.button_pressed = false
	pause_end_run.toggle_mode = false
	pause_return.disabled = false
	var clear_hover_motion := InputEventMouseMotion.new()
	clear_hover_motion.position = Vector2(1270, 710)
	root_viewport.push_input(clear_hover_motion)
	pause_continue.grab_focus()
	await _settle_frames()

	(pause.get_node("PauseMenu/EndRunButton") as Button).pressed.emit()
	await _settle_frames()
	assert_bool((pause.get_node("ExitConfirmation") as Control).visible).is_true()
	captures.append(await _capture(
		root_viewport,
		PAUSE_CONFIRMATION_URI,
		&"pause_confirmation",
		combat
	))
	(pause.get_node("ExitConfirmation/CancelButton") as Button).pressed.emit()
	combat.call("_resume_from_pause")
	await _settle_frames()
	assert_bool(get_tree().paused).is_false()

	var battlefield_backdrop := combat.call("_capture_battlefield_backdrop") as Texture2D
	assert_int(app.current_session.transition(&"shop")).is_equal(OK)
	assert_int(app.route(FlowRoute.SHOP, {
		"battlefield_backdrop": battlefield_backdrop,
	})).is_equal(OK)
	await _settle_frames()
	var shop := _current_screen(host)
	assert_bool(_is_actual_route(shop, "res://game/ui/shop_screen.gd")).is_true()
	if shop == null:
		return
	var shop_runtime := shop.get("_shop") as ShopRuntimeService
	assert_int(shop_runtime.offers.size()).is_equal(4)
	assert_bool(_shop_non_empty_cards_have_type_labels(shop)).is_true()
	assert_bool(_shop_non_empty_cards_are_single_surface(shop)).is_true()
	assert_bool(_button_has_authored_states(shop.get_node("ContinueButton") as Button)).is_true()
	var offer_description := shop.get_node_or_null("OfferDescription") as Label
	var offer_flavor := shop.get_node_or_null("OfferFlavor") as Label
	assert_object(offer_description).is_not_null()
	assert_object(offer_flavor).is_not_null()
	if offer_description != null and offer_flavor != null:
		assert_str(offer_description.text).is_not_empty()
		assert_str(offer_flavor.text).is_not_empty()
		assert_bool(_fits_capture(offer_description)).is_true()
		assert_bool(_fits_capture(offer_flavor)).is_true()
	assert_bool(_tree_has_forbidden_sold_copy(shop)).is_false()
	var full_focused_cards := _focused_non_empty_offer_cards(shop)
	assert_int(full_focused_cards.size()).is_equal(1)
	if full_focused_cards.size() == 1:
		assert_object(root_viewport.gui_get_focus_owner()).is_same(full_focused_cards[0])
		assert_bool(_offer_focus_uses_light_surface_and_dark_copy(full_focused_cards[0])).is_true()
	captures.append(await _capture(root_viewport, SHOP_FULL_URI, &"shop_full", shop))

	var before_ids: Array[StringName] = []
	for offer in shop_runtime.offers:
		before_ids.append((offer as GogoContentDefinition).content_id if offer != null else &"")
	var third_card := shop.get_node("OfferRow/OfferSlot2/Card") as Button
	third_card.pressed.emit()
	await _settle_frames()
	assert_int(shop_runtime.offers.size()).is_equal(4)
	assert_object(shop_runtime.offers[2]).is_null()
	for index in [0, 1, 3]:
		assert_str(String((shop_runtime.offers[index] as GogoContentDefinition).content_id)).is_equal(
			String(before_ids[index])
		)
	var empty_slot := shop.get_node("OfferRow/OfferSlot2") as VBoxContainer
	assert_bool(empty_slot.get_meta(&"empty_offer_slot", false) as bool).is_true()
	assert_int(empty_slot.get_child_count()).is_zero()
	assert_bool(_tree_has_forbidden_sold_copy(shop)).is_false()
	assert_bool(_shop_non_empty_cards_have_type_labels(shop)).is_true()
	assert_bool(_shop_non_empty_cards_are_single_surface(shop)).is_true()
	var sold_focused_cards := _focused_non_empty_offer_cards(shop)
	assert_int(sold_focused_cards.size()).is_equal(1)
	if sold_focused_cards.size() == 1:
		assert_object(root_viewport.gui_get_focus_owner()).is_same(sold_focused_cards[0])
		assert_bool(_offer_focus_uses_light_surface_and_dark_copy(sold_focused_cards[0])).is_true()
	captures.append(await _capture(
		root_viewport,
		SHOP_SOLD_SLOT2_URI,
		&"shop_sold_slot2",
		shop
	))

	(shop.get_node("TopBand/Reroll") as Button).pressed.emit()
	await _settle_frames()
	for offer in shop_runtime.offers:
		assert_object(offer).is_not_null()
	before_ids.clear()
	for offer in shop_runtime.offers:
		before_ids.append((offer as GogoContentDefinition).content_id)
	var first_card := shop.get_node("OfferRow/OfferSlot0/Card") as Button
	first_card.pressed.emit()
	await _settle_frames()
	assert_object(shop_runtime.offers[0]).is_null()
	for index in range(1, 4):
		assert_str(String((shop_runtime.offers[index] as GogoContentDefinition).content_id)).is_equal(
			String(before_ids[index])
		)
	empty_slot = shop.get_node("OfferRow/OfferSlot0") as VBoxContainer
	assert_bool(empty_slot.get_meta(&"empty_offer_slot", false) as bool).is_true()
	assert_int(empty_slot.get_child_count()).is_zero()
	assert_bool(_tree_has_forbidden_sold_copy(shop)).is_false()
	sold_focused_cards = _focused_non_empty_offer_cards(shop)
	assert_int(sold_focused_cards.size()).is_equal(1)
	if sold_focused_cards.size() == 1:
		assert_object(root_viewport.gui_get_focus_owner()).is_same(sold_focused_cards[0])
		assert_bool(_offer_focus_uses_light_surface_and_dark_copy(sold_focused_cards[0])).is_true()
	captures.append(await _capture(
		root_viewport,
		SHOP_SOLD_SLOT0_URI,
		&"shop_sold_slot0",
		shop
	))

	var report_path := ProjectSettings.globalize_path(REPORT_URI)
	assert_int(DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())).is_equal(OK)
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	assert_object(report_file).is_not_null()
	if report_file != null:
		report_file.store_string(JSON.stringify({
			"schema_version": "gogobro-hud-native-1280-visual-regression-v1",
			"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
			"real_route_capture": true,
			"shop_slots_are_fixed_indices": true,
			"sold_slot0_is_null_and_has_no_children": true,
			"sold_slot2_is_null_and_has_no_children": true,
			"captures": captures,
		}, "\t") + "\n")
		report_file.close()
	print("HUD_NATIVE_1280_VISUAL_REGRESSION_V1_OK report=%s" % report_path)


func _capture(
	viewport: SubViewport,
	uri: String,
	page: StringName,
	real_route_root: Node
) -> Dictionary:
	assert_object(real_route_root).is_not_null()
	await _settle_frames()
	if DisplayServer.get_name() == "headless":
		return {
			"page": String(page),
			"absolute_path": "",
			"sha256": "",
			"capture_mode": "headless-structure",
		}
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert_object(image).is_not_null()
	if image == null:
		return {}
	assert_vector(image.get_size()).is_equal(CAPTURE_SIZE)
	var path := ProjectSettings.globalize_path(uri)
	assert_int(DirAccess.make_dir_recursive_absolute(path.get_base_dir())).is_equal(OK)
	assert_int(image.save_png(path)).is_equal(OK)
	return {
		"page": String(page),
		"absolute_path": path,
		"sha256": FileAccess.get_sha256(path),
		"capture_mode": "native-rendered-route",
	}


func _settle_frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _current_screen(host: Node) -> Node:
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0)


func _is_actual_route(screen: Node, expected_path: String) -> bool:
	return (
		screen != null
		and screen.get_script() != null
		and (screen.get_script() as Script).resource_path == expected_path
	)


func _fits_capture(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	var fits := (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= CAPTURE_SIZE.x
		and rect.end.y <= CAPTURE_SIZE.y
	)
	if not fits:
		print("HUD_CAPTURE_OUT_OF_BOUNDS node=%s rect=%s" % [control.get_path(), rect])
	return fits


func _button_has_one_complete_background(button: Button) -> bool:
	return _button_has_authored_states(button)


func _button_has_authored_states(button: Button) -> bool:
	if button == null or button.get_node_or_null("ButtonFill") != null:
		return false
	var expected_textures := {
		&"normal": GogoHudSkin.BUTTON_NORMAL,
		&"hover": GogoHudSkin.BUTTON_FOCUS,
		&"focus": GogoHudSkin.BUTTON_FOCUS,
		&"pressed": GogoHudSkin.BUTTON_PRESSED,
		&"disabled": GogoHudSkin.BUTTON_DISABLED,
	}
	for state: StringName in expected_textures:
		var style := button.get_theme_stylebox(state) as StyleBoxTexture
		if (
			style == null
			or style.texture != expected_textures[state]
			or not is_equal_approx(
				style.get_texture_margin(SIDE_LEFT),
				GogoHudSkin.BUTTON_PATCH_MARGIN
			)
			or not is_equal_approx(style.get_content_margin(SIDE_LEFT), 18.0)
			or not is_equal_approx(style.get_content_margin(SIDE_TOP), 8.0)
		):
			return false
	return true


func _hud_component_textures_are_clean() -> bool:
	for texture: Texture2D in [
		GogoHudSkin.BUTTON_NORMAL,
		GogoHudSkin.BUTTON_FOCUS,
		GogoHudSkin.BUTTON_PRESSED,
		GogoHudSkin.BUTTON_DISABLED,
		GogoHudSkin.SURFACE_TEXTURE,
		GogoHudSkin.DIALOG_TEXTURE,
		GogoHudSkin.SHOP_CARD_TEXTURE,
		GogoHudSkin.SLOT_TEXTURE,
	]:
		if texture == null or _texture_has_visible_magenta(texture):
			return false
	return true


func _texture_has_visible_magenta(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if (
				pixel.a > 0.05
				and pixel.r >= 20.0 / 255.0
				and pixel.b >= 20.0 / 255.0
				and pixel.g <= 80.0 / 255.0
				and minf(pixel.r, pixel.b) >= pixel.g * 1.3
				and absf(pixel.r - pixel.b) <= 90.0 / 255.0
			):
				return true
	return false


func _shop_non_empty_cards_have_type_labels(shop: Node) -> bool:
	for slot_index in 4:
		var slot := shop.get_node("OfferRow/OfferSlot%d" % slot_index) as VBoxContainer
		var card := slot.get_node_or_null("Card") as Button
		if card == null:
			continue
		var type_badge := card.get_node_or_null("TypeBadge") as Label
		if type_badge == null:
			return false
		if type_badge.text != "道具" and not type_badge.text.begins_with("武器 · "):
			return false
	return true


func _shop_non_empty_cards_are_single_surface(shop: Node) -> bool:
	for slot_index in 4:
		var slot := shop.get_node("OfferRow/OfferSlot%d" % slot_index) as VBoxContainer
		var card := slot.get_node_or_null("Card") as Button
		if card == null:
			continue
		var normal := card.get_theme_stylebox(&"normal") as StyleBoxTexture
		var focus := card.get_theme_stylebox(&"focus") as StyleBoxFlat
		if (
			normal == null
			or focus == null
			or normal.texture != GogoHudSkin.SHOP_CARD_TEXTURE
			or not is_equal_approx(
				normal.get_texture_margin(SIDE_LEFT),
				GogoHudSkin.SHOP_CARD_PATCH_MARGIN
			)
			or focus.border_width_left != 1
			or card.get_node_or_null("RarityAccent") != null
		):
			return false
	return true


func _focused_non_empty_offer_cards(shop: Node) -> Array[Button]:
	var focused: Array[Button] = []
	for slot_index in 4:
		var slot := shop.get_node("OfferRow/OfferSlot%d" % slot_index) as VBoxContainer
		var card := slot.get_node_or_null("Card") as Button
		if card != null and not card.disabled and card.has_focus():
			focused.append(card)
	return focused


func _offer_focus_uses_light_surface_and_dark_copy(card: Button) -> bool:
	var focus := card.get_theme_stylebox(&"focus") as StyleBoxFlat
	if focus == null or not focus.bg_color.is_equal_approx(GogoHudSkin.COLOR_CONTROL_FOCUS):
		return false
	for node in card.find_children("*", "Label", true, false):
		var label := node as Label
		if not label.get_theme_color(&"font_color").is_equal_approx(GogoHudSkin.COLOR_TEXT_FOCUS):
			return false
	return true


func _tree_has_forbidden_sold_copy(root: Node) -> bool:
	for node in root.find_children("*", "Label", true, false):
		var copy := (node as Label).text
		if copy.contains("已售出") or copy.contains("空槽") or copy.contains("等待下次商店"):
			return true
	for node in root.find_children("*", "Button", true, false):
		var copy := (node as Button).text
		if copy.contains("已售出") or copy.contains("空槽") or copy.contains("等待下次商店"):
			return true
	return false
