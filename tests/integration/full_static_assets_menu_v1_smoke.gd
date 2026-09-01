extends GdUnitTestSuite


const OUTPUT_DIR_URI := "user://full-static-assets-menu-v1"
const MAIN_MENU_OUTPUT_URI := OUTPUT_DIR_URI + "/menu-1280x720.png"
const CHARACTER_OUTPUT_URI := OUTPUT_DIR_URI + "/character-select-1280x720.png"
const WEAPON_OUTPUT_URI := OUTPUT_DIR_URI + "/weapon-select-1280x720.png"
const REOPENED_CHARACTER_OUTPUT_URI := OUTPUT_DIR_URI + "/character-reopened-1280x720.png"
const DIFFICULTY_OUTPUT_URI := OUTPUT_DIR_URI + "/difficulty-select-1280x720.png"
const DIAGNOSTIC_OUTPUT_URI := OUTPUT_DIR_URI + "/diagnostic-1280x720.png"
const SHOP_OUTPUT_URI := OUTPUT_DIR_URI + "/shop-1280x720.png"
const UPGRADE_OUTPUT_URI := OUTPUT_DIR_URI + "/upgrade-1280x720.png"
const SHOP_BATTLEFIELD_OUTPUT_URI := OUTPUT_DIR_URI + "/shop-battlefield-1280x720.png"
const SHOP_SOLD_OUTPUT_URI := OUTPUT_DIR_URI + "/shop-sold-1280x720.png"
const MANIFEST_URI := OUTPUT_DIR_URI + "/route-captures-v1.json"
const CAPTURE_SIZE := Vector2i(1280, 720)
const APP_SCENE := preload("res://game/app/app_root.tscn")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")


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
	var menu_actions := main_menu.get_node_or_null(
		"ContentRoot/Body/MenuActions"
	) as VBoxContainer
	var start_button := main_menu.get_node_or_null(
		"ContentRoot/Body/MenuActions/StartButton"
	) as Button
	var exit_button := main_menu.get_node_or_null(
		"ContentRoot/Body/MenuActions/ExitButton"
	) as Button
	if not _require(
		menu_actions != null
		and menu_actions.size.x == 360.0
		and start_button != null
		and exit_button != null
		and start_button.size.x == 360.0
		and start_button.size.y >= 64.0
		and exit_button.size.x == 360.0
		and exit_button.size.y >= 56.0
		and start_button.get_node_or_null("ButtonFill") == null
		and _control_fits_capture(menu_actions)
		and _button_uses_authored_states(start_button)
		and _button_uses_authored_states(exit_button),
		"readable rendered HUD v2 button consumers"
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
	var diagnostic_details: Array[String] = []
	# Repeatable real menu-page fixtures for the final native screenshot review.
	for page_spec in [["ProfileButton", "profile"], ["CodexButton", "codex"], ["SettingsButton", "settings"]]:
		(main_menu.get_node("ContentRoot/Body/MenuActions/" + page_spec[0]) as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		if not _require(main_menu.has_node("MenuPage"), "real menu page " + page_spec[1]):
			return
		capture = await _capture_route(root_window, main_menu, StringName(page_spec[1]),
			OUTPUT_DIR_URI + "/" + page_spec[1] + "-1280x720.png", "res://game/ui/main_menu_screen.gd")
		if capture.is_empty():
			return
		captures.append(capture)
		(main_menu.get_node("MenuPage/BackButton") as Button).pressed.emit()
		await get_tree().process_frame
	for detail_index in 28:
		diagnostic_details.append(
			"诊断细节 %02d：真实路由、候选来源与哈希均需保持可追溯。" % detail_index
		)
	if not _require(app.route(FlowRoute.DIAGNOSTIC, {
		"message": "静态素材诊断",
		"details": diagnostic_details,
	}) == OK, "diagnostic route"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var diagnostic_screen := _current_screen(host)
	var principal_surface := diagnostic_screen.get_node_or_null("PrincipalSurface") as Panel
	var diagnostic_content := principal_surface.get_node_or_null(
		"DiagnosticContent"
	) as VBoxContainer if principal_surface != null else null
	var details_scroll := diagnostic_content.get_node_or_null(
		"DetailsScroll"
	) as ScrollContainer if diagnostic_content != null else null
	var return_button := diagnostic_content.get_node_or_null(
		"ReturnButton"
	) as Button if diagnostic_content != null else null
	if not _require(
		_is_actual_route(diagnostic_screen, "res://game/ui/diagnostic_screen.gd")
		and principal_surface != null
		and principal_surface.get_theme_stylebox(&"panel") is StyleBoxTexture
		and (
			principal_surface.get_theme_stylebox(&"panel") as StyleBoxTexture
		).texture == HUD_SKIN.SURFACE_TEXTURE
		and principal_surface.is_visible_in_tree()
		and principal_surface.position == Vector2(272, 184)
		and principal_surface.size == Vector2(736, 352)
		and diagnostic_content != null
		and details_scroll != null
		and return_button != null
		and _control_fits_capture(details_scroll)
		and _control_fits_capture(return_button)
		and details_scroll.get_v_scroll_bar().max_value > details_scroll.get_v_scroll_bar().page,
		"actual scrollable diagnostic principal surface"
	):
		return
	capture = await _capture_route(
		root_window,
		diagnostic_screen,
		&"diagnostic",
		DIAGNOSTIC_OUTPUT_URI,
		"res://game/ui/diagnostic_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)
	if not _require(app.route(FlowRoute.MAIN_MENU) == OK, "return to main menu after diagnostic"):
		return
	await get_tree().process_frame

	app.begin_selection()
	if not _require(app.route(FlowRoute.CHARACTER_SELECT) == OK, "character selection route"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var character_screen := _current_screen(host)
	if not _require(
		_is_actual_route(character_screen, "res://game/ui/character_select_screen.gd"),
		"actual character selection instance"
	):
		return
	var roster := character_screen.get_node_or_null("RosterStrip") as GridContainer
	var niko_cell := character_screen.get_node_or_null("RosterStrip/NikoCell") as Button
	var change_character := character_screen.get_node_or_null("ChangeCharacterButton") as Button
	var unavailable_count := 0
	var unavailable_contract := true
	var all_character_cells_fit := true
	if roster != null:
		for child in roster.get_children():
			var cell := child as Button
			all_character_cells_fit = all_character_cells_fit and _control_fits_capture(cell)
			if cell == niko_cell:
				continue
			unavailable_count += 1
			unavailable_contract = (
				unavailable_contract
				and cell != null
				and String(cell.name).begins_with("UnavailableCharacterSlot")
				and cell.text.is_empty()
				and cell.has_node("SlotIndex")
				and cell.has_node("Glyph")
				and cell.has_node("Status")
				and (cell.get_node("Status") as Label).text == "待开放"
				and cell.disabled
				and cell.focus_mode == Control.FOCUS_NONE
				and not cell.has_meta(&"content_id")
				and not cell.has_meta(&"definition")
				and cell.get_signal_connection_list(&"pressed").is_empty()
			)
	if not _require(
		character_screen.get_node_or_null("BackButton") is Button
		and character_screen.get_node_or_null("NikoDetail/Preview") is TextureRect
		and _texture_visible(character_screen, "NikoDetail/Preview")
		and (character_screen.get_node("NikoDetail/Preview") as TextureRect).texture_filter
			== CanvasItem.TEXTURE_FILTER_NEAREST
		and character_screen.get_node_or_null("NikoDetail/Name") is Label
		and not (character_screen.get_node("NikoDetail/Traits") as Label).text.is_empty()
		and character_screen.get_node_or_null("RosterCaption") is Label
		and roster != null
		and roster.columns == 8
		and roster.get_child_count() == 24
		and niko_cell != null
		and niko_cell.get_meta(&"content_id", &"") == NikoContentFactory.CHARACTER_ID
		and unavailable_count == 23
		and unavailable_contract
		and change_character != null
		and not change_character.visible
		and change_character.disabled
		and not (character_screen.get_node("WeaponStage") as Control).visible
		and not (character_screen.get_node("DifficultyStage") as Control).visible,
		"eight-by-three Niko plus unavailable character picker"
	):
		return
	if not _require(
		_control_fits_capture(character_screen.get_node("NikoDetail") as Control)
		and _control_fits_capture(character_screen.get_node("RosterCaption") as Control)
		and _control_fits_capture(roster)
		and all_character_cells_fit
		and _selection_uses_low_border_style(niko_cell)
		and root_window.gui_get_focus_owner() == niko_cell,
		"complete character setup hierarchy fits the real route capture"
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

	niko_cell.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.selection_draft.get("character_id", &"") == NikoContentFactory.CHARACTER_ID
		and app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.current_session == null
		and not roster.visible
		and not niko_cell.visible
		and (character_screen.get_node("WeaponStage") as Control).visible
		and not (character_screen.get_node("DifficultyStage") as Control).visible
		and change_character.visible
		and not change_character.disabled
		and change_character.text == "Niko · 更换角色",
		"Niko click commits on the same configuration page"
	):
		return
	var weapon_screen := _current_screen(host)
	if not _require(
		_is_actual_route(weapon_screen, "res://game/ui/character_select_screen.gd"),
		"actual combined configuration instance"
	):
		return
	var strip := weapon_screen.get_node_or_null("WeaponStage/WeaponColumns") as HBoxContainer
	var weapon_options := strip.find_children("WeaponOption*", "Button", true, false) if strip != null else []
	if not _require(
		strip != null
		and strip.get_child_count() == 5
		and weapon_options.size() == app.content_snapshot.all(&"weapon").size()
		and weapon_options.size() == 12
		and weapon_screen.get_node_or_null("NikoDetail") != null
		and weapon_screen.get_node_or_null("WeaponStage/SelectedWeaponDetail/Mode") is Label
		and weapon_screen.get_node_or_null("WeaponStage/SelectedWeaponDetail/Damage") is Label
		and weapon_screen.get_node_or_null("WeaponStage/SelectedWeaponDetail/Cooldown") is Label
		and weapon_screen.get_node_or_null("WeaponStage/SelectedWeaponDetail/Modifiers") is Label,
		"canonical weapon setup hierarchy"
	):
		return
	var first_card := weapon_options[0] as Button
	if not _require(
		_texture_visible(first_card, "Icon")
		and (first_card.get_node("Icon") as TextureRect).size.x >= 60.0
		and (first_card.get_node("Icon") as TextureRect).texture_filter
			== CanvasItem.TEXTURE_FILTER_NEAREST
		and _selection_uses_low_border_style(first_card),
		"rendered readable weapon icon and selected low-border cell"
	):
		return
	if not _require(
		_control_fits_capture(weapon_options.back() as Control)
		and _control_fits_capture(weapon_screen.get_node("BackButton") as Control)
		and _control_fits_capture(weapon_screen.get_node("NikoDetail") as Control)
		and _control_fits_capture(weapon_screen.get_node("WeaponStage/SelectedWeaponDetail") as Control),
		"complete weapon hierarchy fits the real route capture"
	):
		return
	capture = await _capture_route(
		root_window,
		weapon_screen,
		&"configuration_weapons",
		WEAPON_OUTPUT_URI,
		"res://game/ui/character_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	var selected_weapon := _button_by_content_id(strip, ValidationContentFactory.RANGED_ID)
	if not _require(selected_weapon != null, "canonical Glock-18 setup option"):
		return
	selected_weapon.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.selection_draft.get("weapon_id", &"") == ValidationContentFactory.RANGED_ID
		and app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.current_session == null
		and (weapon_screen.get_node("DifficultyStage") as Control).visible,
		"real weapon selection commits without advancing or creating a session"
	):
		return
	var before_reopen := app.selection_draft.duplicate(true)
	change_character.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var hidden_stage_safe := true
	for stage_path in [^"WeaponStage", ^"DifficultyStage"]:
		var stage := weapon_screen.get_node(stage_path) as Control
		for control in stage.find_children("*", "Button", true, false):
			var hidden_button := control as Button
			hidden_stage_safe = (
				hidden_stage_safe
				and hidden_button.disabled
				and hidden_button.focus_mode == Control.FOCUS_NONE
			)
	if not _require(
		roster.visible
		and niko_cell.visible
		and not (weapon_screen.get_node("WeaponStage") as Control).visible
		and not (weapon_screen.get_node("DifficultyStage") as Control).visible
		and not change_character.visible
		and app.selection_draft == before_reopen
		and app.current_session == null
		and hidden_stage_safe
		and root_window.gui_get_focus_owner() == niko_cell,
		"reopened picker preserves draft and disables hidden stages"
	):
		return
	capture = await _capture_route(
		root_window,
		weapon_screen,
		&"configuration_character_reopened",
		REOPENED_CHARACTER_OUTPUT_URI,
		"res://game/ui/character_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	niko_cell.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var difficulty_screen := _current_screen(host)
	if not _require(
		_is_actual_route(difficulty_screen, "res://game/ui/character_select_screen.gd"),
		"actual combined weapon-reconfirm instance"
	):
		return
	if not _require(
		not (difficulty_screen.get_node("RosterStrip") as Control).visible
		and (difficulty_screen.get_node("WeaponStage") as Control).visible
		and not (difficulty_screen.get_node("DifficultyStage") as Control).visible
		and app.selection_draft == before_reopen
		and root_window.gui_get_focus_owner() == selected_weapon,
		"reconfirmed character returns to the weapon stage with selected-weapon focus"
	):
		return
	selected_weapon.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var difficulty_button := difficulty_screen.get_node_or_null(
		"DifficultyStage/DifficultyStrip/DifficultyOption0"
	) as Button
	if not _require(
		difficulty_screen.get_node_or_null("BackButton") is Button
		and not (difficulty_screen.get_node("RosterStrip") as Control).visible
		and (difficulty_screen.get_node("WeaponStage") as Control).visible
		and (difficulty_screen.get_node("DifficultyStage") as Control).visible
		and app.selection_draft == before_reopen
		and difficulty_button != null
		and not difficulty_button.disabled
		and difficulty_button.focus_mode == Control.FOCUS_ALL
		and (difficulty_button.get_node("Title") as Label).text == "标准"
		and (difficulty_button.get_node("Multipliers") as Label).text.contains("生命 100%")
		and (difficulty_button.get_node("Multipliers") as Label).text.contains("伤害 100%")
		and (difficulty_button.get_node("StartCue") as Label).text == "开始",
		"canonical combined single-difficulty setup hierarchy"
	):
		return
	if not _require(
		(difficulty_button.get_node("Icon") as TextureRect).texture_filter
			== CanvasItem.TEXTURE_FILTER_NEAREST
		and difficulty_button.get_meta(&"content_id", &"")
			== ValidationContentFactory.DIFFICULTY_ID
		and _selection_uses_low_border_style(difficulty_button)
		and _control_fits_capture(difficulty_screen.get_node("DifficultyStage/DifficultyStrip") as Control)
		and difficulty_button.get_global_rect().encloses(
			(difficulty_button.get_node("Title") as Label).get_global_rect()
		)
		and difficulty_button.get_global_rect().encloses(
			(difficulty_button.get_node("Multipliers") as Label).get_global_rect()
		)
		and difficulty_button.get_global_rect().encloses(
			(difficulty_button.get_node("StartCue") as Label).get_global_rect()
		),
		"difficulty title, multipliers, start cue, and complete capture fit"
	):
		return
	capture = await _capture_route(
		root_window,
		difficulty_screen,
		&"configuration_difficulty",
		DIFFICULTY_OUTPUT_URI,
		"res://game/ui/character_select_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	var back := difficulty_screen.get_node("BackButton") as Button
	back.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and app.selection_draft.get("character_id", &"") == NikoContentFactory.CHARACTER_ID
		and app.selection_draft.get("weapon_id", &"") == ValidationContentFactory.RANGED_ID
		and app.current_session == null
		and not (difficulty_screen.get_node("RosterStrip") as Control).visible
		and (difficulty_screen.get_node("WeaponStage") as Control).visible
		and not (difficulty_screen.get_node("DifficultyStage") as Control).visible
		and root_window.gui_get_focus_owner() == selected_weapon,
		"difficulty Back restores the weapon stage, draft, and selected-weapon focus"
	):
		return
	back.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and (difficulty_screen.get_node("RosterStrip") as Control).visible
		and not (difficulty_screen.get_node("WeaponStage") as Control).visible
		and root_window.gui_get_focus_owner() == difficulty_screen.get_node("RosterStrip/NikoCell"),
		"weapon Back restores the character stage and Niko focus"
	):
		return
	back.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.scene_flow.current_route() == FlowRoute.MAIN_MENU
		and app.selection_draft.get("character_id", &"") == NikoContentFactory.CHARACTER_ID
		and app.selection_draft.get("weapon_id", &"") == ValidationContentFactory.RANGED_ID
		and app.current_session == null,
		"character Back reaches the main menu without losing the draft"
	):
		return
	if not _require(app.route(FlowRoute.DIFFICULTY_SELECT) == OK, "difficulty alias reopens configuration"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	difficulty_screen = _current_screen(host)
	difficulty_button = difficulty_screen.get_node(
		"DifficultyStage/DifficultyStrip/DifficultyOption0"
	) as Button
	var restored_focus := root_window.gui_get_focus_owner() as Control
	if not _require(
		app.scene_flow.current_route() == FlowRoute.CHARACTER_SELECT
		and not (difficulty_screen.get_node("RosterStrip") as Control).visible
		and (difficulty_screen.get_node("DifficultyStage") as Control).visible
		and restored_focus != null
		and restored_focus.is_visible_in_tree()
		and restored_focus != difficulty_screen.get_node("RosterStrip/NikoCell"),
		"valid draft reopens on visible configuration focus"
	):
		return
	difficulty_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not _require(
		app.current_session != null
		and app.selection_draft.get("difficulty_id", &"") == ValidationContentFactory.DIFFICULTY_ID
		and app.scene_flow.current_route() == FlowRoute.COMBAT,
		"real difficulty selection creates session and starts combat"
	):
		return
	var player := app.current_session.run_state.player()
	player.materials = 500
	player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, app.content_snapshot)
	player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, app.content_snapshot)
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
		and player.weapon_ids.size() == 3
		and (loadout.get_node("Weapons") as HBoxContainer).get_child_count() == player.weapon_ids.size()
		and loadout.get_node_or_null("WeaponsTitle") is Label
		and (loadout.get_node("WeaponsTitle") as Label).text == "武器 3/6"
		and shop_screen.get_node_or_null("ContinueButton") is Button,
		"structured shop hierarchy"
	):
		return
	var equipped_weapons := loadout.get_node("Weapons") as HBoxContainer
	if not _require(not equipped_weapons.has_node("EmptyWeapons"), "owned weapons have no empty equipment placeholder"):
		return
	for slot_index in player.weapon_ids.size():
		var equipped := equipped_weapons.get_child(slot_index) as Button
		if not _require(
			equipped != null
			and not equipped.disabled
			and equipped.get_meta(&"slot_index", -1) == slot_index
			and equipped.get_meta(&"content_id", &"") == player.weapon_ids[slot_index],
			"equipped slot %d preserves its actual owned weapon" % slot_index
		):
			return
	var shop_command_states_valid := _button_uses_authored_states(
		shop_screen.get_node("TopBand/Reroll") as Button
	) and _button_uses_authored_states(shop_screen.get_node("ContinueButton") as Button)
	var shop_cards_are_single_surface := true
	for slot in offer_row.get_children():
		var card := (slot as Node).get_node_or_null("Card") as Button
		var lock := (slot as Node).get_node_or_null("Lock") as Button
		shop_command_states_valid = (
			shop_command_states_valid
			and _button_uses_authored_states(lock)
		)
		shop_cards_are_single_surface = (
			shop_cards_are_single_surface
			and card != null
			and card.get_theme_stylebox(&"normal") is StyleBoxTexture
			and (card.get_theme_stylebox(&"normal") as StyleBoxTexture).texture
				== HUD_SKIN.SHOP_CARD_TEXTURE
			and card.get_theme_stylebox(&"focus") is StyleBoxFlat
			and card.get_node_or_null("RarityAccent") == null
		)
	if not _require(
		shop_command_states_valid and shop_cards_are_single_surface,
		"shop commands and cards use one dark surface without rarity rails"
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
	player.xp = maxi(
		player.xp_to_next_level
		- GameSession.fixed_wave_xp_reward(app.current_session.run_state.current_wave),
		0
	)
	combat_world.call("_finish_wave")
	if not _require(
		(combat_screen.get("hud") as GogoBrotatoCombatHud).visible,
		"combat HUD retained beneath upgrade backdrop"
	):
		return
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
	var upgrade_cards_are_single_surface := true
	for choice in choices.get_children():
		upgrade_cards_are_single_surface = (
			upgrade_cards_are_single_surface
			and (choice as Button).get_theme_stylebox(&"normal") is StyleBoxFlat
		)
	if not _require(
		_button_uses_flat_states(
			upgrade_screen.get_node("RerollButton") as Button,
			snapshot
		)
		and upgrade_cards_are_single_surface,
		"upgrade controls and cards use the shared single-surface skin"
	):
		return
	var dim_veil := upgrade_screen.get_node("DimVeil") as ColorRect
	var upgrade_reroll := upgrade_screen.get_node("RerollButton") as Button
	if not _require(
		dim_veil.color.a >= 0.75
		and upgrade_screen.get_node("TitleBand").get_index() > dim_veil.get_index(),
		"upgrade veil subordinates retained combat HUD beneath title UI"
	):
		return
	if not _require(
		_control_fits_capture(choices)
		and _control_fits_capture(upgrade_screen.get_node("StatsColumn") as Control)
		and _control_fits_capture(upgrade_screen.get_node("RerollButton") as Control),
		"upgrade hierarchy fits 1280x720"
	):
		return
	if not _require(
		absf(upgrade_reroll.get_global_rect().get_center().x - choices.get_global_rect().get_center().x) <= 1.0
		and upgrade_reroll.alignment == HORIZONTAL_ALIGNMENT_CENTER
		and upgrade_reroll.clip_text,
		"upgrade reroll is centered beneath the complete four-card row"
	):
		return
	if not _require(
		_stat_icons_are_visible(upgrade_screen.get_node("StatsColumn/StatList") as Control)
		and _card_effect_icons_are_visible(choices),
		"upgrade cards and character-stat column use readable physical stat icons"
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

	# Accept one real upgrade so the next shop receives the exact battlefield texture
	# captured by CombatScreen. Buying from that shop forces a full rebuild and proves
	# that the backdrop, fully empty purchased slot, button fit, and stat icons survive it.
	(choices.get_child(0) as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var battlefield_shop := _current_screen(host)
	if not _require(
		_is_actual_route(battlefield_shop, "res://game/ui/shop_screen.gd"),
		"actual shop after the upgrade route"
	):
		return
	var shop_backdrop := battlefield_shop.get_node_or_null("BattlefieldBackdrop") as TextureRect
	var shop_backdrop_texture := shop_backdrop.texture if shop_backdrop != null else null
	var shop_dim_veil := battlefield_shop.get_node_or_null("DimVeil") as ColorRect
	var battlefield_offer_row := battlefield_shop.get_node_or_null("OfferRow") as HBoxContainer
	var shop_reroll := battlefield_shop.get_node_or_null("TopBand/Reroll") as Button
	if not _require(
		shop_backdrop != null
		and (
			DisplayServer.get_name() == "headless"
			or shop_backdrop.texture != null
		)
		and shop_backdrop.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		and shop_dim_veil != null
		and shop_dim_veil.color.a >= 0.72
		and shop_dim_veil.color.a <= 0.80
		and not (battlefield_shop.get_node("StaticMenuBackground") as TextureRect).visible,
		"shop keeps the exact completed battlefield beneath a strong readability veil"
	):
		return
	if not _require(
		battlefield_offer_row != null
		and battlefield_offer_row.get_child_count() == 4
		and shop_reroll != null
		and shop_reroll.alignment == HORIZONTAL_ALIGNMENT_CENTER
		and shop_reroll.clip_text
		and _control_fits_capture(shop_reroll)
		and _card_effect_icons_are_visible(battlefield_offer_row)
		and _stat_icons_are_visible(
			battlefield_shop.get_node("StatsColumn/StatList") as Control
		),
		"shop cards, stat column, and compact reroll remain legible over the battlefield"
	):
		return
	capture = await _capture_route(
		root_window,
		battlefield_shop,
		&"shop_battlefield",
		SHOP_BATTLEFIELD_OUTPUT_URI,
		"res://game/ui/shop_screen.gd"
	)
	if capture.is_empty():
		return
	captures.append(capture)

	var first_offer_card := battlefield_offer_row.get_node("OfferSlot0/Card") as Button
	if not _require(first_offer_card != null and not first_offer_card.disabled, "buyable shop offer"):
		return
	first_offer_card.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var sold_shop := _current_screen(host)
	# The purchased logical index remains a true empty hole; later cards keep their
	# authored positions instead of shifting left.
	var empty_slot := sold_shop.get_node_or_null("OfferRow/OfferSlot0") as VBoxContainer
	var sold_backdrop := sold_shop.get_node_or_null("BattlefieldBackdrop") as TextureRect
	if not _require(
		empty_slot != null
		and (empty_slot.get_meta(&"empty_offer_slot", false) as bool)
		and empty_slot.get_child_count() == 0
		and empty_slot.find_children("*", "Label", true, false).is_empty()
		and empty_slot.find_children("*", "Button", true, false).is_empty()
		and sold_backdrop != null
		and sold_backdrop.texture == shop_backdrop_texture
		and _stat_icons_are_visible(sold_shop.get_node("StatsColumn/StatList") as Control),
		"purchased slot is visually empty and rebuilding preserves battlefield plus stat icons"
	):
		return
	capture = await _capture_route(
		root_window,
		sold_shop,
		&"shop_sold",
		SHOP_SOLD_OUTPUT_URI,
		"res://game/ui/shop_screen.gd"
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
	_queue_canvas_redraw(screen)
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


func _button_uses_flat_states(
	button: Button,
	_snapshot: GogoStaticAssetSnapshot
) -> bool:
	if button == null:
		return false
	var expected_colors := {
		&"normal": HUD_SKIN.COLOR_CONTROL,
		&"hover": HUD_SKIN.COLOR_CONTROL_FOCUS,
		&"pressed": HUD_SKIN.COLOR_CONTROL_PRESSED,
		&"disabled": HUD_SKIN.COLOR_CONTROL_DISABLED,
	}
	for state: StringName in expected_colors:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		if (
			style == null
			or not style.bg_color.is_equal_approx(expected_colors[state] as Color)
			or style.border_width_left != 1
		):
			return false
	return true


func _button_uses_authored_states(button: Button) -> bool:
	if button == null or button.get_node_or_null("ButtonFill") != null:
		return false
	var expected_textures := {
		&"normal": HUD_SKIN.BUTTON_NORMAL,
		&"hover": HUD_SKIN.BUTTON_FOCUS,
		&"focus": HUD_SKIN.BUTTON_FOCUS,
		&"pressed": HUD_SKIN.BUTTON_PRESSED,
		&"disabled": HUD_SKIN.BUTTON_DISABLED,
	}
	for state: StringName in expected_textures:
		var style := button.get_theme_stylebox(state) as StyleBoxTexture
		if (
			style == null
			or style.texture != expected_textures[state]
			or not is_equal_approx(
				style.get_texture_margin(SIDE_LEFT),
				HUD_SKIN.BUTTON_PATCH_MARGIN
			)
			or not is_equal_approx(style.get_content_margin(SIDE_TOP), 8.0)
		):
			return false
	return true


func _selection_uses_low_border_style(button: Button) -> bool:
	if button == null:
		return false
	var normal := button.get_theme_stylebox(&"normal") as StyleBoxFlat
	return (
		normal != null
		and normal.bg_color.a >= 0.90
		and normal.border_width_left >= 1
		and normal.border_width_left <= 3
	)


func _wait_for_capture_frame() -> void:
	await get_tree().process_frame
	# The headless display server never emits `frame_post_draw`; awaiting it was the
	# cause of this smoke test reaching GdUnit's five-minute watchdog. Windowed
	# capture still waits for the real rendered frame before reading the viewport.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _queue_canvas_redraw(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).queue_redraw()
	for child in node.get_children():
		_queue_canvas_redraw(child)


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


func _stat_icons_are_visible(stat_list: Control) -> bool:
	if stat_list == null or stat_list.get_child_count() == 0:
		return false
	for row in stat_list.get_children():
		var icon := (row as Node).get_node_or_null("Icon") as TextureRect
		if icon == null or icon.texture == null or not icon.is_visible_in_tree():
			return false
	return true


func _card_effect_icons_are_visible(card_parent: Node) -> bool:
	if card_parent == null or card_parent.get_child_count() == 0:
		return false
	for child in card_parent.get_children():
		var card := child as Button
		if card == null:
			card = (child as Node).get_node_or_null("Card") as Button
		if card == null or card.disabled:
			continue
		var rows := card.get_node_or_null("StatRows") as VBoxContainer
		if rows == null:
			return false
		var found_icon := false
		for row in rows.get_children():
			var text_label := (row as Node).get_node_or_null("Text") as Label
			var icon := (row as Node).get_node_or_null("Icon") as TextureRect
			if text_label != null and not text_label.text.is_empty():
				found_icon = icon != null and icon.texture != null and icon.is_visible_in_tree()
				break
		if not found_icon:
			return false
	return true


func _button_by_content_id(parent: Node, content_id: StringName) -> Button:
	if parent == null:
		return null
	for child in parent.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.get_meta(&"content_id", &"") == content_id:
			return button
	return null


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	_fail(label)
	return false


func _fail(message: String) -> void:
	fail("FULL_STATIC_ASSETS_MENU_V1_FAILED: " + message)
