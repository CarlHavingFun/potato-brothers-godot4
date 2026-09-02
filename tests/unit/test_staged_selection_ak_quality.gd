extends GdUnitTestSuite

class IsolatedProfileService extends ProfileService:
	func _atomic_write(payload: Dictionary) -> Error:
		profile_data = payload.duplicate(true)
		return OK


const CHARACTER_SCREEN := preload("res://game/ui/character_select_screen.tscn")
const AK := &"gogobro.preview:weapon/wood_stock_assault_rifle"


func test_stages_reveal_in_character_weapon_difficulty_order() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Control
	var screen := fixture.screen as Control
	assert_object(screen.get_node_or_null("WeaponStage")).is_not_null()
	assert_object(screen.get_node_or_null("DifficultyStage")).is_not_null()
	var weapons := screen.get_node_or_null("WeaponStage") as Control
	var difficulty := screen.get_node_or_null("DifficultyStage") as Control
	if weapons == null or difficulty == null:
		return
	assert_bool(weapons.visible).is_false()
	assert_bool(difficulty.visible).is_false()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_bool((screen.get_node("RosterCaption") as Control).visible).is_true()
	assert_bool((screen.get_node("RosterStrip/NikoCell") as Button).disabled).is_false()
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	assert_bool(weapons.visible).is_true()
	assert_bool(difficulty.visible).is_false()
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	ak_button.pressed.emit()
	await _settle()
	assert_bool(difficulty.visible).is_true()
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_equal(String(AK))
	var option := screen.get_node("DifficultyStage/DifficultyStrip/DifficultyOption0") as Button
	var title := option.get_node("Title") as Label
	var multipliers := option.get_node("Multipliers") as Label
	var start_cue := option.get_node("StartCue") as Label
	assert_str(title.text).is_equal("标准")
	assert_str(multipliers.text).contains("生命 100%")
	assert_str(multipliers.text).contains("伤害 100%")
	assert_str(start_cue.text).is_equal("开始")
	for control in [option, title, multipliers, start_cue]:
		_assert_inside_host(host, control)
		assert_bool(option.get_global_rect().encloses((control as Control).get_global_rect())).is_true()


func test_stale_or_rejected_weapon_never_reveals_difficulty_or_starts() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	app.selection_draft["character_id"] = NikoContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = &"missing:weapon/stale"
	screen.call("_sync_selection")
	await _settle()
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_empty()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	screen.call("_select_difficulty_and_start", ValidationContentFactory.DIFFICULTY_ID)
	assert_object(app.current_session).is_null()


func test_hidden_weapon_stage_has_no_enabled_control_or_stale_focus_destination() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	app.selection_draft["character_id"] = &""
	screen.call("_sync_selection")
	await _settle()
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	var option := _weapon_button(screen, AK)
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool(option.disabled).is_true()
	assert_int(option.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_str(String(niko.focus_neighbor_right)).is_equal(String(niko.get_path_to(niko)))
	assert_object(niko.get_node_or_null(niko.focus_neighbor_right)).is_same(niko)


func test_repeated_difficulty_activation_creates_exactly_one_session() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var created: Array[GameSession] = []
	app.session_created.connect(func(session: GameSession) -> void: created.append(session))
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	_weapon_button(screen, AK).pressed.emit()
	await _settle()
	screen.call("_select_difficulty_and_start", ValidationContentFactory.DIFFICULTY_ID)
	screen.call("_select_difficulty_and_start", ValidationContentFactory.DIFFICULTY_ID)
	assert_int(created.size()).is_equal(1)
	assert_object(app.current_session).is_same(created[0])


func test_back_steps_difficulty_weapon_character_main_without_losing_the_draft() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Control
	var screen := fixture.screen as Control
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	ak_button.pressed.emit()
	await _settle()
	var before := app.selection_draft.duplicate(true)
	var back := screen.get_node("BackButton") as Button
	back.pressed.emit()
	await _settle()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(ak_button)
	var bottom_path := ak_button.focus_neighbor_bottom
	var bottom_neighbor := ak_button.get_node_or_null(bottom_path) as Control
	if not bottom_path.is_empty():
		assert_object(bottom_neighbor).is_not_null()
	if bottom_neighbor != null:
		assert_bool(bottom_neighbor.is_visible_in_tree()).is_true()
		assert_bool(
			not (screen.get_node("DifficultyStage") as Control).is_ancestor_of(bottom_neighbor)
		).is_true()
		if bottom_neighbor is BaseButton:
			assert_bool((bottom_neighbor as BaseButton).disabled).is_false()
	back.pressed.emit()
	await _settle()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(
		screen.get_node("RosterStrip/NikoCell") as Button
	)
	back.pressed.emit()
	await _settle()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.MAIN_MENU))
	assert_int(host.get_child_count()).is_equal(1)
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()


