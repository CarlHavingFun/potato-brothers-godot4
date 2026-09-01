extends GdUnitTestSuite


func test_new_normal_session_has_twenty_effective_waves() -> void:
	var session := _session()
	assert_int(session.run_state.total_waves).is_equal(20)
	var zone := session.content_snapshot.definition(ValidationContentFactory.ZONE_ID, &"zone") as GogoZoneDefinition
	assert_int(zone.wave_ids.size()).is_equal(20)
	for number in [6, 20]:
		var wave := session.content_snapshot.definition(StringName("gogobro.core:wave/training_%d" % number), &"wave") as GogoWaveDefinition
		assert_object(wave).is_not_null()
		if wave != null:
			assert_int(wave.wave_number).is_equal(number)
			assert_bool(wave.spawn_groups.is_empty()).is_false()


func test_continue_is_shop_only_and_commits_before_reentrant_publication() -> void:
	var session := _session()
	assert_bool(session.continue_after_shop()).is_false()
	assert_int(session.run_state.current_wave).is_equal(1)
	assert_int(session.transition(&"shop")).is_equal(OK)
	var callbacks := [0]
	var listener := func(_old: StringName, next: StringName) -> void:
		if next == &"combat" and callbacks[0] == 0:
			callbacks[0] += 1
			session.continue_after_shop()
	session.phase_changed.connect(listener)
	assert_bool(session.continue_after_shop()).is_true()
	assert_int(callbacks[0]).is_equal(1)
	assert_int(session.run_state.current_wave).is_equal(2)
	assert_bool(session.continue_after_shop()).is_false()
	session.phase_changed.disconnect(listener)


func test_failure_is_exact_once_even_in_state_and_terminal_callbacks() -> void:
	var session := _session()
	var callbacks := [0, 0]
	var state_listener := func() -> void:
		if callbacks[0] == 0:
			callbacks[0] += 1
			session.fail_run()
	var terminal_listener := func(_victory: bool) -> void:
		callbacks[1] += 1
		if callbacks[1] == 1:
			session.fail_run()
	session.state_changed.connect(state_listener)
	session.run_ended.connect(terminal_listener)
	session.fail_run()
	session.fail_run()
	assert_int(callbacks[0]).is_equal(1)
	assert_int(callbacks[1]).is_equal(1)
	assert_bool(session.continue_after_shop()).is_false()
	assert_int(session.run_state.current_wave).is_equal(1)
	assert_bool(session.run_state.won).is_false()
	assert_str(session.run_state.phase).is_equal("settlement")
	session.state_changed.disconnect(state_listener)
	session.run_ended.disconnect(terminal_listener)


func test_fixed_wave_rewards_commit_once_under_reward_phase_and_state_reentry() -> void:
	var session := _session()
	var counts := [0, 0, 0]
	var reward_listener := func(_token: StringName, _kind: StringName, _amount: int, _player: int) -> void:
		counts[0] += 1
		if counts[0] < 4:
			session.finish_wave()
	var phase_listener := func(_old: StringName, _next: StringName) -> void:
		counts[1] += 1
		session.finish_wave()
	var state_listener := func() -> void:
		counts[2] += 1
		session.finish_wave()
	session.reward_committed.connect(reward_listener)
	session.phase_changed.connect(phase_listener)
	session.state_changed.connect(state_listener)
	session.finish_wave()
	session.finish_wave()
	assert_int(session.run_state.player().xp).is_equal(10)
	assert_int(session.run_state.player().materials).is_equal(28)
	assert_array(counts).is_equal([2, 1, 1])
	session.reward_committed.disconnect(reward_listener)
	session.phase_changed.disconnect(phase_listener)
	session.state_changed.disconnect(state_listener)


func test_start_rejects_empty_or_invalid_authored_zone() -> void:
	for defect in ["empty", "missing", "wrong_number", "unknown_enemy"]:
		var packs := ValidationContentFactory.create_packs()
		for definition in packs[0].definitions:
			if definition is GogoZoneDefinition:
				if defect == "empty":
					definition.wave_ids.clear()
				if defect == "missing":
					definition.wave_ids[0] = &"absent:wave/one"
			if definition is GogoWaveDefinition and definition.wave_number == 1:
				if defect == "wrong_number":
					definition.wave_number = 0
				if defect == "unknown_enemy":
					definition.spawn_groups[0]["enemy_id"] = &"absent:enemy/one"
		var session := GameSession.new()
		assert_int(session.start(_config(), GogoContentRegistry.new().build_snapshot(packs))).is_not_equal(OK)
		assert_object(session.run_state).is_null()


