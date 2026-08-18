extends GdUnitTestSuite


func test_arena_exposes_persistent_player_vitals_and_material_bag_labels() -> void:
	var scene_text := FileAccess.get_file_as_string("res://scenes/arena/arena.tscn")
	for node_name: String in ["HealthHudLabel", "ExperienceHudLabel", "MaterialBagLabel"]:
		assert_str(scene_text).contains(node_name)

const RUN_HUD_FORMATTER := preload("res://core/presentation/run_hud_formatter.gd")


func test_encounter_preview_prioritizes_boss_then_elite_then_horde() -> void:
	var standard := WaveDef.new()
	var normal_spawn := WaveSpawnDef.new()
	standard.spawns = [normal_spawn]
	assert_str(RUN_HUD_FORMATTER.encounter_key(standard)).is_equal("ui.hud.encounter.standard")

	standard.tags = [&"horde_wave"]
	assert_str(RUN_HUD_FORMATTER.encounter_key(standard)).is_equal("ui.hud.encounter.horde")

	var elite := WaveSpawnDef.new()
	elite.is_elite = true
	standard.spawns.append(elite)
	assert_str(RUN_HUD_FORMATTER.encounter_key(standard)).is_equal("ui.hud.encounter.elite")

	var boss := WaveSpawnDef.new()
	boss.is_boss = true
	standard.spawns.append(boss)
	assert_str(RUN_HUD_FORMATTER.encounter_key(standard)).is_equal("ui.hud.encounter.boss")


func test_status_entries_are_stable_and_preserve_stack_and_duration() -> void:
	var entries := RUN_HUD_FORMATTER.status_entries({
		&"slow": {"stacks": 1, "remaining": 0.5},
		&"burn": {"stacks": 3, "remaining": 2.25},
	})

	assert_int(entries.size()).is_equal(2)
	assert_str(str(entries[0].status_id)).is_equal("burn")
	assert_int(int(entries[0].stacks)).is_equal(3)
	assert_float(float(entries[0].remaining)).is_equal(2.25)


func test_boss_snapshot_ignores_freed_instances_before_type_checks() -> void:
	var freed_enemy := Enemy.new()
	var candidates: Array = [freed_enemy]
	freed_enemy.free()

	var snapshot: Dictionary
	for _frame: int in range(10_000):
		snapshot = RUN_HUD_FORMATTER.boss_snapshot(candidates)

	assert_dict(snapshot).is_empty()
