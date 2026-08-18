extends GdUnitTestSuite


const WAVE_DIRECTOR_PATH := "res://core/directors/wave_director.gd"
const WAVE_RULES := preload("res://core/directors/core_wave_rules.gd")


func test_wave_enemy_selection_is_reproducible_for_the_same_run_seed() -> void:
	assert_bool(ResourceLoader.exists(WAVE_DIRECTOR_PATH)).is_true()
	if not ResourceLoader.exists(WAVE_DIRECTOR_PATH):
		return
	var script: Script = load(WAVE_DIRECTOR_PATH)
	var first: RefCounted = script.new(Content.catalog, 405)
	var second: RefCounted = script.new(Content.catalog, 405)
	var wave := Content.catalog.get_wave(&"wave/9")
	var first_ids: Array[StringName] = []
	var second_ids: Array[StringName] = []
	for index in 20:
		first_ids.append(first.call("select_enemy_id", wave, false))
		second_ids.append(second.call("select_enemy_id", wave, false))

	assert_array(first_ids).is_equal(second_ids)


func test_lowest_difficulty_has_no_special_event_before_final_boss() -> void:
	var director := WaveDirector.new(Content.catalog, 405)
	var wave := Content.catalog.get_wave(&"wave/10")
	assert_str(director.encounter_kind(10, 1)).is_equal("standard")
	assert_str(director.encounter_kind(15, 1)).is_equal("standard")
	assert_int(director.priority_spawn_limit(wave, 1)).is_zero()
	assert_bool(director.is_final_wave(wave.wave_number)).is_false()


func test_wave_20_chooses_one_of_two_final_bosses_deterministically() -> void:
	var wave := Content.catalog.get_wave(&"wave/20")
	var first := WaveDirector.new(Content.catalog, 771)
	var second := WaveDirector.new(Content.catalog, 771)
	var first_id := first.select_enemy_id(wave, false)

	assert_bool(["enemy/mouse_dog", "enemy/scrap_titan"].has(String(first_id))).is_true()
	assert_str(second.select_enemy_id(wave, false)).is_equal(String(first_id))
	assert_str(first.select_enemy_id(wave, true)).is_not_equal(String(first_id))
	assert_bool(first.is_final_wave(20)).is_true()
	assert_bool(first.is_final_wave(19)).is_false()
	var observed: Dictionary = {}
	for seed_value: int in range(64):
		var seeded := WaveDirector.new(Content.catalog, seed_value)
		observed[String(seeded.select_enemy_id(wave, false))] = true
	assert_bool(observed.has("enemy/mouse_dog")).is_true()
	assert_bool(observed.has("enemy/scrap_titan")).is_true()


func test_difficulty_driven_encounter_schedule_is_deterministic() -> void:
	var first := WaveDirector.new(Content.catalog, 9071)
	var second := WaveDirector.new(Content.catalog, 9071)
	var first_schedule := first.encounter_schedule(4)
	var second_schedule := second.encounter_schedule(4)

	assert_dict(first_schedule).is_equal(second_schedule)
	var special_waves := first.encounter_waves(&"elite", 4)
	special_waves.append_array(first.encounter_waves(&"horde", 4))
	special_waves.sort()
	assert_int(special_waves.size()).is_equal(3)
	for window_index in WAVE_RULES.SPECIAL_EVENT_WINDOWS.size():
		var event_wave := special_waves[window_index]
		var window: Vector2i = WAVE_RULES.SPECIAL_EVENT_WINDOWS[window_index]
		assert_bool(event_wave >= window.x and event_wave <= window.y).is_true()
	assert_bool(first.encounter_waves(&"elite", 4).has(special_waves[2])).is_true()


func test_middle_difficulties_have_one_special_event_in_first_window() -> void:
	for level in [2, 3]:
		var director := WaveDirector.new(Content.catalog, 1122 + level)
		var special_waves := director.encounter_waves(&"elite", level)
		special_waves.append_array(director.encounter_waves(&"horde", level))
		assert_int(special_waves.size()).is_equal(1)
		assert_bool(special_waves[0] in [11, 12]).is_true()


func test_difficulty_five_spawns_both_final_bosses_once() -> void:
	var director := WaveDirector.new(Content.catalog, 771)
	var wave := Content.catalog.get_wave(&"wave/20")

	assert_int(director.priority_spawn_limit(wave, 1)).is_equal(1)
	assert_int(director.priority_spawn_limit(wave, 5)).is_equal(2)
	var first_id := director.select_enemy_id(wave, 0, 5)
	var second_id := director.select_enemy_id(wave, 1, 5)

	assert_bool(["enemy/mouse_dog", "enemy/scrap_titan"].has(String(first_id))).is_true()
	assert_bool(["enemy/mouse_dog", "enemy/scrap_titan"].has(String(second_id))).is_true()
	assert_str(second_id).is_not_equal(String(first_id))
