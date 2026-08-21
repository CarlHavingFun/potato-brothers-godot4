extends GdUnitTestSuite


const GAME_ROOT_SCENE := "res://scenes/game_root/game_root.tscn"
const TEST_SAVE_ROOT := "user://tests/game_root_profiles"

var _original_provider: SaveProvider


func before_test() -> void:
	_original_provider = Global.save_provider
	Global.save_provider = ProfileSaveProvider.new(ProfileStore.new(TEST_SAVE_ROOT, ""), 1)
	Global.meta_progress = MetaProgress.new()
	Global.end_run()


func after_test() -> void:
	Global.end_run()
	Global.save_provider = _original_provider
	Global.meta_progress = MetaProgress.new()
	for slot in range(1, ProfileStore.MAX_PROFILES + 1):
		ProfileStore.new(TEST_SAVE_ROOT, "").delete_profile(slot)


func test_game_root_owns_frontend_and_keeps_legacy_arena_frontend_hidden() -> void:
	assert_bool(ResourceLoader.exists(GAME_ROOT_SCENE)).is_true()
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()

	assert_object(root.get_node("Arena")).is_not_null()
	assert_bool(root.get_node("FrontendLayer/FrontendShell").visible).is_true()
	assert_bool(root.get_node("Arena/GameUI/TitlePanel").visible).is_false()
	assert_bool(root.get_node("Arena/GameUI/SelectionPanel").visible).is_false()
	assert_bool(root.get_node("Arena/GameUI/DifficultyPanel").visible).is_false()
	assert_object(root.get_node("FrontendLayer/CodexPanel")).is_not_null()


func test_active_skin_theme_reaches_every_top_level_ui_surface() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	var controls: Array[Control] = [
		root.get_node("FrontendLayer/FrontendShell") as Control,
		root.get_node("FrontendLayer/CodexPanel") as Control,
	]
	for child: Node in root.get_node("Arena/GameUI").get_children():
		if child is Control:
			controls.append(child as Control)
	for control: Control in controls:
		assert_object(control.theme).is_not_null()
		if control.theme != null:
			assert_object(control.theme.default_font).is_not_null()


func test_reference_theme_has_smooth_dark_edges_and_text_outlines() -> void:
	var theme := Presentation.active_skin.theme
	assert_object(theme).is_not_null()
	if theme == null:
		return
	assert_int(theme.get_constant("outline_size", "Label")).is_equal(2)
	assert_int(theme.get_constant("outline_size", "Button")).is_equal(2)
	for state in [&"normal", &"hover", &"focus", &"pressed"]:
		var style := theme.get_stylebox(state, &"Button") as StyleBoxFlat
		assert_object(style).is_not_null()
		if style == null:
			continue
		assert_bool(style.anti_aliasing).is_true()
		assert_float(style.anti_aliasing_size).is_equal_approx(1.25, 0.001)
		assert_int(style.border_width_left).is_equal(2)
		assert_int(style.corner_radius_top_left).is_equal(6)
		assert_bool(style.bg_color.r < 0.12).is_true()
	var panel_style := theme.get_stylebox(&"panel", &"Panel") as StyleBoxFlat
	assert_object(panel_style).is_not_null()
	if panel_style != null:
		assert_int(panel_style.border_width_left).is_equal(2)
		assert_int(panel_style.corner_radius_top_left).is_equal(6)


func test_post_wave_panels_are_translucent_and_fullscreen_images_use_linear_filtering() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	var arena := root.get_node("Arena") as Arena
	assert_int(arena.background.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR)
	assert_int(arena.floor_background.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR)
	assert_int(
		(root.get_node("FrontendLayer/FrontendShell/Background") as TextureRect).texture_filter
	).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR)
	for panel_path in ["UpgradePanel", "RewardPanel", "ShopPanel"]:
		var panel := root.get_node("Arena/GameUI/%s" % panel_path) as Panel
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		assert_object(style).is_not_null()
		if style != null:
			assert_float(style.bg_color.a).is_between(0.55, 0.82)


