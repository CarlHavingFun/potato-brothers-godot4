extends GdUnitTestSuite


const BOSS_SCRIPT_PATH := "res://scenes/unit/enemy/boss/mouse_dog.gd"
const BOSS_SCENE_PATH := "res://scenes/unit/enemy/boss/mouse_dog.tscn"


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
	spawner.wave_index = 10

	assert_bool(spawner.complete_wave()).is_true()
	assert_int(Global.current_run.phase).is_equal(RunPhase.VICTORY)

	Global.begin_run(910, null, 0)
	Global.enter_phase(RunPhase.COMBAT)
	var arena: Arena = auto_free(Arena.new())
	arena._on_player_died()
	assert_int(Global.current_run.phase).is_equal(RunPhase.DEATH)