func test_escape_uses_the_same_progressive_back_rule_and_focus_restoration() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	niko.pressed.emit()
	await _settle()
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	ak_button.pressed.emit()
	await _settle()
	var before := app.selection_draft.duplicate(true)

	await _escape(screen)
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(ak_button)

	await _escape(screen)
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)

	await _escape(screen)
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.MAIN_MENU))
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()


func test_initial_picker_is_eight_by_four_with_one_real_niko_and_thirty_one_unavailable_slots() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var host := fixture.host as Control
	var screen := fixture.screen as Control
	var roster := screen.get_node_or_null("RosterStrip") as GridContainer
	var niko := screen.get_node_or_null("RosterStrip/NikoCell") as Button
	var change := screen.get_node_or_null("ChangeCharacterButton") as Button
	assert_object(roster).is_not_null()
	assert_object(niko).is_not_null()
	assert_object(change).is_not_null()
	if roster == null or niko == null or change == null:
		return
	assert_int(roster.columns).is_equal(8)
	assert_int(roster.get_child_count()).is_equal(32)
	assert_bool(roster.size.is_equal_approx(Vector2(900, 472))).is_true()
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_width"))).is_equal(1280)
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_height"))).is_equal(720)
	assert_str(String(ProjectSettings.get_setting("display/window/stretch/mode"))).is_equal("canvas_items")
	assert_str((screen.get_node("RosterCaption") as Label).text).contains("已解锁 1 / 32")
	assert_bool(roster.visible).is_true()
	assert_bool(change.visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)
	_assert_inside_host(host, screen.get_node("RosterCaption") as Control)
	var unavailable_slots: Array[int] = []
	for child in roster.get_children():
		var cell := child as Button
		assert_object(cell).is_not_null()
		if cell == null:
			continue
		_assert_inside_host(host, cell)
		assert_bool(roster.get_global_rect().encloses(cell.get_global_rect())).is_true()
		if cell == niko:
			assert_bool(cell.disabled).is_false()
			assert_bool(cell.focus_mode != Control.FOCUS_NONE).is_true()
			assert_str(String(cell.get_meta(&"content_id", &""))).is_equal(String(NikoContentFactory.CHARACTER_ID))
			continue
		assert_bool(cell.disabled).is_true()
		assert_int(cell.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(cell.has_meta(&"content_id")).is_false()
		assert_bool(cell.has_meta(&"definition")).is_false()
		assert_bool(cell.has_meta(&"character_definition")).is_false()
		assert_str(String(cell.get_meta(&"availability", &""))).is_equal("unavailable")
		var slot_number := int(cell.get_meta(&"roster_slot", 0))
		unavailable_slots.append(slot_number)
		assert_str(String(cell.name)).is_equal("UnavailableCharacterSlot%02d" % slot_number)
		assert_str(cell.tooltip_text).contains("角色槽位 %02d" % slot_number)
		assert_str(cell.text).is_empty()
		assert_str((cell.get_node("Glyph") as Label).text).is_equal("空位")
		assert_str((cell.get_node("Status") as Label).text).is_equal("待开放")
		assert_int(cell.get_signal_connection_list(&"pressed").size()).is_equal(0)
		for neighbor_path in [
			cell.focus_neighbor_left,
			cell.focus_neighbor_right,
			cell.focus_neighbor_top,
			cell.focus_neighbor_bottom,
			cell.focus_next,
			cell.focus_previous,
		]:
			assert_str(String(neighbor_path)).is_empty()
		cell.grab_focus()
		cell.pressed.emit()
		assert_str(String(app.selection_draft.get("character_id", &""))).is_empty()
		assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
		assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
		assert_object(app.current_session).is_null()
		assert_bool(get_viewport().gui_get_focus_owner() != cell).is_true()
	assert_array(unavailable_slots).is_equal(range(2, 33))
	for output_size in [Vector2(1280, 720), Vector2(960, 540)]:
		_assert_scaled_inside_output(roster, Vector2(1280, 720), output_size)


func test_change_character_reconfirm_preserves_legal_draft_without_session() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	niko.pressed.emit()
	await _settle()
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	ak_button.pressed.emit()
	await _settle()
	var before := app.selection_draft.duplicate(true)
	var change := screen.get_node_or_null("ChangeCharacterButton") as Button
	assert_object(change).is_not_null()
	if change == null:
		return
	assert_bool(change.visible).is_true()
	assert_str(change.text).is_equal("Niko · 更换角色")
	change.pressed.emit()
	await _settle()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_bool((screen.get_node("RosterCaption") as Control).visible).is_true()
	assert_bool(change.visible).is_false()
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(niko)
	for stage in [screen.get_node("WeaponStage") as Control, screen.get_node("DifficultyStage") as Control]:
		for control in stage.find_children("*", "Button", true, false):
			var button := control as Button
			assert_bool(button.disabled).is_true()
			assert_int(button.focus_mode).is_equal(Control.FOCUS_NONE)
			assert_str(String(button.focus_neighbor_left)).is_empty()
			assert_str(String(button.focus_neighbor_right)).is_empty()
			assert_str(String(button.focus_neighbor_top)).is_empty()
			assert_str(String(button.focus_neighbor_bottom)).is_empty()
	screen.call("_select_weapon", ValidationContentFactory.RANGED_ID)
	screen.call("_select_difficulty_and_start", ValidationContentFactory.DIFFICULTY_ID)
	assert_dict(app.selection_draft).is_equal(before)
	assert_object(app.current_session).is_null()
	niko.pressed.emit()
	await _settle()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_true()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(ak_button)
	assert_object(app.current_session).is_null()
	ak_button.pressed.emit()
	await _settle()
	assert_dict(app.selection_draft).is_equal(before)
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_true()
	assert_object(app.current_session).is_null()


func test_reopen_with_valid_draft_never_defers_focus_to_hidden_niko() -> void:
	var fixture := await _fixture({
		"character_id": NikoContentFactory.CHARACTER_ID,
		"weapon_id": AK,
	})
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var niko := screen.get_node("RosterStrip/NikoCell") as Button
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	assert_bool(niko.visible).is_false()
	await _settle()
	var focus := get_viewport().gui_get_focus_owner() as Control
	assert_object(focus).is_not_null()
	if focus == null:
		return
	assert_bool(focus.visible).is_true()
	assert_bool(focus.focus_mode != Control.FOCUS_NONE).is_true()
	assert_bool(focus != niko).is_true()
	assert_object(focus).is_same(ak_button)
	assert_str(String(app.selection_draft.get("character_id", &""))).is_equal(String(NikoContentFactory.CHARACTER_ID))
	assert_str(String(app.selection_draft.get("weapon_id", &""))).is_equal(String(AK))
	assert_object(app.current_session).is_null()


func test_ak_selection_explicitly_displays_white_quality_one_without_inventory_mutation() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	var ak_button := _weapon_button(screen, AK)
	assert_object(ak_button).is_not_null()
	if ak_button == null:
		return
	ak_button.pressed.emit()
	await _settle()
	assert_str((ak_button.get_node("QualityBadge") as Label).text).is_equal("I")
	assert_bool((ak_button.get_node("QualityBadge") as Label).get_theme_color(&"font_color").is_equal_approx(Color("e8e6dc"))).is_true()
	assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/QualityBadge") as Label).text).is_equal("I")
	assert_str((screen.get_node("WeaponStage/SelectedWeaponDetail/Damage") as Label).text).contains("8")
	assert_object(app.current_session).is_null()


func test_ak_real_start_keeps_tier_separate_from_quality_one_runtime_stats() -> void:
	var session := _ak_session()
	var definition := session.content_snapshot.definition(AK, &"weapon") as GogoWeaponDefinition
	assert_int(definition.tier).is_equal(2)
	assert_int(definition.price).is_equal(22)
	assert_float(definition.damage).is_equal(8.0)
	assert_array(session.run_state.player().weapon_inventory.records()).is_equal([
		{"instance_id": 1, "content_id": AK, "quality": 1},
	])
	var stats := WeaponRuntimeService.new().build_instance(definition, session.run_state.player(), 1)
	assert_int(stats.weapon_quality).is_equal(1)
	assert_float(stats.damage).is_equal_approx(8.0, 0.0001)


func test_ak_wave_two_quote_and_purchase_create_next_white_quality_one_record() -> void:
	var session := _ak_session()
	assert_int(session.transition(&"shop")).is_equal(OK)
	session.run_state.current_wave = 2
	session.run_state.player().materials = 100
	var definition := session.content_snapshot.definition(AK, &"weapon") as GogoWeaponDefinition
	var shop := ShopRuntimeService.new()
	shop.offers = [definition]
	session.run_state.shop_offer_ids = [AK]
	session.run_state.shop_offer_wave = 2
	session.run_state.shop_offer_initialized = true
	assert_int(shop.item_pool.price_for(definition, 2)).is_equal(24)
	assert_int(shop.buy(session, 0)).is_equal(OK)
	assert_array(session.run_state.player().weapon_inventory.records()).is_equal([
		{"instance_id": 1, "content_id": AK, "quality": 1},
		{"instance_id": 2, "content_id": AK, "quality": 1},
	])
	assert_int(session.run_state.player().materials).is_equal(76)


func _ak_session() -> GameSession:
	var snapshot := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	var config := SessionConfig.new()
	config.seed = 701
	config.character_id = NikoContentFactory.CHARACTER_ID
	config.starting_weapon_id = AK
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, snapshot)).is_equal(OK)
	return session


