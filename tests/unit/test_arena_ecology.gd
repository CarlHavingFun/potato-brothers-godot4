extends GdUnitTestSuite


func after_test() -> void:
	Global.end_run()


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
	assert_array(_tree_drop_kinds(first)).is_equal(_tree_drop_kinds(second))
	assert_array(_tree_presentation_ids(first)).contains_exactly(
		_tree_presentation_ids(second)
	)
	assert_bool(_tree_presentation_ids(first).has(&"prop.supply_crate")).is_true()
	assert_bool(_tree_presentation_ids(first).has(&"prop.weapon_rack")).is_true()


func test_prop_art_selection_is_stable_and_does_not_consume_ecology_rng() -> void:
	var ecology: ArenaEcology = auto_free(ArenaEcology.new())
	ecology._rng.seed = 918273
	var state_before := ecology._rng.state

	assert_str(String(ecology._prop_presentation_id(0))).is_equal("prop.supply_crate")
	assert_str(String(ecology._prop_presentation_id(1))).is_equal("prop.weapon_rack")
	assert_str(String(ecology._prop_presentation_id(2))).is_equal("prop.supply_crate")
	assert_int(ecology._rng.state).is_equal(state_before)


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


func test_danger_zone_uses_the_typed_player_damage_pipeline() -> void:
	Global.begin_run(915, null, 0)
	Global.current_run.phase = RunPhase.COMBAT
	Global.current_run.player_stats.set_stat(StatId.ARMOR, 15.0)
	Global.current_run.player_stats.set_stat(StatId.DODGE, 0.0)
	var player: Player = auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	var ecology: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	add_child(ecology)
	ecology.setup_wave(6, 915, player)
	ecology.danger_center = player.global_position
	ecology._danger_cycle = 0
	ecology._elapsed = ecology.danger_warning_seconds + 0.01
	var health_before := player.health_component.current_health
	var raw_damage := 3.0 + 6.0 * 0.35

	ecology._process(0.0)

	assert_float(player.health_component.current_health).is_equal_approx(
		health_before - Global.combat_resolver.damage_after_armor(raw_damage, 15.0),
		0.001
	)


func test_tree_harvest_defers_pickup_creation_until_physics_flush_is_safe() -> void:
	var ecology: ArenaEcology = auto_free(ArenaEcology.new())
	add_child(ecology)
	var child_count := ecology.get_child_count()

	ecology._on_tree_harvested(Vector2(40.0, 20.0), ArenaEcology.PickupKind.HEAL)

	assert_int(ecology.get_child_count()).is_equal(child_count)
	await await_idle_frame()
	assert_int(ecology.get_child_count()).is_equal(child_count + 1)
	assert_object(ecology.get_child(child_count)).is_instanceof(EcologyPickup)


func test_fifth_wave_no_longer_grants_an_unconditional_chest() -> void:
	var ecology: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	add_child(ecology)

	ecology.setup_wave(5, 1007, null)

	assert_array(ecology.pickup_kinds).contains_exactly([ArenaEcology.PickupKind.HEAL])


func test_enemy_drop_entrypoint_spawns_the_rolled_world_pickup_safely() -> void:
	var ecology: ArenaEcology = auto_free(ArenaEcology.new()) as ArenaEcology
	add_child(ecology)
	var child_count := ecology.get_child_count()

	assert_bool(ecology.spawn_world_drop(Vector2(24.0, 18.0), ArenaEcology.PickupKind.MATERIAL)).is_true()
	assert_int(ecology.get_child_count()).is_equal(child_count)
	await await_idle_frame()
	assert_int(ecology.get_child_count()).is_equal(child_count + 1)
	assert_object(ecology.get_child(child_count)).is_instanceof(EcologyPickup)


func _tree_drop_kinds(ecology: ArenaEcology) -> Array[int]:
	var result: Array[int] = []
	for child: Node in ecology.get_children():
		if child is EcologyTree:
			result.append((child as EcologyTree).pickup_kind)
	return result


func _tree_presentation_ids(ecology: ArenaEcology) -> Array[StringName]:
	var result: Array[StringName] = []
	for child: Node in ecology.get_children():
		if child is EcologyTree:
			result.append((child as EcologyTree).presentation_id)
	return result
