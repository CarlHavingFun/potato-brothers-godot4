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


func test_difficulty_selection_can_only_create_one_player() -> void:
	var arena: Arena = auto_free(load(ARENA_SCENE).instantiate() as Arena)
	add_child(arena)
	await await_idle_frame()
	await await_idle_frame()
	Global.select_character(Content.catalog.get_characters()[0])
	Global.select_starting_weapon(Content.catalog.get_weapon(&"weapon/pistol"))
	arena._on_selection_panel_on_selection_completed()

	arena._on_difficulty_panel_difficulty_selected(1)
	var first_player := Global.player
	arena._on_difficulty_panel_difficulty_selected(1)

	assert_object(Global.player).is_same(first_player)
	assert_int(arena.find_children("*", "Player", true, false).size()).is_equal(1)
	assert_bool(arena.difficulty_panel.visible).is_false()
	arena.reset_to_title()


func test_death_retry_clears_old_selection_and_can_start_again() -> void:
	var arena: Arena = auto_free(load(ARENA_SCENE).instantiate() as Arena)
	add_child(arena)
	await await_idle_frame()
	await await_idle_frame()
	var selection := arena.selection_panel
	var character := Content.catalog.get_characters()[0]
	var weapon := Content.catalog.get_weapon(&"weapon/pistol")
	var player_card := selection.player_container.get_child(0) as SelectionCard
	var weapon_card := selection.weapon_container.get_child(0) as SelectionCard
	selection._on_player_selected(character, player_card)
	selection._on_weapon_selected(weapon, weapon_card)
	arena._on_selection_panel_on_selection_completed()
	arena._on_difficulty_panel_difficulty_selected(1)
	arena.finish_run(false)

	arena._on_settlement_panel_retry_requested()
	await await_idle_frame()
	await await_idle_frame()

	assert_bool(selection.visible).is_true()
	assert_bool(player_card.button_pressed).is_false()
	assert_bool(weapon_card.button_pressed).is_false()
	selection._on_player_selected(character, player_card)
	selection._on_weapon_selected(weapon, weapon_card)
	arena._on_selection_panel_on_selection_completed()
	arena._on_difficulty_panel_difficulty_selected(1)
	assert_object(Global.player).is_not_null()
	assert_int(arena.find_children("*", "Player", true, false).size()).is_equal(1)
	arena.reset_to_title()
