extends GdUnitTestSuite


func test_ecology_layout_is_deterministic_and_contains_trees_and_consumables() -> void:
	var first: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	var second: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	add_child(first)
	add_child(second)

	first.setup_wave(8, 404, null)
	second.setup_wave(8, 404, null)

	assert_array(first.tree_positions).is_equal(second.tree_positions)
	assert_int(first.tree_positions.size()).is_greater_equal(3)
	assert_int(first.pickup_kinds.size()).is_greater_equal(1)
	assert_bool(first.pickup_kinds.has(ArenaEcology.PickupKind.HEAL)).is_true()


func test_spawn_safe_zone_and_dynamic_danger_rules_are_explicit() -> void:
	var ecology: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	add_child(ecology)
	ecology.setup_wave(12, 909, null)

	assert_float(ecology.spawn_safe_radius).is_equal(280.0)
	assert_bool(ecology.is_spawn_position_safe(Vector2.ZERO)).is_false()
	assert_bool(ecology.is_spawn_position_safe(Vector2(700, 300))).is_true()
	assert_bool(ecology.danger_enabled).is_true()
	assert_float(ecology.danger_warning_seconds).is_greater(0.0)


func test_high_difficulty_mutator_makes_danger_zones_faster_and_larger() -> void:
	Global.begin_run(914, null, 0)
	Global.current_run.difficulty = 1
	var normal: ArenaEcology = auto_free(ArenaEcology.new())
	normal.setup_wave(12, 914, null)
	Global.current_run.difficulty = 4
	var pressured: ArenaEcology = auto_free(ArenaEcology.new())
	pressured.setup_wave(12, 914, null)

	assert_bool(pressured.effective_danger_interval < normal.effective_danger_interval).is_true()
	assert_bool(pressured.danger_radius > normal.danger_radius).is_true()
	Global.end_run()
