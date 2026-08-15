extends GdUnitTestSuite


const BOSS_SCRIPT_PATH := "res://scenes/unit/enemy/boss/mouse_dog.gd"
const BOSS_SCENE_PATH := "res://scenes/unit/enemy/boss/mouse_dog.tscn"
const TITAN_SCRIPT_PATH := "res://scenes/unit/enemy/boss/scrap_titan.gd"
const TITAN_SCENE_PATH := "res://scenes/unit/enemy/boss/scrap_titan.tscn"


func test_mouse_dog_has_a_dedicated_component_scene() -> void:
	assert_bool(ResourceLoader.exists(BOSS_SCRIPT_PATH)).is_true()
	assert_bool(ResourceLoader.exists(BOSS_SCENE_PATH)).is_true()
	if not ResourceLoader.exists(BOSS_SCENE_PATH):
		return
	var boss: Node = auto_free(load(BOSS_SCENE_PATH).instantiate())
	var definition := Content.catalog.get_enemy(&"enemy/mouse_dog")

	assert_str(boss.get_script().resource_path).is_equal(BOSS_SCRIPT_PATH)
	assert_object(definition).is_not_null()
	assert_str(definition.scene.resource_path).is_equal(BOSS_SCENE_PATH)


func test_mouse_dog_enrage_threshold_is_50_percent_except_difficulty_five() -> void:
	assert_bool(ResourceLoader.exists(BOSS_SCRIPT_PATH)).is_true()
	if not ResourceLoader.exists(BOSS_SCRIPT_PATH):
		return
	var script: Script = load(BOSS_SCRIPT_PATH)

	assert_bool(script.call("should_enrage", 50.0, 100.0, 1)).is_true()
	assert_bool(script.call("should_enrage", 51.0, 100.0, 1)).is_false()
	assert_bool(script.call("should_enrage", 65.0, 100.0, 5)).is_true()
	assert_bool(script.call("should_enrage", 66.0, 100.0, 5)).is_false()


func test_terminal_run_phases_are_entered_for_final_wave_and_player_death() -> void:
	Global.begin_run(909, null, 0)
	Global.enter_phase(RunPhase.COMBAT)
	var spawner: Spawner = auto_free(Spawner.new())
	spawner.wave_index = 20

	assert_bool(spawner.complete_wave()).is_true()
	assert_int(Global.current_run.phase).is_equal(RunPhase.VICTORY)

	Global.begin_run(910, null, 0)
	Global.enter_phase(RunPhase.COMBAT)
	var arena: Arena = auto_free(Arena.new())
	arena._on_player_died()
	assert_int(Global.current_run.phase).is_equal(RunPhase.DEATH)


func test_endless_wave_twenty_records_standard_win_once_and_continues() -> void:
	Global.meta_progress = MetaProgress.new()
	Global.begin_run(911, null, 0)
	Global.current_run.character_id = &"core:character/brawler"
	Global.current_run.starting_weapon_id = &"core:weapon/punch"
	Global.current_run.difficulty = 1
	Global.current_run.run_mode = RunMode.ENDLESS
	Global.enter_phase(RunPhase.COMBAT)
	var spawner: Spawner = auto_free(Spawner.new())
	spawner.wave_index = 20

	assert_bool(spawner.complete_boss_victory()).is_false()
	assert_int(Global.current_run.phase).is_equal(RunPhase.COMBAT)
	assert_bool(spawner.complete_wave()).is_true()
	assert_int(Global.current_run.phase).is_equal(RunPhase.UPGRADE)
	assert_bool(Global.current_run.standard_victory_recorded).is_true()
	assert_int(Global.meta_progress.highest_clear_for(Global.current_run.character_id)).is_equal(1)
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(2)
	assert_bool(bool(Global.call("record_standard_victory_once"))).is_false()
	assert_int(Global.meta_progress.highest_unlocked_difficulty).is_equal(2)


func test_both_final_boss_definitions_are_recognized_for_immediate_victory() -> void:
	var arena_script: Script = load("res://scenes/arena/arena.gd")
	for boss_id: StringName in [&"enemy/mouse_dog", &"enemy/scrap_titan"]:
		var definition := Content.catalog.get_enemy(boss_id)
		assert_object(definition).is_not_null()
		if definition == null:
			continue
		var enemy: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
		enemy.definition = definition
		assert_bool(bool(arena_script.call("is_final_boss_enemy", enemy))).is_true()


func test_scrap_titan_has_an_independent_scene_script_and_phase_rules() -> void:
	assert_bool(ResourceLoader.exists(TITAN_SCRIPT_PATH)).is_true()
	assert_bool(ResourceLoader.exists(TITAN_SCENE_PATH)).is_true()
	if not ResourceLoader.exists(TITAN_SCENE_PATH):
		return
	var titan: Node = auto_free(load(TITAN_SCENE_PATH).instantiate())
	var definition := Content.catalog.get_enemy(&"enemy/scrap_titan")

	assert_str(titan.get_script().resource_path).is_equal(TITAN_SCRIPT_PATH)
	assert_str(titan.get_script().resource_path).is_not_equal(BOSS_SCRIPT_PATH)
	assert_object(definition).is_not_null()
	assert_str(definition.scene.resource_path).is_equal(TITAN_SCENE_PATH)
	assert_bool(bool(titan.get_script().call("should_enter_overdrive", 40.0, 100.0, 4))).is_false()
	assert_bool(bool(titan.get_script().call("should_enter_overdrive", 40.0, 100.0, 5))).is_true()
	assert_int(int(titan.get_script().call("burst_projectile_count", 1, false))).is_equal(8)
	assert_int(int(titan.get_script().call("burst_projectile_count", 5, true))).is_equal(16)
