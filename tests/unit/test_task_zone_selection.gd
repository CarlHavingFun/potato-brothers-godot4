extends GdUnitTestSuite


const CHARACTER_SCREEN := preload("res://game/ui/character_select_screen.tscn")
const SECOND_ZONE_ID := &"gogobro.test:zone/night_training"


func test_task_option_lists_only_real_zones_inline_without_creating_a_session() -> void:
	GogoStaticConsumerRegistry.reset_current()
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
	var icon_records := GogoStaticConsumerRegistry.current().records().filter(
		func(record: Dictionary) -> bool:
			return record.get("asset_id", &"") == &"zone_thumbnail"
	)
	assert_int(icon_records.size()).is_equal(1)
	if icon_records.size() == 1:
		var icon_record := icon_records[0] as Dictionary
		assert_bool(icon_record.has("integer_display_scale")).is_false()
		assert_vector(icon_record.get("rendered_size_px", Vector2.ZERO)).is_equal_approx(
			Vector2(40.0, 23.0), Vector2(0.001, 0.001)
		)
		assert_vector(icon_record.get("display_scale", Vector2.ZERO)).is_equal_approx(
			Vector2(0.15625, 23.0 / 144.0), Vector2(0.00001, 0.00001)
		)
		var snapshot := app.static_asset_service.active_snapshot()
		var report := GogoStaticCoverageAudit.build(
			"res://game/content/assets/gogobro_static_assets_v1.json",
			snapshot,
			icon_records
		)
		var accepted := report.accepted_observations as Array
		assert_int(accepted.size()).is_equal(1)
		if accepted.size() == 1:
			assert_vector(_vector2(accepted[0].get("rendered_size_px", []))).is_equal(
				Vector2(40.0, 23.0)
			)
			assert_vector(_vector2(accepted[0].get("display_scale", []))).is_equal_approx(
				Vector2(0.15625, 23.0 / 144.0), Vector2(0.00001, 0.00001)
			)
		var forged_records := icon_records.duplicate(true)
		forged_records[0]["display_scale"] = Vector2.ONE
		var forged_report := GogoStaticCoverageAudit.build(
			"res://game/content/assets/gogobro_static_assets_v1.json",
			snapshot,
			forged_records
		)
		assert_bool((forged_report.rejected_observations as Array).any(
			func(rejection: Dictionary) -> bool:
				return rejection.get("reason", &"") == &"rendered_measurement_mismatch"
		)).is_true()
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


func test_task_option_does_not_observe_first_icon_before_restoring_a_later_draft() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var fixture := await _fixture(_second_zone_pack(false), SECOND_ZONE_ID)
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var option := screen.get_node("TaskOptionButton") as OptionButton
	var second_index := _item_index(option, SECOND_ZONE_ID)
	assert_int(second_index).is_greater_equal(0)
	assert_int(option.selected).is_equal(second_index)
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(String(SECOND_ZONE_ID))
	assert_object(option.get_item_icon(second_index)).is_null()
	var leaked_first_icon := GogoStaticConsumerRegistry.current().records().any(
		func(record: Dictionary) -> bool:
			return record.get("asset_id", &"") == &"zone_thumbnail"
	)
	assert_bool(leaked_first_icon).is_false()
	assert_object(app.current_session).is_null()


func test_selecting_a_valid_task_unlocks_difficulty_after_character_and_weapon_are_ready() -> void:
	var fixture := await _fixture(_second_zone_pack())
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var option := screen.get_node("TaskOptionButton") as OptionButton
	app.selection_draft["zone_id"] = &""
	screen.call("_sync_selection")
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	var weapon_candidates := screen.find_children("WeaponOption*", "Button", true, false).filter(
		func(button: Button) -> bool: return button.visible and not button.disabled
	)
	assert_int(weapon_candidates.size()).is_greater(0)
	if weapon_candidates.is_empty():
		return
	(weapon_candidates.front() as Button).pressed.emit()
	await _settle()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	var second_index := _item_index(option, SECOND_ZONE_ID)
	assert_int(second_index).is_greater_equal(0)
	if second_index < 0:
		return
	option.item_selected.emit(second_index)
	await _settle()
	assert_str(String(app.selection_draft.get("zone_id", &""))).is_equal(String(SECOND_ZONE_ID))
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_true()
	assert_bool(screen.find_children("DifficultyOption*", "Button", true, false).any(
		func(button: Button) -> bool: return button.visible and not button.disabled
	)).is_true()
	assert_object(app.current_session).is_null()


