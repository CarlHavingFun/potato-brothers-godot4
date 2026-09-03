extends GdUnitTestSuite


const PAUSE_OVERLAY_PATH := "res://game/ui/pause_overlay.gd"


func test_pause_overlay_script_exists() -> void:
	assert_bool(FileAccess.file_exists(PAUSE_OVERLAY_PATH)).is_true()


func test_pause_overlay_exposes_brotato_structure_and_real_loadout() -> void:
	if not FileAccess.file_exists(PAUSE_OVERLAY_PATH):
		return
	var overlay := auto_free((load(PAUSE_OVERLAY_PATH) as GDScript).new()) as Control
	var player := _player_fixture()
	overlay.call("configure", player, _content_fixture(), null, 3, 8, 17.2)
	add_child(overlay)
	assert_vector(overlay.size).is_equal(Vector2(1280, 720))
	assert_int(overlay.process_mode).is_equal(Node.PROCESS_MODE_WHEN_PAUSED)
	for path in [
		"DimVeil",
		"PauseMenu",
		"Loadout",
		"StatsColumn",
		"WaveProgress",
		"ExitConfirmation",
	]:
		assert_bool(overlay.has_node(path)).is_true()
	for path in [
		"PauseMenu/ContinueButton",
		"PauseMenu/RestartButton",
		"PauseMenu/EndRunButton",
		"PauseMenu/SettingsButton",
		"PauseMenu/ReturnButton",
	]:
		assert_bool(overlay.has_node(path)).is_true()
	var weapon_slots := overlay.get_node("Loadout/Weapons") as HBoxContainer
	var owned_weapons := player.weapon_inventory.records()
	assert_int(weapon_slots.get_child_count()).is_equal(owned_weapons.size())
	for index in owned_weapons.size():
		var slot := weapon_slots.get_child(index) as Button
		var record := owned_weapons[index] as Dictionary
		assert_bool(slot.has_meta(&"inventory_instance_id")).is_true()
		assert_bool(slot.has_meta(&"content_id")).is_true()
		assert_int(int(slot.get_meta(&"inventory_instance_id"))).is_equal(
			int(record.get(&"instance_id", 0))
		)
		assert_str(String(slot.get_meta(&"content_id"))).is_equal(
			String(record.get(&"content_id", &""))
		)
	var item_slots := overlay.get_node("Loadout/ItemsScroll/ItemsGrid") as GridContainer
	assert_int(item_slots.get_child_count()).is_equal(player.item_ids.size())
	for index in player.item_ids.size():
		var slot := item_slots.get_child(index) as Control
		assert_bool(slot.has_meta(&"content_id")).is_true()
		assert_str(String(slot.get_meta(&"content_id"))).is_equal(String(player.item_ids[index]))
	assert_int(overlay.get_node("StatsColumn/Rows").get_child_count()).is_greater(0)
	assert_str((overlay.get_node("WaveProgress/Wave") as Label).text).contains("3 / 8")
	assert_str((overlay.get_node("WaveProgress/Time") as Label).text).contains("18")


func test_danger_actions_require_confirmation_before_emitting() -> void:
	if not FileAccess.file_exists(PAUSE_OVERLAY_PATH):
		return
	var overlay := auto_free((load(PAUSE_OVERLAY_PATH) as GDScript).new()) as Control
	overlay.call("configure", _player_fixture(), _content_fixture(), null, 1, 8, 20.0)
	add_child(overlay)
	var calls: Array[StringName] = []
	overlay.connect("end_run_requested", func() -> void: calls.append(&"end"))
	overlay.connect("return_to_menu_requested", func() -> void: calls.append(&"return"))
	var confirmation := overlay.get_node("ExitConfirmation") as Control
	(overlay.get_node("PauseMenu/EndRunButton") as Button).emit_signal("pressed")
	assert_bool(confirmation.visible).is_true()
	assert_array(calls).is_empty()
	(confirmation.get_node("CancelButton") as Button).emit_signal("pressed")
	assert_bool(confirmation.visible).is_false()
	assert_array(calls).is_empty()
	(overlay.get_node("PauseMenu/EndRunButton") as Button).emit_signal("pressed")
	(confirmation.get_node("ConfirmButton") as Button).emit_signal("pressed")
	assert_array(calls).is_equal([&"end"])

	(overlay.get_node("PauseMenu/ReturnButton") as Button).emit_signal("pressed")
	assert_bool(confirmation.visible).is_true()
	assert_array(calls).is_equal([&"end"])
	(confirmation.get_node("ConfirmButton") as Button).emit_signal("pressed")
	assert_array(calls).is_equal([&"end", &"return"])


func test_safe_actions_emit_immediately_and_settings_opens_inline_panel() -> void:
	if not FileAccess.file_exists(PAUSE_OVERLAY_PATH):
		return
	var overlay := auto_free((load(PAUSE_OVERLAY_PATH) as GDScript).new()) as Control
	overlay.call("configure", _player_fixture(), _content_fixture(), null, 1, 8, 20.0)
	add_child(overlay)
	var calls: Array[StringName] = []
	overlay.connect("continue_requested", func() -> void: calls.append(&"continue"))
	overlay.connect("restart_requested", func() -> void: calls.append(&"restart"))
	(overlay.get_node("PauseMenu/ContinueButton") as Button).emit_signal("pressed")
	(overlay.get_node("PauseMenu/RestartButton") as Button).emit_signal("pressed")
	assert_array(calls).is_equal([&"continue", &"restart"])
	var settings := overlay.get_node("SettingsPanel") as Control
	assert_bool(settings.visible).is_false()
	(overlay.get_node("PauseMenu/SettingsButton") as Button).emit_signal("pressed")
	assert_bool(settings.visible).is_true()
	(settings.get_node("CloseButton") as Button).emit_signal("pressed")
	assert_bool(settings.visible).is_false()


func _player_fixture() -> SessionPlayerState:
	var player := SessionPlayerState.new()
	player.character_id = ValidationContentFactory.CHARACTER_ID
	player.level = 4
	player.current_health = 17.0
	player.max_health = 20.0
	player.materials = 87
	player.base_stats = {
		&"max_health": 20.0,
		&"damage_multiplier": 1.0,
		&"movement_speed": 100.0,
	}
	player.final_stats = player.base_stats.duplicate(true)
	var content := _content_fixture()
	var ranged := player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, content, 1)
	var melee := player.weapon_inventory.add_weapon(ValidationContentFactory.MELEE_ID, content, 1)
	assert_int(int(ranged.error)).is_equal(OK)
	assert_int(int(melee.error)).is_equal(OK)
	player.item_ids.assign([
		&"gogobro.core:item/training_1",
		&"gogobro.core:item/training_2",
	])
	return player


func _content_fixture() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
