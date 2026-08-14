extends GdUnitTestSuite


const ARENA_SCENE := "res://scenes/arena/arena.tscn"
const REQUIRED_PANELS := [&"TitlePanel", &"SelectionPanel", &"DifficultyPanel", &"PausePanel", &"SettlementPanel"]


func test_title_to_difficulty_flow_does_not_start_combat_early() -> void:
	var arena: Node = auto_free(load(ARENA_SCENE).instantiate())
	add_child(arena)
	await await_idle_frame()
	await await_idle_frame()

	for panel_name: StringName in REQUIRED_PANELS:
		assert_object(arena.find_child(String(panel_name), true, false)).is_not_null()
	assert_bool(arena.get_node("GameUI/TitlePanel").visible).is_true()
	assert_bool(arena.get_node("GameUI/SelectionPanel").visible).is_false()

	arena.call("_on_title_panel_start_requested")
	assert_bool(arena.get_node("GameUI/TitlePanel").visible).is_false()
	assert_bool(arena.get_node("GameUI/SelectionPanel").visible).is_true()

	Global.select_character(Content.catalog.get_characters()[0])
	Global.select_starting_weapon(Content.catalog.get_weapons()[0])
	arena.call("_on_selection_panel_on_selection_completed")
	assert_bool(arena.get_node("GameUI/DifficultyPanel").visible).is_true()
	assert_bool(Global.current_run == null or Global.current_run.phase == RunPhase.SELECTION).is_true()


func test_settlement_can_return_to_title_and_leave_no_active_run() -> void:
	var arena: Node = auto_free(load(ARENA_SCENE).instantiate())
	add_child(arena)
	await await_idle_frame()
	await await_idle_frame()
	Global.begin_run(41, Content.catalog.get_characters()[0].stats, 12)
	Global.current_run.character_id = Content.catalog.get_characters()[0].get_stable_id(Content.catalog.pack_id)
	Global.current_run.wave = 4
	Global.current_run.difficulty = 2
	Global.current_run.elapsed_seconds = 42.0
	Global.enter_phase(RunPhase.COMBAT)

	arena.call("finish_run", false)
	var settlement: Control = arena.get_node("GameUI/SettlementPanel")
	assert_bool(settlement.visible).is_true()
	assert_str(str(settlement.get("result_key"))).is_equal("death")

	arena.call("reset_to_title")
	assert_object(Global.current_run).is_null()
	assert_bool(arena.get_node("GameUI/TitlePanel").visible).is_true()