func test_snapshot_without_zones_never_exposes_a_dead_start_action() -> void:
	var fixture := await _fixture(null, &"", false)
	var app := fixture.app as AppKernel
	var screen := fixture.screen as Control
	var option := screen.get_node("TaskOptionButton") as OptionButton
	assert_int(option.item_count).is_equal(0)
	assert_bool(option.disabled).is_true()
	assert_int(option.focus_mode).is_equal(Control.FOCUS_NONE)
	assert_str(option.text).is_equal("任务 · 无可用任务")
	(screen.get_node("RosterStrip/NikoCell") as Button).pressed.emit()
	await _settle()
	var weapon_candidates := screen.find_children("WeaponOption*", "Button", true, false).filter(
		func(button: Button) -> bool: return button.visible and not button.disabled
	)
	assert_int(weapon_candidates.size()).is_greater(0)
	if weapon_candidates.is_empty():
		return
	var first_weapon := weapon_candidates.front() as Button
	first_weapon.pressed.emit()
	await _settle()
	assert_bool((screen.get_node("DifficultyStage") as Control).visible).is_false()
	assert_bool(screen.find_children("DifficultyOption*", "Button", true, false).all(
		func(button: Button) -> bool: return button.disabled or not button.visible
	)).is_true()
	assert_object(app.current_session).is_null()


func _fixture(
	extra_pack: GogoContentPackDefinition = null,
	initial_zone_id: StringName = &"",
	include_zones: bool = true
) -> Dictionary:
	var app := auto_free(AppKernel.new()) as AppKernel
	app.add_to_group(&"gogobro_app")
	var packs := ValidationContentFactory.create_packs(true)
	if not include_zones:
		for pack: GogoContentPackDefinition in packs:
			for definition_index in range(pack.definitions.size() - 1, -1, -1):
				if pack.definitions[definition_index].kind == &"zone":
					pack.definitions.remove_at(definition_index)
	if extra_pack != null:
		packs.append(extra_pack)
	app.content_snapshot = GogoContentRegistry.new().build_snapshot(packs)
	assert_int(app.static_asset_service.stage(app.content_snapshot)).is_equal(OK)
	assert_int(app.static_asset_service.activate_staged(&"", null)).is_equal(OK)
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
	if not initial_zone_id.is_empty():
		app.selection_draft["zone_id"] = initial_zone_id
	assert_int(app.route(FlowRoute.CHARACTER_SELECT)).is_equal(OK)
	await _settle()
	return {"app": app, "host": host, "screen": host.get_child(0)}


func _second_zone_pack(with_icon: bool = true) -> GogoContentPackDefinition:
	var source := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(true)
	)
	var training := source.definition(
		ValidationContentFactory.ZONE_ID, &"zone"
	) as GogoZoneDefinition
	var zone := GogoZoneDefinition.new()
	zone.content_id = SECOND_ZONE_ID
	zone.display_name = "夜间训练场"
	zone.icon_asset_id = &"zone_thumbnail" if with_icon else &""
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


func _vector2(value: Variant) -> Vector2:
	var values := value as Array
	if values == null or values.size() != 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


func _empty_scene() -> PackedScene:
	var node := Control.new()
	var scene := PackedScene.new()
	assert_int(scene.pack(node)).is_equal(OK)
	node.free()
	return scene


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
