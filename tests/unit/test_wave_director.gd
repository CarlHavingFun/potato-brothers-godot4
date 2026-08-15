extends GdUnitTestSuite


const WAVE_DIRECTOR_PATH := "res://core/directors/wave_director.gd"


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


func test_elite_waves_use_two_distinct_priority_enemies() -> void:
	var director := WaveDirector.new(Content.catalog, 405)
	var wave := Content.catalog.get_wave(&"wave/10")

	var first_id := director.select_enemy_id(wave, false)
	var second_id := director.select_enemy_id(wave, true)

	assert_str(first_id).is_equal("enemy/iron_maw")
	assert_str(second_id).is_not_equal("enemy/iron_maw")
	assert_str(director.select_enemy_id(Content.catalog.get_wave(&"wave/15"), false)).is_equal(
		"enemy/volt_stalker"
	)
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
