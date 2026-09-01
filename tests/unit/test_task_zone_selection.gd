extends GdUnitTestSuite


const CHARACTER_SCREEN := preload("res://game/ui/character_select_screen.tscn")
const SECOND_ZONE_ID := &"gogobro.test:zone/night_training"


func test_task_option_lists_only_real_zones_inline_without_creating_a_session() -> void:
	var fixture := await _fixture()
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var option := screen.get_node_or_null("TaskOptionButton") as OptionButton
	assert_object(option).is_not_null()
	assert_object(screen.get_node_or_null("TaskButton")).is_null()
	assert_object(screen.get_node_or_null("ZoneStage")).is_null()
	if option == null:
		return
	var zones := app.content_snapshot.all(&"zone")
	assert_int(option.item_count).is_equal(zones.size())
	assert_int(option.item_count).is_equal(1)
	for index in option.item_count:
		var content_id := StringName(option.get_item_metadata(index))
		var definition := app.content_snapshot.definition(content_id, &"zone") as GogoZoneDefinition
		assert_object(definition).is_not_null()
		if definition == null:
			continue
		assert_str(option.get_item_text(index)).is_equal("任务 · %s" % definition.display_name)
		assert_str(option.get_item_tooltip(index)).is_equal(
			"%s · %d 波 · 从第 1 波开始" % [definition.display_name, definition.wave_ids.size()]
		)
	assert_int(option.selected).is_equal(_item_index(option, ValidationContentFactory.ZONE_ID))
	assert_str(option.text).is_equal("任务 · 训练场")
	assert_str(option.tooltip_text).is_equal("训练场 · 20 波 · 从第 1 波开始")
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(
		String(ValidationContentFactory.ZONE_ID)
	)
	var training_zone := app.content_snapshot.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	assert_object(training_zone).is_not_null()
	if training_zone != null:
		assert_str(String(training_zone.icon_asset_id)).is_equal("zone_thumbnail")
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_int((screen.get_node("RosterStrip") as GridContainer).get_child_count()).is_equal(24)
	assert_bool((screen.get_node("WeaponStage") as Control).visible).is_false()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_int(screen.find_children("UnavailableZoneSlot*", "Button", true, false).size()).is_equal(0)
	assert_bool(_visible_text(screen).contains("参考 Brotato")).is_false()
	assert_object(app.current_session).is_null()
	option.item_selected.emit(option.selected)
	await _settle()
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(app.current_session).is_null()


func test_task_option_commits_only_the_selected_real_zone_id() -> void:
	var fixture := await _fixture(_second_zone_pack())
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var option := screen.get_node_or_null("TaskOptionButton") as OptionButton
	assert_object(option).is_not_null()
	if option == null:
		return
	assert_int(option.item_count).is_equal(app.content_snapshot.all(&"zone").size())
	assert_int(option.item_count).is_equal(2)
	var second_index := _item_index(option, SECOND_ZONE_ID)
	assert_int(second_index).is_greater_equal(0)
	if second_index < 0:
		return
	var draft_before := app.selection_draft.duplicate(true)
	option.item_selected.emit(second_index)
	await _settle()
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(String(SECOND_ZONE_ID))
	for key in ["seed", "character_id", "weapon_id", "difficulty_id"]:
		assert_that(app.selection_draft.get(key)).is_equal(draft_before.get(key))
	assert_int(option.selected).is_equal(second_index)
	assert_str(option.text).is_equal("任务 · 夜间训练场")
	assert_str(option.tooltip_text).is_equal("夜间训练场 · 20 波 · 从第 1 波开始")
	assert_bool((screen.get_node("RosterStrip") as Control).visible).is_true()
	assert_object(screen.get_node_or_null("ZoneStage")).is_null()
	assert_object(app.current_session).is_null()


func _fixture(extra_pack: GogoContentPackDefinition = null) -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	var packs := ValidationContentFactory.create_packs(true)
	if extra_pack != null:
		packs.append(extra_pack)
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(packs)
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


func _second_zone_pack() -> GogoContentPackDefinition:
	var source := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
	var training := source.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	var zone := GogoZoneDefinition.new()
	zone.content_id = SECOND_ZONE_ID
	zone.display_name = "夜间训练场"
	zone.icon_asset_id = &"zone_thumbnail"
	for wave_id in training.wave_ids:
		zone.wave_ids.append(wave_id)
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"gogobro.test.task_zone"
	pack.pack_kind = &"core"
	pack.definitions.append(zone)
	return pack


func _item_index(option: OptionButton, content_id: StringName) -> int:
	for index in option.item_count:
		if StringName(option.get_item_metadata(index)) == content_id:
			return index
	return -1


func _visible_text(root: Node) -> String:
	var values: Array[String] = []
	for candidate in root.find_children("*", "Control", true, false):
		if candidate is Label and (candidate as Label).visible:
			values.append((candidate as Label).text)
		elif candidate is Button and (candidate as Button).visible:
			values.append((candidate as Button).text)
	return "\n".join(values)


func _empty_scene() -> PackedScene:
	var node := Control.new()
	var scene := PackedScene.new()
	assert_int(scene.pack(node)).is_equal(OK)
	node.free()
	return scene


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