func test_headings_and_combat_numbers_use_reference_outline_hierarchy() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	for label_path in [
		"Arena/GameUI/UpgradePanel/MarginContainer/HBoxContainer/VBoxContainer/Label",
		"Arena/GameUI/ShopPanel/MarginContainer/Control/Title",
		"Arena/GameUI/RewardPanel/Center/Card/Title",
		"Arena/GameUI/PausePanel/Content/LeftMenu/Title",
		"Arena/GameUI/SettlementPanel/Center/Content/ResultLabel",
		"Arena/GameUI/SettingsPanel/SafeArea/Layout/Header/Title",
		"FrontendLayer/CodexPanel/SafeArea/Layout/Header/Title",
	]:
		var label := root.get_node(label_path) as Label
		assert_int(label.get_theme_constant("outline_size")).is_equal(4)
	for label_path in ["Arena/GameUI/CombatHud/TopCenter/Wave", "Arena/GameUI/CombatHud/TopCenter/Countdown"]:
		var label := root.get_node(label_path) as Label
		assert_int(label.label_settings.outline_size).is_equal(6)
	var floating: Node = auto_free(
		(load("res://scenes/ui/floating_text/floating_text.tscn") as PackedScene).instantiate()
	)
	add_child(floating)
	assert_int((floating.get_node("ValueLabel") as Label).label_settings.outline_size).is_equal(6)


func test_codex_builds_all_four_discovery_categories_and_returns_to_title() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	Global.meta_progress.mark_discovered(
		Content.catalog.get_characters()[0].get_stable_id(Content.catalog.pack_id)
	)

	root.call("_show_codex")
	var codex := root.get_node("FrontendLayer/CodexPanel")
	assert_bool(codex.visible).is_true()
	assert_int(codex.call("category_count")).is_equal(4)
	assert_int(codex.call("entry_count")).is_equal(Content.catalog.get_characters().size())
	codex.call("close_codex")
	assert_bool(root.get_node("FrontendLayer/FrontendShell").visible).is_true()


func test_run_launch_request_is_the_only_frontend_to_combat_bridge() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0]
	var request := RunLaunchRequest.new()
	request.profile_id = 1
	request.character_id = character.get_stable_id(Content.catalog.pack_id)
	request.weapon_id = weapon.get_stable_id(Content.catalog.pack_id)
	request.difficulty = 1
	request.aim_mode = AimMode.MANUAL_MOUSE
	request.run_mode = RunMode.ENDLESS
	request.random_seed = 8128

	assert_bool(root.call("launch_run", request)).is_true()

	assert_bool(root.get_node("FrontendLayer/FrontendShell").visible).is_false()
	assert_object(Global.player).is_not_null()
	assert_int(Global.current_run.random_seed).is_equal(8128)
	assert_int(Global.current_run.difficulty).is_equal(1)
	assert_int(Global.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_int(Global.current_run.run_mode).is_equal(RunMode.ENDLESS)
	assert_int(Global.current_run.phase).is_equal(RunPhase.COMBAT)
	assert_bool(Global.save_provider.load_slot().has("run_state")).is_true()
	assert_int(Global.active_profile_id()).is_equal(1)
	assert_bool(FileAccess.file_exists("%s/1/save_v4.json" % TEST_SAVE_ROOT)).is_true()
	root.call("return_to_frontend")


func test_character_core_rule_is_applied_once_before_player_spawn() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	var character := Content.catalog.get_character(&"character/scrap_broker")
	var weapon := Content.catalog.get_weapon(character.starter_weapon_ids[0])
	var request := RunLaunchRequest.new()
	request.profile_id = 1
	request.character_id = character.get_stable_id(Content.catalog.pack_id)
	request.weapon_id = weapon.get_stable_id(Content.catalog.pack_id)
	request.difficulty = 1
	request.random_seed = 8181

	assert_bool(root.call("launch_run", request)).is_true()

	assert_bool(Global.current_run.character_rule_applied).is_true()
	assert_str(String(Global.current_run.character_rule_id)).is_equal("character_rule/scrap_broker")
	assert_int(Global.current_run.materials).is_zero()
	assert_bool(Global.current_run.materials_reset_on_wave_start).is_true()
	assert_array(Global.current_run.shop_bias_tags).contains([&"economy", &"luck"])
	root.call("return_to_frontend")


func test_continue_rebuilds_the_saved_wave_without_serializing_live_enemies() -> void:
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0]
	Global.select_character(character)
	Global.select_starting_weapon(weapon)
	assert_bool(Global.begin_selected_run(444)).is_true()
	Global.current_run.wave = 7
	Global.current_run.difficulty = 2
	Global.current_run.materials = 123
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_progress(true)
	Global.end_run()
	Global.load_progress()
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()

	root.call("_continue_run")

	assert_object(Global.player).is_not_null()
	assert_int(Global.current_run.wave).is_equal(7)
	assert_int(Global.current_run.materials).is_equal(123)
	assert_int(root.get_node("Arena/Spawner").wave_index).is_equal(7)
	assert_int(root.get_node("Arena/Spawner").spawned_enemies.size()).is_equal(0)
	assert_bool(root.get_node("FrontendLayer/FrontendShell").visible).is_false()
	root.call("return_to_frontend")