func test_final_shop_requires_explicit_choice_and_preserves_loss() -> void:
	var session := _session()
	session.run_state.current_wave = 20
	assert_int(session.transition(&"shop")).is_equal(OK)
	assert_bool(session.continue_after_shop()).is_false()
	assert_bool(session.run_state.ended).is_false()
	assert_int(session.run_state.current_wave).is_equal(20)
	assert_bool(session.has_method("finish_normal_run")).is_true()
	assert_bool(session.has_method("continue_endless")).is_true()
	if session.has_method("finish_normal_run"):
		session.fail_run()
		assert_bool(session.call("finish_normal_run")).is_false()
		assert_bool(session.call("continue_endless")).is_false()
		assert_bool(session.run_state.won).is_false()


func test_ended_combat_never_grants_fixed_rewards() -> void:
	var session := _session()
	var player := session.run_state.player()
	var materials := player.materials
	session.run_state.ended = true
	session.finish_wave()
	session.finish_wave()
	assert_int(player.materials).is_equal(materials)
	assert_int(player.xp).is_equal(0)


func test_run_state_advance_refuses_invalid_phase_and_pending_upgrades() -> void:
	var state := GogoRunState.new()
	assert_bool(state.advance_wave()).is_false()
	assert_int(state.current_wave).is_equal(1)
	state.phase = &"shop"
	state.pending_upgrade_count = 1
	assert_bool(state.advance_wave()).is_false()
	assert_int(state.current_wave).is_equal(1)


func test_terminal_choices_latch_before_all_synchronous_callbacks() -> void:
	for choice in ["finish_normal_run", "continue_endless"]:
		var session := _session()
		session.run_state.current_wave = 20
		session.transition(&"shop")
		var counts := [0, 0, 0]
		var phase_listener := func(_old: StringName, _next: StringName) -> void:
			counts[0] += 1
			session.call(choice)
			session.continue_after_shop()
			session.fail_run()
		var state_listener := func() -> void:
			counts[1] += 1
			session.call(choice)
		var terminal_listener := func(_won: bool) -> void:
			counts[2] += 1
			session.call(choice)
			session.fail_run()
		session.phase_changed.connect(phase_listener)
		session.state_changed.connect(state_listener)
		session.run_ended.connect(terminal_listener)
		assert_bool(session.call(choice)).is_true()
		assert_bool(session.call(choice)).is_false()
		assert_int(counts[0]).is_equal(1)
		assert_int(counts[1]).is_equal(1)
		assert_int(counts[2]).is_equal(1 if choice == "finish_normal_run" else 0)
		assert_int(session.run_state.current_wave).is_equal(20 if choice == "finish_normal_run" else 21)
		assert_bool(session.run_state.won).is_equal(choice == "finish_normal_run")
		session.phase_changed.disconnect(phase_listener)
		session.state_changed.disconnect(state_listener)
		session.run_ended.disconnect(terminal_listener)


func test_world_rejects_bad_definitions_before_mutating_live_references() -> void:
	var session := _session()
	for defect in ["duration", "empty", "enemy", "schedule", "number"]:
		var world := auto_free(CombatWorld.new()) as CombatWorld
		add_child(world)
		var wave := GogoWaveResolver.resolve(session)
		match defect:
			"duration": wave.duration_seconds = NAN
			"empty": wave.spawn_groups.clear()
			"enemy": wave.spawn_groups[0]["enemy_id"] = &"missing:enemy/test"
			"schedule": wave.spawn_groups[0]["end"] = 9000.0
			"number": wave.wave_number = 21
		assert_int(world.start_wave(session, wave)).is_equal(ERR_INVALID_DATA)
		assert_object(world.session).is_null()
		assert_object(world.player_actor).is_null()
		assert_bool(world.running).is_false()


func test_all_twenty_authored_waves_are_valid_and_snapshots_stay_immutable() -> void:
	var session := _session()
	var expected_counts := [28, 44, 68, 85, 105, 117, 126, 138, 147, 159, 170, 182, 191, 205, 214, 228, 237, 251, 266, 280]
	for number in range(1, 21):
		session.run_state.current_wave = number
		var wave := GogoWaveResolver.resolve(session)
		assert_object(wave).is_not_null()
		if wave == null:
			continue
		assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, number)).is_equal(OK)
		var total := 0
		for group in wave.spawn_groups:
			total += int(group["count"])
		assert_int(total).is_equal(expected_counts[number - 1])
		wave.spawn_groups.clear()
		assert_bool(GogoWaveResolver.resolve(session).spawn_groups.is_empty()).is_false()


