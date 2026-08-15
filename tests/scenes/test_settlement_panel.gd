extends GdUnitTestSuite


const SETTLEMENT_SCENE := "res://scenes/ui/settlement_panel/settlement_panel.tscn"


func test_endless_settlement_reports_wave_kills_bosses_materials_and_time() -> void:
	var panel: SettlementPanel = auto_free(load(SETTLEMENT_SCENE).instantiate())
	add_child(panel)
	await await_idle_frame()
	var run := RunState.new()
	run.run_mode = RunMode.ENDLESS
	run.character_id = &"core:test_character"
	run.difficulty = 4
	run.wave = 51
	run.highest_wave_reached = 51
	run.kill_count = 1200
	run.boss_kill_count = 5
	run.materials = 987
	run.elapsed_seconds = 3723.0

	panel.show_result(run, false)

	assert_str(panel.details_label.text).contains("51")
	assert_str(panel.details_label.text).contains("1200")
	assert_str(panel.details_label.text).contains("5")
	assert_str(panel.details_label.text).contains("987")
	assert_str(panel.details_label.text).contains("62:03")


func test_standard_settlement_keeps_standard_summary() -> void:
	var panel: SettlementPanel = auto_free(load(SETTLEMENT_SCENE).instantiate())
	add_child(panel)
	await await_idle_frame()
	var run := RunState.new()
	run.character_id = &"core:test_character"
	run.difficulty = 2
	run.wave = 20
	run.materials = 77

	panel.show_result(run, true)

	assert_str(panel.details_label.text).contains("20 / 20")
	assert_str(panel.details_label.text).contains("77")