func _fixture(initial_draft: Dictionary = {}) -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs(true))
	# This lightweight fixture intentionally skips boot, so publish its isolated
	# test content context explicitly before any start can persist W1.
	app.profile_service = IsolatedProfileService.new()
	app.profile_service.publish_content_context(app.content_snapshot)
	add_child(app)
	var host := Control.new()
	host.size = Vector2(1280, 720)
	app.add_child(host)
	var flow := SceneFlow.new()
	app.add_child(flow)
	var audio := GogoAudioService.new()
	app.add_child(audio)
	app.configure(flow, audio)
	flow.configure(host, {
		FlowRoute.MAIN_MENU: _combat_scene(),
		FlowRoute.CHARACTER_SELECT: CHARACTER_SCREEN,
		FlowRoute.COMBAT: _combat_scene(),
	})
	app.begin_selection()
	if not initial_draft.is_empty():
		app.selection_draft = initial_draft.duplicate(true)
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle()
	return {"app": app, "host": host, "screen": host.get_child(0)}


func _combat_scene() -> PackedScene:
	var node := Control.new()
	var scene := PackedScene.new()
	assert_int(scene.pack(node)).is_equal(OK)
	node.free()
	return scene


func _weapon_button(screen: Control, content_id: StringName) -> Button:
	for button: Button in screen.find_children("WeaponOption*", "Button", true, false):
		if button.get_meta(&"content_id") == content_id:
			return button
	return null


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _escape(screen: Control) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	screen.call("_unhandled_key_input", event)
	await _settle()


func _assert_inside_host(host: Control, control: Control) -> void:
	assert_object(control).is_not_null()
	if control != null:
		assert_bool(host.get_global_rect().encloses(control.get_global_rect())).is_true()


func _assert_scaled_inside_output(
	control: Control,
	logical_size: Vector2,
	output_size: Vector2
) -> void:
	var logical_rect := control.get_global_rect()
	var output_scale := output_size / logical_size
	var scaled_rect := Rect2(
		logical_rect.position * output_scale,
		logical_rect.size * output_scale
	)
	assert_bool(Rect2(Vector2.ZERO, output_size).encloses(scaled_rect)).is_true()