func test_resolver_rejects_invalid_or_unchosen_endless_state() -> void:
	var session := _session()
	for number in [-1, 0, 21]:
		session.run_state.current_wave = number
		assert_object(GogoWaveResolver.resolve(session)).is_null()
	session.run_state.current_wave = 1
	session.run_state.zone_id = &"missing:zone/test"
	assert_object(GogoWaveResolver.resolve(session)).is_null()
	session.run_state.zone_id = ValidationContentFactory.ZONE_ID
	session.run_state.total_waves = 19
	assert_object(GogoWaveResolver.resolve(session)).is_null()
	session.run_state.total_waves = 20
	session.fail_run()
	assert_object(GogoWaveResolver.resolve(session)).is_null()


func test_endless_curve_is_legal_and_bounded_even_at_maximum_integer() -> void:
	var session := _session()
	session.run_state.current_wave = 20
	session.transition(&"shop")
	session.continue_endless()
	for spec in [[21, 292, 2.65, 1.80, 1.16], [22, 304, 2.80, 1.85, 1.17], [25, 340, 3.25, 2.00, 1.20], [9223372036854775807, 480, 32.5, 11.75, 1.50]]:
		session.run_state.current_wave = spec[0]
		var wave := GogoWaveResolver.resolve(session)
		assert_object(wave).is_not_null()
		if wave == null:
			continue
		assert_int(wave.spawn_groups.size()).is_equal(4)
		assert_float(wave.duration_seconds).is_equal(60.0)
		assert_float(wave.enemy_health_multiplier).is_equal_approx(spec[2], 0.00001)
		assert_float(wave.enemy_damage_multiplier).is_equal_approx(spec[3], 0.00001)
		assert_float(wave.enemy_speed_multiplier).is_equal_approx(spec[4], 0.00001)
		var runtime := WaveRuntime.new()
		runtime.begin(wave, 1.0)
		assert_int(runtime.schedules.size()).is_equal(4)
		assert_int(runtime.tick(60.0).size()).is_equal(spec[1])
	assert_object(EndlessWaveFactory.new().build(21, [])).is_null()
	assert_object(EndlessWaveFactory.new().build(0, [&"gogobro.core:enemy/drifter"])).is_null()
	var unknown := EndlessWaveFactory.new().build(21, [&"missing:enemy/test"])
	assert_int(GogoWaveResolver.validate_wave(unknown, session.content_snapshot, 21)).is_equal(ERR_INVALID_DATA)


func test_optional_endless_and_shop_state_round_trip_and_legacy_defaults() -> void:
	var session := _session()
	var legacy_payload := session.run_state.to_dictionary()
	legacy_payload.schema_version = 1
	legacy_payload.total_waves = 5
	legacy_payload.players[0].erase("weapons")
	legacy_payload.players[0].erase("next_weapon_instance_id")
	legacy_payload.players[0].weapon_ids = [String(ValidationContentFactory.RANGED_ID)]
	legacy_payload.erase("endless")
	var legacy := GogoRunState.from_dictionary(legacy_payload, session.content_snapshot)
	assert_bool(legacy.endless).is_false()
	assert_bool(legacy.ended).is_false()
	assert_bool(legacy.won).is_false()
	assert_int(legacy.total_waves).is_equal(5)
	var state := _session().run_state
	state.endless = true
	state.current_wave = 21
	state.shop_offer_initialized = true
	state.shop_offer_initialization_id = 4
	state.shop_offer_wave = 20
	state.shop_offer_ids = [ValidationContentFactory.RANGED_ID, &"", &"", &""]
	state.locked_shop_offer_ids = [ValidationContentFactory.RANGED_ID]
	assert_dict(GogoRunState.from_dictionary(state.to_dictionary(), session.content_snapshot).to_dictionary()).is_equal(state.to_dictionary())


func test_world_refuses_inconsistent_endless_or_zone_limit_even_with_valid_wave() -> void:
	for defect in ["endless_before_limit", "wrong_limit"]:
		var session := _session()
		var wave := GogoWaveResolver.resolve(session)
		if defect == "endless_before_limit":
			session.run_state.endless = true
		else:
			session.run_state.total_waves = 19
		var world := auto_free(CombatWorld.new()) as CombatWorld
		add_child(world)
		assert_int(world.start_wave(session, wave)).is_equal(ERR_INVALID_DATA)
		assert_object(world.session).is_null()


