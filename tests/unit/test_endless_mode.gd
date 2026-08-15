extends GdUnitTestSuite


const RUN_MODE_PATH := "res://core/types/run_mode.gd"
const SCALING_PATH := "res://core/endless/endless_scaling_def.gd"
const GENERATOR_PATH := "res://core/endless/endless_wave_generator.gd"


func test_run_mode_is_preserved_from_selection_to_checkpoint() -> void:
	assert_bool(ResourceLoader.exists(RUN_MODE_PATH)).is_true()
	if not ResourceLoader.exists(RUN_MODE_PATH):
		return
	var run_mode_script: Script = load(RUN_MODE_PATH)
	var endless := 1
	assert_bool(bool(run_mode_script.call("is_valid", endless))).is_true()
	var draft := SelectionDraft.new()
	draft.profile_id = 2
	draft.character_id = &"core:character/brawler"
	draft.weapon_id = &"core:weapon/punch"
	draft.difficulty = 3
	draft.set("run_mode", endless)
	var restored_draft := SelectionDraft.from_dict(draft.to_dict())
	var request := RunLaunchRequest.from_draft(restored_draft)

	assert_int(int(restored_draft.get("run_mode"))).is_equal(endless)
	assert_int(int(request.get("run_mode"))).is_equal(endless)
	var run := RunState.new(91)
	run.set("run_mode", endless)
	run.set("standard_victory_recorded", true)
	run.set("endless_cycle", 7)
	run.set("highest_wave_reached", 54)
	run.set("kill_count", 1200)
	run.set("boss_kill_count", 8)
	var restored_run := RunState.from_dict(run.to_dict())
	assert_int(int(restored_run.get("run_mode"))).is_equal(endless)
	assert_bool(bool(restored_run.get("standard_victory_recorded"))).is_true()
	assert_int(int(restored_run.get("endless_cycle"))).is_equal(7)
	assert_int(int(restored_run.get("highest_wave_reached"))).is_equal(54)
	assert_int(int(restored_run.get("kill_count"))).is_equal(1200)
	assert_int(int(restored_run.get("boss_kill_count"))).is_equal(8)


func test_endless_scaling_uses_configured_growth_and_caps() -> void:
	assert_bool(ResourceLoader.exists(SCALING_PATH)).is_true()
	if not ResourceLoader.exists(SCALING_PATH):
		return
	var scaling: Resource = load(SCALING_PATH).new()

	assert_float(float(scaling.call("health_multiplier", 21))).is_equal_approx(1.12, 0.0001)
	assert_float(float(scaling.call("damage_multiplier", 21))).is_equal_approx(1.055, 0.0001)
	assert_float(float(scaling.call("density_multiplier", 21))).is_equal_approx(1.04, 0.0001)
	assert_float(float(scaling.call("material_drop_multiplier", 21))).is_equal_approx(0.98, 0.0001)
	assert_float(float(scaling.call("shop_price_multiplier", 21))).is_equal_approx(1.06, 0.0001)
	assert_float(float(scaling.call("density_multiplier", 100))).is_equal_approx(2.4, 0.0001)
	assert_float(float(scaling.call("speed_multiplier", 100))).is_equal_approx(1.25, 0.0001)
	assert_float(float(scaling.call("material_drop_multiplier", 100))).is_equal_approx(0.25, 0.0001)


func test_endless_generator_builds_deterministic_five_wave_cycles() -> void:
	assert_bool(ResourceLoader.exists(GENERATOR_PATH)).is_true()
	if not ResourceLoader.exists(GENERATOR_PATH):
		return
	var generator: RefCounted = load(GENERATOR_PATH).new(Content.catalog, 44017)
	var same_seed: RefCounted = load(GENERATOR_PATH).new(Content.catalog, 44017)
	var wave_21: WaveDef = generator.call("generate", 21, 3)
	var wave_24: WaveDef = generator.call("generate", 24, 3)
	var wave_25: WaveDef = generator.call("generate", 25, 3)
	var wave_30: WaveDef = generator.call("generate", 30, 3)
	var wave_50: WaveDef = generator.call("generate", 50, 5)

	assert_float(wave_21.duration).is_equal(60.0)
	assert_int(int(wave_21.get("endless_cycle"))).is_equal(1)
	assert_array(wave_21.tags).contains([&"endless", &"mixed"])
	assert_array(wave_24.tags).contains([&"high_pressure"])
	assert_array(wave_25.tags).contains([&"elite_wave"])
	assert_int(wave_25.spawns.filter(func(spawn: WaveSpawnDef): return spawn.is_elite).size()).is_equal(1)
	assert_array(wave_30.tags).contains([&"boss_wave"])
	assert_int(wave_30.spawns.filter(func(spawn: WaveSpawnDef): return spawn.is_boss).size()).is_equal(1)
	assert_int(wave_50.spawns.filter(func(spawn: WaveSpawnDef): return spawn.is_boss).size()).is_equal(2)
	assert_int(int(wave_50.get("priority_spawn_count"))).is_equal(2)
	assert_array(_spawn_ids(wave_30)).is_equal(_spawn_ids(same_seed.call("generate", 30, 3)))