func test_continue_rebuilds_an_endless_wave_from_generator_and_restores_run_totals() -> void:
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0]
	Global.select_character(character)
	Global.select_starting_weapon(weapon)
	assert_bool(Global.begin_selected_run(5050)).is_true()
	Global.current_run.run_mode = RunMode.ENDLESS
	Global.current_run.wave = 50
	Global.current_run.endless_cycle = 6
	Global.current_run.highest_wave_reached = 50
	Global.current_run.kill_count = 1450
	Global.current_run.boss_kill_count = 7
	Global.enter_phase(RunPhase.COMBAT)
	Global.save_progress(true)
	Global.end_run()
	Global.load_progress()
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()

	root.call("_continue_run")

	var spawner := root.get_node("Arena/Spawner")
	assert_int(Global.current_run.run_mode).is_equal(RunMode.ENDLESS)
	assert_int(Global.current_run.wave).is_equal(50)
	assert_int(Global.current_run.endless_cycle).is_equal(6)
	assert_int(Global.current_run.kill_count).is_equal(1450)
	assert_int(Global.current_run.boss_kill_count).is_equal(7)
	assert_int(spawner.wave_index).is_equal(50)
	assert_int(spawner.current_wave_definition.endless_cycle).is_equal(6)
	assert_int(spawner.current_wave_definition.priority_spawn_count).is_equal(2)
	root.call("return_to_frontend")


func test_continue_restores_shop_checkpoint_without_replaying_completed_wave() -> void:
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0]
	Global.select_character(character)
	Global.select_starting_weapon(weapon)
	assert_bool(Global.begin_selected_run(445)).is_true()
	Global.enter_phase(RunPhase.COMBAT)
	Global.current_run.wave = 6
	Global.enter_phase(RunPhase.UPGRADE)
	Global.enter_phase(RunPhase.SHOP)
	Global.save_progress(true)
	Global.end_run()
	Global.load_progress()
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()

	root.call("_continue_run")

	assert_int(Global.current_run.phase).is_equal(RunPhase.SHOP)
	assert_int(Global.current_run.wave).is_equal(6)
	assert_bool(root.get_node("Arena/GameUI/ShopPanel").visible).is_true()
	assert_bool(root.get_node("Arena/Spawner/WaveTimer").is_stopped()).is_true()
	root.call("return_to_frontend")


func test_continue_restores_upgrade_and_chest_checkpoints_to_their_panels() -> void:
	for phase: int in [RunPhase.UPGRADE, RunPhase.CHEST]:
		var character := Content.catalog.get_characters()[0]
		var weapon := Content.catalog.get_weapons()[0]
		Global.select_character(character)
		Global.select_starting_weapon(weapon)
		assert_bool(Global.begin_selected_run(500 + phase)).is_true()
		Global.enter_phase(RunPhase.COMBAT)
		Global.current_run.wave = 8
		Global.current_run.queued_level_ups = 1
		Global.current_run.queued_rewards = 1
		Global.enter_phase(RunPhase.UPGRADE)
		if phase == RunPhase.CHEST:
			Global.enter_phase(RunPhase.CHEST)
		Global.save_progress(true)
		Global.end_run()
		Global.load_progress()
		var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
		add_child(root)
		await await_idle_frame()
		await await_idle_frame()

		root.call("_continue_run")

		assert_int(Global.current_run.phase).is_equal(phase)
		var panel_name := "UpgradePanel" if phase == RunPhase.UPGRADE else "RewardPanel"
		assert_bool(root.get_node("Arena/GameUI/%s" % panel_name).visible).is_true()
		assert_bool(root.get_node("Arena/Spawner/WaveTimer").is_stopped()).is_true()
		root.call("return_to_frontend")
		root.queue_free()
		await await_idle_frame()