func test_zero_health_session_cannot_restart_world() -> void:
	var session := _session()
	var wave := GogoWaveResolver.resolve(session)
	session.run_state.player().current_health = 0.0
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	assert_int(world.start_wave(session, wave)).is_equal(ERR_INVALID_PARAMETER)
	assert_bool(world.running).is_false()
	assert_object(world.session).is_null()


func test_extreme_endless_fixed_reward_is_bounded_before_xp_processing() -> void:
	assert_int(GameSession.fixed_wave_xp_reward(21)).is_equal(50)
	assert_int(GameSession.fixed_wave_material_reward(21)).is_equal(48)
	assert_int(GameSession.fixed_wave_xp_reward(9223372036854775807)).is_equal(448)
	assert_int(GameSession.fixed_wave_material_reward(9223372036854775807)).is_equal(446)


func test_wave_difficulty_multiplies_runtime_copies_and_actor_population_is_capped() -> void:
	var packs := ValidationContentFactory.create_packs()
	for definition in packs[0].definitions:
		if definition is GogoDifficultyDefinition:
			definition.enemy_health_multiplier = 1.5
			definition.enemy_damage_multiplier = 2.0
			definition.enemy_speed_multiplier = 0.5
	var session := GameSession.new()
	assert_int(session.start(_config(), GogoContentRegistry.new().build_snapshot(packs))).is_equal(OK)
	session.run_state.current_wave = 20
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	assert_int(world.start_wave(session, GogoWaveResolver.resolve(session))).is_equal(OK)
	for index in 180:
		world.call("_spawn_enemy", &"gogobro.core:enemy/drifter")
	assert_int(world.active_enemy_count()).is_equal(160)
	var enemy := world.enemy_layer.get_child(0) as GogoEnemyActor
	assert_float(enemy.current_health).is_equal_approx(26.25, 0.0001)
	assert_float(enemy.definition.touch_damage).is_equal_approx(7.0, 0.0001)
	assert_float(enemy.definition.movement_speed).is_equal_approx(47.15, 0.0001)
	var original := session.content_snapshot.definition(&"gogobro.core:enemy/drifter", &"enemy") as GogoEnemyDefinition
	assert_float(original.movement_speed).is_equal(82.0)
	assert_float(original.max_health).is_equal(7.0)
	assert_float(original.touch_damage).is_equal(2.0)
	var difficulty := session.content_snapshot.definition(ValidationContentFactory.DIFFICULTY_ID, &"difficulty") as GogoDifficultyDefinition
	assert_float(difficulty.enemy_health_multiplier).is_equal(1.5)
	assert_float(difficulty.enemy_speed_multiplier).is_equal(0.5)


func test_twenty_wave_session_flow_does_not_win_at_five() -> void:
	var session := _session()
	var build := PlayerBuildService.new()
	for number in range(1, 21):
		assert_int(session.run_state.current_wave).is_equal(number)
		assert_object(GogoWaveResolver.resolve(session)).is_not_null()
		session.finish_wave()
		while session.run_state.pending_upgrade_count > 0:
			var offers := build.upgrade_reward_offers(session)
			assert_int(build.apply_upgrade(session, session.run_state.player(), offers[0].content_id)).is_equal(OK)
			session.run_state.pending_upgrade_count -= 1
		if session.run_state.phase == &"upgrade":
			session.transition(&"shop")
		assert_bool(session.run_state.ended).is_false()
		assert_bool(session.run_state.won).is_false()
		if number < 20:
			assert_bool(session.continue_after_shop()).is_true()
	assert_bool(session.finish_normal_run()).is_true()
	assert_bool(session.run_state.won).is_true()


func test_effective_minimum_interval_rejects_literal_deadline_overrun() -> void:
	var session := _session()
	var wave := _timing_wave({"count": 2, "start": 0.999, "end": 1.0})
	var runtime := WaveRuntime.new()
	runtime.begin(wave, 1.0)
	assert_int(runtime.tick(1.0).size()).is_equal(1)
	assert_bool(runtime.is_finished()).is_true()
	assert_int(int(runtime.schedules[0]["remaining"])).is_equal(1)
	assert_float(float(runtime.schedules[0]["next_spawn"])).is_equal_approx(1.009, 0.0000001)
	assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1)).is_equal(ERR_INVALID_DATA)
	print("TASK6_I1_LITERAL deadline=1 due=1 remaining=1 next=1.009 expected_validation=ERR_INVALID_DATA")