func test_meta_progress_records_highest_endless_wave_per_character_and_difficulty() -> void:
	var progress := MetaProgress.new()
	assert_bool(bool(progress.call("record_endless_wave", &"core:character/brawler", 3, 47))).is_true()
	assert_bool(bool(progress.call("record_endless_wave", &"core:character/brawler", 3, 40))).is_false()
	assert_bool(bool(progress.call("record_endless_wave", &"core:character/brawler", 4, 31))).is_true()
	var restored := MetaProgress.from_dict(progress.to_dict())

	assert_int(int(restored.call("highest_endless_wave_for", &"core:character/brawler", 3))).is_equal(47)
	assert_int(int(restored.call("highest_endless_wave_for", &"core:character/brawler", 4))).is_equal(31)
	assert_int(int(restored.call("highest_endless_wave_for", &"core:character/brawler", 2))).is_zero()


func test_endless_mode_does_not_make_wave_twenty_terminal() -> void:
	var director := WaveDirector.new(Content.catalog, 100)
	assert_bool(director.is_final_wave(20)).is_true()
	assert_bool(bool(director.call("is_final_wave", 20, RunMode.ENDLESS))).is_false()
	assert_bool(bool(director.call("is_final_wave", 100, RunMode.ENDLESS))).is_false()


func test_endless_scaling_is_consumed_by_enemy_stats_and_shop_prices() -> void:
	var base := UnitStats.new()
	base.health = 100
	base.health_increase_per_wave = 0
	base.damage = 20.0
	base.damage_increase_per_wave = 0.0
	base.speed = 100
	base.gold_drop = 100
	var scaling := EndlessScalingDef.new()
	var spawner: Spawner = auto_free(Spawner.new())
	var scaled: UnitStats = spawner.call(
		"build_enemy_stats_for_wave", base, 21, 1, [] as Array[StringName], scaling
	)

	assert_int(scaled.health).is_equal(112)
	assert_float(scaled.damage).is_equal_approx(21.1, 0.001)
	assert_int(scaled.speed).is_equal(101)
	assert_int(scaled.gold_drop).is_equal(98)
	var service := ShopService.new(12)
	var standard := RunState.new(12)
	standard.wave = 21
	var endless := RunState.new(12)
	endless.wave = 21
	endless.run_mode = RunMode.ENDLESS
	assert_int(service.refresh_price_for_run(endless, 21)).is_greater(
		service.refresh_price_for_run(standard, 21)
	)


func test_wave_fifty_emits_two_distinct_priority_bosses_before_regular_enemies() -> void:
	var wave := EndlessWaveGenerator.new(Content.catalog, 707).generate(50, 5)
	var director := WaveDirector.new(Content.catalog, 707)
	var first := StringName(director.call("select_enemy_id", wave, 0))
	var second := StringName(director.call("select_enemy_id", wave, 1))
	var third := StringName(director.call("select_enemy_id", wave, 2))

	assert_bool(Content.catalog.get_enemy(first).tags.has(&"boss")).is_true()
	assert_bool(Content.catalog.get_enemy(second).tags.has(&"boss")).is_true()
	assert_str(first).is_not_equal(String(second))
	assert_bool(Content.catalog.get_enemy(third).tags.has(&"boss")).is_false()


func _spawn_ids(wave: WaveDef) -> Array[String]:
	var result: Array[String] = []
	for spawn: WaveSpawnDef in wave.spawns:
		result.append(String(spawn.enemy_id))
	return result
