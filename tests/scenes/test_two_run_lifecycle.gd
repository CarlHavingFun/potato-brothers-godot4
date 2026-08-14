extends GdUnitTestSuite


const ARENA_SCENE := "res://scenes/arena/arena.tscn"


func test_two_runs_reuse_one_arena_without_duplicate_global_signals_or_live_run_state() -> void:
	var arena: Node = load(ARENA_SCENE).instantiate()
	var arena_id := arena.get_instance_id()
	add_child(arena)
	await await_idle_frame()
	await await_idle_frame()
	for signal_name: StringName in [&"on_create_block_text", &"on_create_damage_text", &"on_upgrade_selected", &"on_create_heal_text", &"on_enemy_died"]:
		assert_int(_connections_to(Global.get(signal_name), arena_id)).override_failure_message(signal_name).is_equal(1)

	for run_index: int in range(2):
		Global.begin_run(900 + run_index, Content.catalog.get_characters()[run_index].stats, 12)
		Global.current_run.character_id = Content.catalog.get_characters()[run_index].get_stable_id(Content.catalog.pack_id)
		Global.enter_phase(RunPhase.COMBAT)
		arena.call("finish_run", run_index == 1)
		assert_bool(arena.get_node("GameUI/SettlementPanel").visible).is_true()
		arena.call("reset_to_title")
		await await_idle_frame()
		assert_object(Global.current_run).is_null()
		assert_bool(arena.get_node("GameUI/TitlePanel").visible).is_true()
		assert_int(arena.get_node("Spawner").get("spawned_enemies").size()).is_equal(0)

	arena.queue_free()
	await await_idle_frame()
	await await_idle_frame()
	for signal_name: StringName in [&"on_create_block_text", &"on_create_damage_text", &"on_upgrade_selected", &"on_create_heal_text", &"on_enemy_died"]:
		assert_int(_connections_to(Global.get(signal_name), arena_id)).override_failure_message(signal_name).is_equal(0)


func _connections_to(signal_value: Signal, target_id: int) -> int:
	var count := 0
	for connection: Dictionary in signal_value.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.is_valid() and callable.get_object_id() == target_id:
			count += 1
	return count