func test_effective_batch_interval_rejects_clamped_overrun() -> void:
	var session := _session()
	var wave := _timing_wave({"count": 4, "batch_size": 2, "interval_seconds": 0.0001, "start": 0.999, "end": 1.0})
	var runtime := WaveRuntime.new()
	runtime.begin(wave, 1.0)
	assert_int(runtime.tick(1.0).size()).is_equal(2)
	assert_int(int(runtime.schedules[1]["remaining"])).is_equal(2)
	assert_float(float(runtime.schedules[1]["next_spawn"])).is_equal_approx(1.009, 0.0000001)
	assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1)).is_equal(ERR_INVALID_DATA)


func test_near_deadline_legal_continuous_and_batch_schedules_finish_all_bodies() -> void:
	var session := _session()
	for group in [
		{"count": 2, "start": 0.989, "end": 1.0},
		{"count": 4, "batch_size": 2, "interval_seconds": 0.0001, "start": 0.989, "end": 1.0},
	]:
		var wave := _timing_wave(group)
		assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1)).is_equal(OK)
		var runtime := WaveRuntime.new()
		runtime.begin(wave, 1.0)
		assert_int(runtime.tick(1.0).size()).is_equal(int(group["count"]))
		assert_int(runtime.tick(1.0).size()).is_zero()


func test_selected_difficulty_rejects_effective_schedule_before_session_creation() -> void:
	var packs := ValidationContentFactory.create_packs()
	for definition in packs[0].definitions:
		if definition is GogoDifficultyDefinition:
			definition.spawn_multiplier = 3.0
		if definition is GogoWaveDefinition and definition.wave_number == 1:
			definition.duration_seconds = 1.0
			definition.spawn_groups = _timing_wave({"count": 2, "start": 0.2, "end": 1.0, "interval_seconds": 0.3}).spawn_groups
	var session := GameSession.new()
	assert_int(session.start(_config(), GogoContentRegistry.new().build_snapshot(packs))).is_equal(ERR_INVALID_DATA)
	assert_object(session.run_state).is_null()


func test_resolver_validates_selected_difficulty_for_existing_state() -> void:
	var session := _session()
	var packs := ValidationContentFactory.create_packs()
	for definition in packs[0].definitions:
		if definition is GogoDifficultyDefinition:
			definition.spawn_multiplier = 3.0
		if definition is GogoWaveDefinition and definition.wave_number == 1:
			definition.duration_seconds = 1.0
			definition.spawn_groups = _timing_wave({"count": 2, "start": 0.2, "end": 1.0, "interval_seconds": 0.3}).spawn_groups
	# A controlled existing-state boundary independently checks the resolver;
	# ordinary start() now refuses this snapshot before assigning run state.
	session.content_snapshot = GogoContentRegistry.new().build_snapshot(packs)
	assert_object(GogoWaveResolver.resolve(session)).is_null()


func test_world_effective_timing_refusal_preserves_previous_world_and_session() -> void:
	for spec in [
		[{"count": 2, "start": 0.999, "end": 1.0}, 1.0, 1],
		[{"count": 2, "start": 0.98, "end": 1.0}, 2.0, 3],
		[{"count": 2, "start": 0.2, "end": 1.0, "interval_seconds": 0.3}, 3.0, 3],
		[{"count": 4, "batch_size": 2, "interval_seconds": 0.0001, "start": 0.999, "end": 1.0}, 1.5, 3],
	]:
		var previous := _session()
		var world := auto_free(CombatWorld.new()) as CombatWorld
		add_child(world)
		assert_int(world.start_wave(previous, GogoWaveResolver.resolve(previous))).is_equal(OK)
		world.call("_spawn_enemy", &"gogobro.core:enemy/drifter")
		var old_wave := world.wave_runtime.wave
		var old_zone := world.zone_runtime
		var old_player := world.player_actor.player_state
		world.running = false # Reuse preflight; retain real old actors/references.
		var packs := ValidationContentFactory.create_packs()
		for definition in packs[0].definitions:
			if definition is GogoDifficultyDefinition:
				definition.spawn_multiplier = float(spec[1])
		var next_session := GameSession.new()
		assert_int(next_session.start(_config(), GogoContentRegistry.new().build_snapshot(packs))).is_equal(OK)
		var wave := _timing_wave(spec[0])
		var runtime := WaveRuntime.new()
		runtime.begin(wave, float(spec[1]))
		assert_int(runtime.tick(1.0).size()).is_equal(int(spec[2]))
		assert_int(world.start_wave(next_session, wave)).is_equal(ERR_INVALID_DATA)
		assert_object(world.session).is_same(previous)
		assert_object(world.wave_runtime.wave).is_same(old_wave)
		assert_object(world.zone_runtime).is_same(old_zone)
		assert_object(world.player_actor.player_state).is_same(old_player)
		assert_int(world.active_enemy_count()).is_equal(1)
		assert_bool(world.running).is_false()