func test_upgrade_to_chest_persists_target_phase_and_rejects_free_upgrade() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(root.call("launch_run", _make_launch_request(611))).is_true()
	var arena := root.get_node("Arena") as Arena
	Global.current_run.queued_level_ups = 1
	Global.current_run.queued_rewards = 1
	Global.enter_phase(RunPhase.UPGRADE)

	arena.call("_on_upgrade_selected")

	var saved := RunState.from_dict(Global.save_provider.load_slot().get("run_state", {}))
	assert_int(saved.phase).is_equal(RunPhase.CHEST)
	assert_int(saved.queued_level_ups).is_zero()
	var upgrade := Content.catalog.get_upgrade_items()[0]
	var definition := Content.catalog.get_upgrade_definition_for_item(upgrade)
	var before := Global.current_run.player_stats.get_stat(definition.stat_id)
	var card: UpgradeCard = auto_free(load("res://scenes/ui/upgrade_card/upgrade_card.tscn").instantiate()) as UpgradeCard
	add_child(card)
	await await_idle_frame()
	card.item_data = upgrade
	card.call("_on_custom_buttom_pressed")
	assert_float(Global.current_run.player_stats.get_stat(definition.stat_id)).is_equal(before)
	root.call("return_to_frontend")


func test_return_to_title_then_continue_loads_the_latest_same_process_checkpoint() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(root.call("launch_run", _make_launch_request(612))).is_true()
	Global.enter_phase(RunPhase.UPGRADE)
	Global.enter_phase(RunPhase.SHOP)
	Global.current_run.materials = 321
	Global.save_progress(true)

	root.call("return_to_frontend")
	root.call("_continue_run")

	assert_object(Global.current_run).is_not_null()
	assert_int(Global.current_run.materials).is_equal(321)
	assert_bool(root.get_node("FrontendLayer/FrontendShell").visible).is_false()
	root.call("return_to_frontend")


func test_new_wave_checkpoint_precedes_wave_started_effects_and_rng() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(root.call("launch_run", _make_launch_request(613))).is_true()
	var effect := EffectDef.new()
	effect.effect_id = &"effect/test/wave_checkpoint"
	effect.trigger_events = [GameplayEvent.Type.WAVE_STARTED]
	effect.conditions = [EffectConditionDef.roll(1.0)]
	effect.operations = [EffectOperationDef.add_stat(StatId.DAMAGE, 7.0)]
	Global.gameplay_effects.register_effect(effect)
	Global.enter_phase(RunPhase.UPGRADE)
	Global.enter_phase(RunPhase.SHOP)
	var before_damage := Global.current_run.player_stats.get_stat(StatId.DAMAGE)
	var before_effect_rng := Global.gameplay_effects.rng.state

	(root.get_node("Arena") as Arena).start_new_wave()

	var saved := RunState.from_dict(Global.save_provider.load_slot().get("run_state", {}))
	assert_float(Global.current_run.player_stats.get_stat(StatId.DAMAGE)).is_equal(before_damage + 7.0)
	assert_float(saved.player_stats.get_stat(StatId.DAMAGE)).is_equal(before_damage)
	assert_int(int(saved.rng_states.get("effects", 0))).is_equal(before_effect_rng)
	root.call("return_to_frontend")


func test_post_wave_snapshot_persists_until_the_next_wave_starts() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(root.call("launch_run", _make_launch_request(616))).is_true()
	var arena := root.get_node("Arena") as Arena
	var snapshot := root.get_node_or_null("Arena/GameUI/PostWaveSnapshot") as TextureRect
	assert_object(snapshot).is_not_null()
	assert_bool(arena.has_method("_capture_post_wave_snapshot")).is_true()
	if snapshot == null or not arena.has_method("_capture_post_wave_snapshot"):
		root.call("return_to_frontend")
		return

	var source_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source_image.fill(Color("352f2b"))
	assert_bool(bool(arena.call("_capture_post_wave_snapshot", source_image))).is_true()
	assert_bool(snapshot.visible).is_true()
	assert_object(snapshot.texture).is_not_null()
	assert_bool(Global.enter_phase(RunPhase.UPGRADE)).is_true()
	assert_bool(Global.enter_phase(RunPhase.SHOP)).is_true()
	assert_bool(snapshot.visible).is_true()

	arena.start_new_wave()
	assert_bool(snapshot.visible).is_false()
	assert_object(snapshot.texture).is_null()
	root.call("return_to_frontend")


