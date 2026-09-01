extends GdUnitTestSuite


const CHARACTER_SCREEN := preload("res://game/ui/character_select_screen.tscn")


func test_task_button_opens_one_real_zone_card_without_faking_wave_skip() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var task_button := screen.get_node_or_null("TaskButton") as Button
	var zone_stage := screen.get_node_or_null("ZoneStage") as Control
	assert_object(task_button).is_not_null()
	assert_object(zone_stage).is_not_null()
	if task_button == null or zone_stage == null:
		return
	assert_str(task_button.text).contains("训练场")
	assert_str(task_button.tooltip_text).contains("20 波")
	task_button.pressed.emit()
	await _settle()
	assert_bool(zone_stage.visible).is_true()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_false()
	var option := zone_stage.get_node_or_null("ZoneGrid/ZoneOption0") as Button
	assert_object(option).is_not_null()
	if option == null:
		return
	assert_str(String(option.get_meta(&"content_id", &""))).is_equal(String(ValidationContentFactory.ZONE_ID))
	assert_str((option.get_node("Name") as Label).text).is_equal("训练场")
	assert_str((option.get_node("WaveCount") as Label).text).is_equal("20 波")
	assert_str((option.get_node("StartWave") as Label).text).is_equal("从第 1 波开始")
	assert_object(app.current_session).is_null()
	var placeholders := zone_stage.find_children("UnavailableZoneSlot*", "Button", true, false)
	assert_int(placeholders.size()).is_equal(2)
	for candidate in placeholders:
		var placeholder := candidate as Button
		assert_bool(placeholder.disabled).is_true()
		assert_int(placeholder.focus_mode).is_equal(Control.FOCUS_NONE)
		assert_bool(placeholder.has_meta(&"content_id")).is_false()
		assert_bool(placeholder.get_signal_connection_list(&"pressed").is_empty()).is_true()
	option.pressed.emit()
	await _settle()
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(String(ValidationContentFactory.ZONE_ID))
	assert_object(app.current_session).is_null()
	assert_bool(zone_stage.visible).is_false()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()


func test_task_overlay_back_returns_to_the_same_character_draft() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var draft_before := app.selection_draft.duplicate(true)
	var task_button := screen.get_node_or_null("TaskButton") as Button
	var zone_stage := screen.get_node_or_null("ZoneStage") as Control
	assert_object(task_button).is_not_null()
	assert_object(zone_stage).is_not_null()
	if task_button == null or zone_stage == null:
		return
	task_button.pressed.emit()
	await _settle()
	(screen.get_node("BackButton") as Button).pressed.emit()
	await _settle()
	assert_bool(zone_stage.visible).is_false()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_str(String(app.scene_flow.current_route())).is_equal(String(FlowRoute.CHARACTER_SELECT))
	assert_dict(app.selection_draft).is_equal(draft_before)


func _fixture() -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
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
		FlowRoute.MAIN_MENU: _empty_scene(),
		FlowRoute.CHARACTER_SELECT: CHARACTER_SCREEN,
		FlowRoute.COMBAT: _empty_scene(),
	})
	app.begin_selection()
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle()
	return {"app": app, "host": host, "screen": host.get_child(0)}


func _empty_scene() -> PackedScene:
	var node := Control.new()
	var scene := PackedScene.new()
	assert_int(scene.pack(node)).is_equal(OK)
	node.free()
	return scene


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
