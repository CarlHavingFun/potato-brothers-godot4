extends GdUnitTestSuite


const HUD_SCENE_PATH := "res://scenes/ui/combat_hud/combat_hud.tscn"
const METRICS_PATH := "res://core/presentation/combat_hud_metrics.gd"


func test_combat_hud_renders_the_complete_hud_state_from_one_entry_point() -> void:
	# Break caught: an arena-owned partial refresh leaves one visible HUD field stale.
	var packed := load(HUD_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var hud: Control = auto_free(packed.instantiate()) as Control
	add_child(hud)
	await await_idle_frame()
	var state := HudState.new()
	state.wave = 7
	state.standard_wave_count = 20
	state.seconds_remaining = 12
	state.materials = 51
	state.material_bag = 5
	state.level = 3
	state.experience = 4
	state.experience_required = 10
	state.health = 9
	state.max_health = 12

	hud.call("apply_state", state)

	assert_str((hud.get_node("TopLeft/HealthBar/Value") as Label).text).is_equal("9 / 12")
	assert_str((hud.get_node("TopLeft/ExperienceBar/Level") as Label).text).is_equal("LV.3")
	assert_float((hud.get_node("TopLeft/HealthBar") as ProgressBar).value).is_equal(9.0)
	assert_float((hud.get_node("TopLeft/ExperienceBar") as ProgressBar).value).is_equal(4.0)
	assert_str((hud.get_node("TopLeft/Materials/Value") as Label).text).is_equal("51")
	assert_bool((hud.get_node("TopLeft/MaterialBag") as Control).visible).is_true()
	assert_str((hud.get_node("TopCenter/Wave") as Label).text).is_equal(
		LocalizedTextService.resolve(&"ui.hud.wave.standard", [7])
	)
	assert_str((hud.get_node("TopCenter/Countdown") as Label).text).is_equal("12")


func test_combat_hud_hides_empty_material_bag_without_affecting_materials() -> void:
	# Break caught: a zero bag renders an empty persistent HUD row.
	var packed := load(HUD_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var hud: Control = auto_free(packed.instantiate()) as Control
	add_child(hud)
	await await_idle_frame()
	var state := HudState.new()
	state.materials = 51
	state.material_bag = 0

	hud.call("apply_state", state)

	assert_str((hud.get_node("TopLeft/Materials/Value") as Label).text).is_equal("51")
	assert_bool((hud.get_node("TopLeft/MaterialBag") as Control).visible).is_false()


func test_combat_hud_keeps_boss_and_notice_outside_full_state_rows() -> void:
	# Break caught: a boss or transient notice changes wave/state rows instead of its own region.
	var packed := load(HUD_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()
	if packed == null:
		return
	var hud: Control = auto_free(packed.instantiate()) as Control
	add_child(hud)
	await await_idle_frame()
	var state := HudState.new()
	state.wave = 2
	state.seconds_remaining = 30
	hud.call("apply_state", state)
	hud.call("update_boss_status", "Boss 100 / 100")
	hud.call("show_notice", "Level up!")

	assert_str((hud.get_node("TopCenter/Wave") as Label).text).is_equal(
		LocalizedTextService.resolve(&"ui.hud.wave.standard", [2])
	)
	assert_str((hud.get_node("TopCenter/Countdown") as Label).text).is_equal("30")
	assert_bool((hud.get_node("BossStatus") as Control).visible).is_true()
	assert_bool((hud.get_node("Notice") as Control).visible).is_true()
	assert_object(hud.find_child("EncounterLabel", true, false)).is_null()
	assert_object(hud.find_child("NextWaveLabel", true, false)).is_null()


func test_combat_hud_metrics_project_reference_anchors_at_every_16_by_9_size() -> void:
	# Break caught: changing viewport scale moves reference anchors or makes HUD regions overlap.
	var metrics := load(METRICS_PATH)
	assert_object(metrics).is_not_null()
	if metrics == null:
		return
	for physical_size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080)]:
		var layout: Dictionary = metrics.call("layout_for_output", physical_size)
		var health := layout.get("health", Rect2()) as Rect2
		var experience := layout.get("experience", Rect2()) as Rect2
		var materials := layout.get("materials", Rect2()) as Rect2
		var wave := layout.get("wave", Rect2()) as Rect2
		var countdown := layout.get("countdown", Rect2()) as Rect2
		var scale := physical_size.x / 1280.0
		assert_float(health.position.x).is_equal_approx(20.0 * scale, 0.01)
		assert_float(health.position.y).is_equal_approx(16.0 * scale, 0.01)
		assert_float(health.size.x).is_equal_approx(205.0 * scale, 0.01)
		assert_float(experience.position.y).is_equal_approx(50.0 * scale, 0.01)
		assert_float(materials.position.y).is_equal_approx(85.0 * scale, 0.01)
		assert_float(wave.get_center().x).is_equal_approx(physical_size.x * 0.5, 0.01)
		assert_float(wave.position.y).is_equal_approx(12.0 * scale, 0.01)
		assert_float(countdown.get_center().x).is_equal_approx(physical_size.x * 0.5, 0.01)
		assert_float(countdown.position.y).is_between(45.0 * scale, 49.0 * scale)
		assert_bool(not health.intersects(experience)).is_true()
		assert_bool(not experience.intersects(materials)).is_true()
		assert_bool(not wave.intersects(countdown)).is_true()


func test_instantiated_combat_hud_projects_all_live_regions_from_metrics_at_16_by_9_outputs() -> void:
	# Break caught: changing a metric no longer changes the actual HUD controls.
	var packed := load(HUD_SCENE_PATH) as PackedScene
	var metrics := load(METRICS_PATH)
	assert_object(packed).is_not_null()
	assert_object(metrics).is_not_null()
	if packed == null or metrics == null:
		return
	var hud: Control = auto_free(packed.instantiate()) as Control
	add_child(hud)
	await await_idle_frame()
	assert_bool(hud.has_method("apply_metric_layout")).is_true()
	if not hud.has_method("apply_metric_layout"):
		return
	hud.call("apply_metric_layout")
	hud.size = Vector2(1920, 1080)
	hud.call("apply_metric_layout")
	var regions := {
		"health": hud.get_node("TopLeft/HealthBar") as Control,
		"experience": hud.get_node("TopLeft/ExperienceBar") as Control,
		"materials": hud.get_node("TopLeft/Materials") as Control,
		"material_bag": hud.get_node("TopLeft/MaterialBag") as Control,
		"wave": hud.get_node("TopCenter/Wave") as Control,
		"countdown": hud.get_node("TopCenter/Countdown") as Control,
		"boss": hud.get_node("BossStatus") as Control,
		"notice": hud.get_node("Notice") as Control,
	}
	for physical_size: Vector2 in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080)]:
		var expected_layout: Dictionary = metrics.call("layout_for_output", physical_size)
		var output_scale := physical_size.x / 1920.0
		for region_id: String in regions:
			var control := regions[region_id] as Control
			var rendered := Rect2(control.position * output_scale, control.size * output_scale)
			var expected := expected_layout[region_id] as Rect2
			assert_float(rendered.position.x).is_equal_approx(expected.position.x, 0.01)
			assert_float(rendered.position.y).is_equal_approx(expected.position.y, 0.01)
			assert_float(rendered.size.x).is_equal_approx(expected.size.x, 0.01)
			assert_float(rendered.size.y).is_equal_approx(expected.size.y, 0.01)