func test_post_wave_snapshot_is_released_on_run_reset() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(root.call("launch_run", _make_launch_request(617))).is_true()
	var arena := root.get_node("Arena") as Arena
	var snapshot := root.get_node_or_null("Arena/GameUI/PostWaveSnapshot") as TextureRect
	assert_object(snapshot).is_not_null()
	assert_bool(arena.has_method("_capture_post_wave_snapshot")).is_true()
	if snapshot == null or not arena.has_method("_capture_post_wave_snapshot"):
		root.call("return_to_frontend")
		return
	var source_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source_image.fill(Color("352f2b"))
	arena.call("_capture_post_wave_snapshot", source_image)

	root.call("return_to_frontend")
	assert_bool(snapshot.visible).is_false()
	assert_object(snapshot.texture).is_null()


func test_settlement_keeps_the_last_combat_snapshot_after_death_or_victory() -> void:
	# Break caught: settlement cleanup clears the captured last frame before its overlay is shown.
	for victory: bool in [false, true]:
		var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
		add_child(root)
		await await_idle_frame()
		await await_idle_frame()
		assert_bool(root.call("launch_run", _make_launch_request(700 + int(victory)))).is_true()
		var arena := root.get_node("Arena") as Arena
		var snapshot := root.get_node("Arena/GameUI/PostWaveSnapshot") as TextureRect
		var source_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		source_image.fill(Color("352f2b"))
		assert_bool(bool(arena.call("_capture_post_wave_snapshot", source_image))).is_true()

		arena.finish_run(victory)

		assert_bool(snapshot.visible).is_true()
		assert_object(snapshot.texture).is_not_null()
		assert_bool((root.get_node("Arena/GameUI/SettlementPanel") as Control).visible).is_true()
		root.call("return_to_frontend")
		root.queue_free()
		await await_idle_frame()


func test_passive_chest_reward_applies_stats_exactly_once_through_arena_signal_chain() -> void:
	var root: Node = auto_free(load(GAME_ROOT_SCENE).instantiate())
	add_child(root)
	await await_idle_frame()
	await await_idle_frame()
	var character := Content.catalog.get_character(&"character/well_rounded")
	var weapon := Content.catalog.get_weapon(character.starter_weapon_ids[0])
	var request := RunLaunchRequest.new()
	request.profile_id = 1
	request.character_id = character.get_stable_id(Content.catalog.pack_id)
	request.weapon_id = weapon.get_stable_id(Content.catalog.pack_id)
	request.difficulty = 1
	request.random_seed = 614
	assert_bool(root.call("launch_run", request)).is_true()
	var passive := Content.catalog.get_passive(&"passive/coffee")
	assert_object(passive).is_not_null()
	if passive == null:
		root.call("return_to_frontend")
		return
	Global.current_run.queued_rewards = 1
	assert_bool(Global.enter_phase(RunPhase.UPGRADE)).is_true()
	assert_bool(Global.enter_phase(RunPhase.CHEST)).is_true()
	var attack_speed_before := Global.current_run.player_stats.get_stat(StatId.ATTACK_SPEED)
	var expected_delta := float(passive.stat_modifiers.get("attack_speed", 0.0))
	var reward_panel := root.get_node("Arena/GameUI/RewardPanel") as RewardPanel
	reward_panel.reward_item = passive.item

	reward_panel.call("_on_claim_button_pressed")

	var stable_id := passive.get_stable_id(Content.catalog.pack_id)
	assert_int(Global.current_run.inventory.passive_count(stable_id)).is_equal(1)
	assert_float(Global.current_run.player_stats.get_stat(StatId.ATTACK_SPEED)).is_equal(
		attack_speed_before + expected_delta
	)
	root.call("return_to_frontend")


func _make_launch_request(seed_value: int) -> RunLaunchRequest:
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapons()[0]
	var request := RunLaunchRequest.new()
	request.profile_id = 1
	request.character_id = character.get_stable_id(Content.catalog.pack_id)
	request.weapon_id = weapon.get_stable_id(Content.catalog.pack_id)
	request.difficulty = 1
	request.aim_mode = AimMode.AUTO_TARGET
	request.random_seed = seed_value
	return request
