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