func test_zero_density_scheduler_contract_stays_batch_zero_continuous_one() -> void:
	var continuous := _timing_wave({"count": 2, "start": 0.999, "end": 1.0})
	var batch := _timing_wave({"count": 4, "batch_size": 2, "interval_seconds": 0.0001, "start": 0.999, "end": 1.0})
	var runtime := WaveRuntime.new()
	runtime.begin(continuous, 0.0)
	assert_int(runtime.tick(1.0).size()).is_equal(1)
	runtime.begin(batch, 0.0)
	assert_int(runtime.tick(2.0).size()).is_zero()
	continuous.spawn_groups[0]["count"] = 0
	batch.spawn_groups[0]["count"] = 0
	runtime.begin(continuous, 1.0)
	assert_int(runtime.tick(1.0).size()).is_equal(1)
	runtime.begin(batch, 1.0)
	assert_int(runtime.tick(2.0).size()).is_zero()


func test_effective_schedule_obeys_group_end_even_before_wave_deadline() -> void:
	var session := _session()
	var wave := _timing_wave({"count": 2, "start": 0.999, "end": 1.0})
	wave.duration_seconds = 2.0
	assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1)).is_equal(ERR_INVALID_DATA)
	var runtime := WaveRuntime.new()
	runtime.begin(wave, 1.0)
	assert_int(runtime.tick(1.0).size()).is_equal(1)
	assert_int(runtime.tick(1.0).size()).is_equal(1)


func test_effective_batch_validation_keeps_late_zero_slots_empty() -> void:
	var session := _session()
	var wave := _timing_wave({"count": 9, "batch_size": 4, "interval_seconds": 0.01, "start": 0.985, "end": 1.0})
	# Rounded prefixes 0/1/1 emit only at0.995; the1.005 slot is empty.
	assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1, 0.1)).is_equal(OK)
	assert_int(GogoWaveResolver.validate_wave(wave, session.content_snapshot, 1, 1.0)).is_equal(ERR_INVALID_DATA)
	var runtime := WaveRuntime.new()
	runtime.begin(wave, 0.1)
	assert_int(runtime.tick(1.0).size()).is_equal(1)
	assert_int(runtime.tick(1.0).size()).is_zero()


func test_legal_scaled_near_deadline_world_spawns_four_then_finishes() -> void:
	var packs := ValidationContentFactory.create_packs()
	for definition in packs[0].definitions:
		if definition is GogoDifficultyDefinition:
			definition.spawn_multiplier = 2.0
	var session := GameSession.new()
	assert_int(session.start(_config(), GogoContentRegistry.new().build_snapshot(packs))).is_equal(OK)
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var wave := _timing_wave({"count": 2, "start": 0.96, "end": 1.0})
	assert_int(world.start_wave(session, wave)).is_equal(OK)
	var observed := [0, 0]
	world.hud_snapshot_changed.connect(func(snapshot: GogoCombatHudSnapshot) -> void:
		if snapshot.seconds == 0.0:
			observed[0] = world.active_enemy_count()
	)
	world.wave_completed.connect(func() -> void: observed[1] += 1)
	world.call("_physics_process", 1.0)
	assert_array(observed).contains_exactly([4, 1])
	assert_int(int(world.wave_runtime.schedules[0]["remaining"])).is_zero()
	assert_bool(world.running).is_false()


func _timing_wave(group: Dictionary) -> GogoWaveDefinition:
	var wave := GogoWaveDefinition.new()
	wave.duration_seconds = 1.0
	wave.wave_number = 1
	var actual_group := group.duplicate(true)
	actual_group["enemy_id"] = &"gogobro.core:enemy/drifter"
	wave.spawn_groups = [actual_group]
	return wave


func _session() -> GameSession:
	var session := GameSession.new()
	assert_int(session.start(_config(), GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs()))).is_equal(OK)
	return session


func _config() -> SessionConfig:
	var config := SessionConfig.new()
	config.seed = 62021
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	return config
