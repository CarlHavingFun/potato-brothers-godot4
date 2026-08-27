extends GdUnitTestSuite


const OUTPUT_DIR_URI := "user://full-static-assets-menu-v1"
const MAIN_MENU_OUTPUT_URI := OUTPUT_DIR_URI + "/menu-1280x720.png"
const CHARACTER_OUTPUT_URI := OUTPUT_DIR_URI + "/character-select-1280x720.png"
const WEAPON_OUTPUT_URI := OUTPUT_DIR_URI + "/weapon-select-1280x720.png"
const DIFFICULTY_OUTPUT_URI := OUTPUT_DIR_URI + "/difficulty-select-1280x720.png"
const SHOP_OUTPUT_URI := OUTPUT_DIR_URI + "/shop-1280x720.png"
const UPGRADE_OUTPUT_URI := OUTPUT_DIR_URI + "/upgrade-1280x720.png"
const MANIFEST_URI := OUTPUT_DIR_URI + "/route-captures-v1.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const APP_SCENE := preload("res://game/app/app_root.tscn")


func test_capture_actual_menu_and_selection_routes_at_1280() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var root_window := auto_free(SubViewport.new()) as SubViewport
	root_window.size = CAPTURE_SIZE
	root_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(root_window)
	var app := APP_SCENE.instantiate() as AppKernel
	root_window.add_child(app)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(app.boot_result != null and app.boot_result.is_ok(), "application boot"):
		return
	var snapshot := app.static_asset_service.active_snapshot()
	if not _require(snapshot != null and snapshot.is_development_preview(), "development preview assets"):
		return
	if not _require(app.content_snapshot.all(&"character").size() == 1, "Niko-only character scope"):
		return
	var output_dir := ProjectSettings.globalize_path(OUTPUT_DIR_URI)
	if not _require(
		DirAccess.make_dir_recursive_absolute(output_dir) in [OK, ERR_ALREADY_EXISTS],
		"menu capture directory"
	):
		return

	var host := app.get_node("SceneHost") as Node
	var main_menu := _current_screen(host)
	if not _require(_is_actual_route(main_menu, "res://game/ui/main_menu_screen.gd"), "actual main menu route"):
		return
	if not _require(_texture_visible(main_menu, "ContentRoot/Body/Wordmark"), "wordmark consumer"):
		return
	if not _require(_texture_visible(main_menu, "StaticMenuBackground"), "menu background consumer"):
		return
	if not _require(main_menu.get_node_or_null("StaticNineSlicePanel") == null, "low-border menu shell"):
		return
	var start_button := main_menu.get_node_or_null(
		"ContentRoot/Body/StartButton"
	) as Button
	if not _require(
		start_button != null and _button_uses_texture_states(start_button),
		"rendered four-state button consumer"
	):
		return
	var captures: Array[Dictionary] = []
	var capture := await _capture_route(
		root_window,
		main_menu,
		&"main_menu",
		MAIN_MENU_OUTPUT_URI,
		"res://game/ui/main_menu_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	app.begin_selection()
	if not _require(app.route(FlowRoute.CHARACTER_SELECT) == OK, "character selection route"):
		return
	await get_tree().process_frame
	var character_screen := _current_screen(host)
	if not _require(
		_is_actual_route(character_screen, "res://game/ui/character_select_screen.gd"),
		"actual character selection instance"
	):
		return
	if not _require(
		_texture_visible(character_screen, "ContentRoot/Body/ZoneThumbnail"),
		"character route zone thumbnail"
	):
		return
	capture = await _capture_route(
		root_window,
		character_screen,
		&"character_select",
		CHARACTER_OUTPUT_URI,
		"res://game/ui/character_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	app.selection_draft["character_id"] = ValidationContentFactory.CHARACTER_ID
	if not _require(app.route(FlowRoute.WEAPON_SELECT) == OK, "weapon selection route"):
		return
	await get_tree().process_frame
	var weapon_screen := _current_screen(host)
	if not _require(
		_is_actual_route(weapon_screen, "res://game/ui/weapon_select_screen.gd"),
		"actual weapon selection instance"
	):
		return
	var grid := weapon_screen.get_node_or_null(
		"ContentRoot/Body/WeaponCardGrid"
	) as GridContainer
	if not _require(grid != null and grid.get_child_count() >= 12, "weapon card grid"):
		return
	var first_card := grid.get_child(0) as Button
	if not _require(
		_texture_visible(first_card, "Icon")
		and (first_card.get_node("Icon") as TextureRect).size.x >= 64.0
		and _card_uses_low_border_style(first_card),
		"rendered 64px icon and low-border card"
	):
		return
	var weapon_body := weapon_screen.get_node(
		"ContentRoot/Body"
	) as VBoxContainer
	var return_button := weapon_body.get_child(weapon_body.get_child_count() - 1) as Button
	if not _require(
		_control_fits_capture(grid.get_child(grid.get_child_count() - 1) as Control)
		and _control_fits_capture(return_button),
		"complete weapon grid and return action fit the real route capture"
	):
		return
	capture = await _capture_route(
		root_window,
		weapon_screen,
		&"weapon_select",
		WEAPON_OUTPUT_URI,
		"res://game/ui/weapon_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	if not _require(app.route(FlowRoute.DIFFICULTY_SELECT) == OK, "difficulty selection route"):
		return
	await get_tree().process_frame
	var difficulty_screen := _current_screen(host)
	if not _require(
		_is_actual_route(difficulty_screen, "res://game/ui/difficulty_select_screen.gd"),
		"actual difficulty selection instance"
	):
		return
	if not _require(
		_texture_visible(difficulty_screen, "ContentRoot/Body/ZoneThumbnail"),
		"difficulty route zone thumbnail"
	):
		return
	var difficulty_button := _first_button(difficulty_screen)
	if not _require(
		difficulty_button != null
		and difficulty_button.icon != null
		and _button_uses_texture_states(difficulty_button),
		"difficulty badge and rendered button states"
	):
		return
	capture = await _capture_route(
		root_window,
		difficulty_screen,
		&"difficulty_select",
		DIFFICULTY_OUTPUT_URI,
		"res://game/ui/difficulty_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	app.selection_draft["difficulty_id"] = ValidationContentFactory.DIFFICULTY_ID
	app.selection_draft["zone_id"] = ValidationContentFactory.ZONE_ID
	if not _require(app.create_session_from_draft() == OK, "shop session creation"):
		return
	var player := app.current_session.run_state.player()
	player.materials = 500
	player.weapon_ids.append(ValidationContentFactory.RANGED_ID)
	player.weapon_ids.append(ValidationContentFactory.RANGED_ID)
	player.weapon_levels[String(ValidationContentFactory.RANGED_ID)] = 1
	if not _require(app.current_session.transition(&"shop") == OK, "shop phase transition"):
		return
	if not _require(app.route(FlowRoute.SHOP) == OK, "shop route"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var shop_screen := _current_screen(host)
	if not _require(
		_is_actual_route(shop_screen, "res://game/ui/shop_screen.gd"),
		"actual shop instance"
	):
		return
	var offer_row := shop_screen.get_node_or_null("OfferRow") as HBoxContainer
	var loadout := shop_screen.get_node_or_null("LoadoutBar") as Control
	if not _require(
		offer_row != null
		and offer_row.get_child_count() == 4
		and shop_screen.get_node_or_null("TopBand/Reroll") is Button
		and shop_screen.get_node_or_null("StatsColumn") != null
		and loadout != null
		and loadout.get_node_or_null("Weapons") is HBoxContainer
		and (loadout.get_node("Weapons") as HBoxContainer).get_child_count() == 6
		and shop_screen.get_node_or_null("ContinueButton") is Button,
		"structured shop hierarchy"
	):
		return
	if not _require(
		_control_fits_capture(offer_row)
		and _control_fits_capture(shop_screen.get_node("StatsColumn") as Control)
		and _control_fits_capture(loadout)
		and _control_fits_capture(shop_screen.get_node("ContinueButton") as Control),
		"complete shop hierarchy fits 1280x720"
	):
		return
	capture = await _capture_route(
		root_window,
		shop_screen,
		&"shop",
		SHOP_OUTPUT_URI,
		"res://game/ui/shop_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	if not _require(app.current_session.continue_after_shop(), "advance from shop to combat"):
		return
	if not _require(app.route(FlowRoute.COMBAT) == OK, "combat route before upgrade"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var combat_screen := host.get_child(0) as Node2D
	if not _require(
		combat_screen != null
		and combat_screen.get_script() != null
		and (combat_screen.get_script() as Script).resource_path == "res://game/ui/combat_screen.gd",
		"actual combat route before upgrade"
	):
		return
	var combat_world := combat_screen.get("world") as CombatWorld
	if not _require(combat_world != null, "actual combat world before upgrade"):
		return
	combat_world.call("_finish_wave")
	await get_tree().process_frame
	await get_tree().process_frame
	var upgrade_screen := _current_screen(host)
	if not _require(
		_is_actual_route(upgrade_screen, "res://game/ui/upgrade_screen.gd"),
		"actual upgrade route after combat"
	):
		return
	var choices := upgrade_screen.get_node_or_null("UpgradeChoiceRow") as HBoxContainer
	if not _require(
		choices != null
		and choices.get_child_count() == 4
		and upgrade_screen.get_node_or_null("BattlefieldBackdrop") is TextureRect
		and (
			DisplayServer.get_name() == "headless"
			or (upgrade_screen.get_node("BattlefieldBackdrop") as TextureRect).texture != null
		)
		and upgrade_screen.get_node_or_null("DimVeil") is ColorRect
		and upgrade_screen.get_node_or_null("StatsColumn") != null
		and upgrade_screen.get_node_or_null("RerollButton") is Button,
		"four-choice upgrade hierarchy with captured battlefield"
	):
		return
	if not _require(
		_control_fits_capture(choices)
		and _control_fits_capture(upgrade_screen.get_node("StatsColumn") as Control)
		and _control_fits_capture(upgrade_screen.get_node("RerollButton") as Control),
		"upgrade hierarchy fits 1280x720"
	):
		return
	capture = await _capture_route(
		root_window,
		upgrade_screen,
		&"upgrade",
		UPGRADE_OUTPUT_URI,
		"res://game/ui/upgrade_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	var manifest_path := ProjectSettings.globalize_path(MANIFEST_URI)
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if not _require(manifest_file != null, "route capture manifest open"):
		return
	manifest_file.store_string(JSON.stringify({
		"schema_version": "gogobro-real-menu-route-captures-v1",
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"captures": captures,
	}, "  "))
	manifest_file.close()
	print(
		"FULL_STATIC_ASSETS_MENU_V1_OK captures=%d manifest=%s"
		% [captures.size(), manifest_path]
	)


func _capture_route(
	root_window: SubViewport,
	screen: Control,
	route_name: StringName,
	output_uri: String,
	expected_script_path: String
) -> Dictionary:
	if not _require(_is_actual_route(screen, expected_script_path), "%s route identity" % route_name):
		return {}
	if not _require(
		screen.get_node_or_null("SelectionEvidence") == null,
		"%s contains only real route UI" % route_name
	):
		return {}
	await _wait_for_capture_frame()
	await _wait_for_capture_frame()
	if DisplayServer.get_name() == "headless":
		return {
			"route": String(route_name),
			"screen_script": expected_script_path,
			"user_uri": output_uri,
			"absolute_path": "",
			"sha256": "",
			"capture_mode": "headless-structure",
		}
	var image := root_window.get_texture().get_image()
	if not _require(
		image != null and image.get_size() == CAPTURE_SIZE,
		"%s 1280x720 capture" % route_name
	):
		return {}
	var output_path := ProjectSettings.globalize_path(output_uri)
	if not _require(image.save_png(output_path) == OK, "%s capture save" % route_name):
		return {}
	return {
		"route": String(route_name),
		"screen_script": expected_script_path,
		"user_uri": output_uri,
		"absolute_path": output_path,
		"sha256": FileAccess.get_sha256(output_path),
	}


func _is_actual_route(screen: Control, expected_script_path: String) -> bool:
	if screen == null or screen.get_script() == null:
		return false
	return (screen.get_script() as Script).resource_path == expected_script_path


func _button_uses_texture_states(button: Button) -> bool:
	if button == null:
		return false
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style := button.get_theme_stylebox(state)
		if not style is StyleBoxTexture or (style as StyleBoxTexture).texture == null:
			return false
	return true


func _card_uses_low_border_style(card: Button) -> bool:
	if card == null or card.find_children("RarityAccent", "ColorRect", true, false).size() != 1:
		return false
	var normal := card.get_theme_stylebox(&"normal")
	return (
		normal is StyleBoxFlat
		and (normal as StyleBoxFlat).border_width_left == 1
		and not (normal as StyleBoxFlat).anti_aliasing
	)


func _wait_for_capture_frame() -> void:
	await get_tree().process_frame
	# The headless display server never emits `frame_post_draw`; awaiting it was the
	# cause of this smoke test reaching GdUnit's five-minute watchdog. Windowed
	# capture still waits for the real rendered frame before reading the viewport.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _control_fits_capture(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	return (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= CAPTURE_SIZE.x
		and rect.end.y <= CAPTURE_SIZE.y
	)


func _current_screen(host: Node) -> Control:
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0) as Control


func _texture_visible(parent: Node, path: String) -> bool:
	if parent == null:
		return false
	var texture_rect := parent.get_node_or_null(path) as TextureRect
	return texture_rect != null and texture_rect.texture != null and texture_rect.is_visible_in_tree()


func _first_button(parent: Node) -> Button:
	if parent == null:
		return null
	for node in parent.find_children("*", "Button", true, false):
		return node as Button
	return null


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("FULL_STATIC_ASSETS_MENU_V1_FAILED: " + message)