func test_pause_panel_has_live_loadout_stats_and_progress_sections() -> void:
	# Break caught: pause overlay regresses to an empty menu without run information.
	var panel := auto_free((load("res://scenes/ui/pause_panel/pause_panel.tscn") as PackedScene).instantiate()) as PausePanel
	add_child(panel)
	await await_idle_frame()
	assert_object(panel.get_node_or_null("Content/LeftMenu")).is_not_null()
	assert_object(panel.get_node_or_null("Content/Loadout/WeaponsLabel")).is_not_null()
	assert_object(panel.get_node_or_null("Content/Loadout/ItemsLabel")).is_not_null()
	assert_object(panel.get_node_or_null("Content/StatsZone/StatsContainer")).is_not_null()
	assert_object(panel.get_node_or_null("Content/RunProgress/ProgressLabel")).is_not_null()


func test_pause_panel_localizes_sections_and_inventory_display_names() -> void:
	# Break caught: pause UI leaks hard-coded English headings and stable content IDs.
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var panel := auto_free((load("res://scenes/ui/pause_panel/pause_panel.tscn") as PackedScene).instantiate()) as PausePanel
	add_child(panel)
	await await_idle_frame()
	var run := RunState.new()
	var weapon := Content.catalog.get_weapon(&"weapon/pistol")
	var passive := Content.catalog.get_passive(&"passive/coffee")
	assert_object(weapon).is_not_null()
	assert_object(passive).is_not_null()
	if weapon == null or passive == null:
		TranslationServer.set_locale(original_locale)
		return
	var weapon_id := weapon.get_stable_id(Content.catalog.pack_id)
	var passive_id := passive.get_stable_id(Content.catalog.pack_id)
	run.inventory.add_weapon(weapon_id, 2, 10)
	run.inventory.add_passive(passive_id, 3)

	panel.refresh_from_run(run)

	assert_str((panel.get_node("Content/Loadout/WeaponsTitle") as Label).text).is_equal(
		LocalizedTextService.resolve(&"ui.pause.weapons")
	)
	assert_str((panel.get_node("Content/Loadout/ItemsTitle") as Label).text).is_equal(
		LocalizedTextService.resolve(&"ui.pause.items")
	)
	assert_str((panel.get_node("Content/RunProgress/Title") as Label).text).is_equal(
		LocalizedTextService.resolve(&"ui.pause.progress")
	)
	var expected_weapon := LocalizedTextService.resolve(&"ui.pause.weapon_entry", [
		ItemDescriptionFormatter.item_display_name(weapon.tiers[1]), 2,
	])
	var expected_passive := LocalizedTextService.resolve(&"ui.pause.item_entry", [
		ItemDescriptionFormatter.item_display_name(passive.item), 3,
	])
	assert_str((panel.get_node("Content/Loadout/WeaponsLabel") as Label).text).is_equal(expected_weapon)
	assert_str((panel.get_node("Content/Loadout/ItemsLabel") as Label).text).is_equal(expected_passive)
	assert_str((panel.get_node("Content/Loadout/WeaponsLabel") as Label).text).not_contains("weapon/")
	assert_str((panel.get_node("Content/Loadout/ItemsLabel") as Label).text).not_contains("passive/")
	TranslationServer.set_locale(original_locale)


func test_pause_progress_reports_endless_wave_without_a_standard_twenty_wave_cap() -> void:
	# Break caught: Endless wave 21+ is rendered as the impossible "Wave N / 20".
	var panel := auto_free((load("res://scenes/ui/pause_panel/pause_panel.tscn") as PackedScene).instantiate()) as PausePanel
	add_child(panel)
	await await_idle_frame()
	var run := RunState.new()
	run.run_mode = RunMode.ENDLESS
	run.wave = 23
	run.endless_cycle = 1

	panel.refresh_from_run(run)

	var progress := panel.get_node("Content/RunProgress/ProgressLabel") as Label
	assert_str(progress.text).is_equal(LocalizedTextService.resolve(&"ui.pause.progress.endless", [23]))
	assert_str(progress.text).not_contains("/ 20")
