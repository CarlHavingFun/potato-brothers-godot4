extends GdUnitTestSuite

const APP_SCENE := preload("res://game/app/app_root.tscn")


func test_actual_combat_screen_starts_normal_six_and_twenty() -> void:
	for number in [6, 20, 25]:
		var app := await _app()
		if number > 20:
			app.current_session.run_state.current_wave = 20
			app.current_session.transition(&"shop")
			assert_bool(app.current_session.continue_endless()).is_true()
		app.current_session.run_state.current_wave = number
		assert_int(app.route(FlowRoute.COMBAT)).is_equal(OK)
		await get_tree().process_frame
		var screen := _screen(app)
		var world := screen.get("world") as CombatWorld
		assert_object(world).is_not_null()
		if world != null:
			assert_bool(world.running).is_true()
			if world.running:
				assert_int(world.wave_runtime.wave.wave_number).is_equal(number)
		await _dispose(app)


func test_final_shop_exposes_two_real_skinned_actions() -> void:
	var app := await _app()
	app.current_session.run_state.current_wave = 20
	assert_int(app.current_session.transition(&"shop")).is_equal(OK)
	assert_int(app.route(FlowRoute.SHOP)).is_equal(OK)
	await get_tree().process_frame
	var shop := _screen(app)
	for action in [["FinishRunButton", "结束并结算"], ["EndlessButton", "继续无尽"]]:
		var button := shop.get_node_or_null(action[0]) as Button
		assert_object(button).is_not_null()
		if button != null:
			assert_str(button.text).is_equal(action[1])
			assert_bool(button.get_theme_stylebox(&"normal") is StyleBoxTexture).is_true()
	await _dispose(app)


func test_actual_endless_twenty_one_factory_starts_world() -> void:
	var app := await _app()
	app.current_session.run_state.current_wave = 20
	app.current_session.transition(&"shop")
	assert_bool(app.current_session.continue_endless()).is_true()
	var ids: Array[StringName] = [&"gogobro.core:enemy/drifter", &"gogobro.core:enemy/spark", &"gogobro.core:enemy/rammer", ValidationContentFactory.ELITE_RAMMER_ID]
	var wave := EndlessWaveFactory.new().build(21, ids)
	assert_object(wave).is_not_null()
	var world := CombatWorld.new()
	app.add_child(world)
	assert_int(world.start_wave(app.current_session, wave)).is_equal(OK)
	assert_bool(world.running).is_true()
	if world.running:
		assert_int(world.wave_runtime.wave.wave_number).is_equal(21)
		assert_bool(world.wave_runtime.schedules.is_empty()).is_false()
	await _dispose(app)


func test_actual_finish_button_records_once_and_repeated_close_is_inert() -> void:
	var app := await _app()
	var session := app.current_session
	var before := int(app.profile_service.profile_data.completed_runs)
	session.run_state.current_wave = 20
	session.transition(&"shop")
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	var button := _screen(app).get_node("FinishRunButton") as Button
	var ended := [0]
	session.run_ended.connect(func(_won: bool) -> void: ended[0] += 1)
	button.pressed.emit()
	button.pressed.emit()
	await get_tree().process_frame
	assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.SETTLEMENT)
	assert_bool(session.run_state.won).is_true()
	assert_bool(session.run_state.ended).is_true()
	assert_int(ended[0]).is_equal(1)
	assert_int(int(app.profile_service.profile_data.completed_runs)).is_equal(before + 1)
	var closes := [0]
	app.session_closed.connect(func() -> void: closes[0] += 1)
	app.close_session(true)
	app.close_session(true)
	assert_int(closes[0]).is_equal(1)
	assert_int(int(app.profile_service.profile_data.completed_runs)).is_equal(before + 1)
	await _dispose(app)


func test_actual_endless_button_preserves_build_rng_and_final_shop_cache() -> void:
	var app := await _app()
	var session := app.current_session
	session.run_state.current_wave = 20
	session.transition(&"shop")
	var shop := ShopRuntimeService.new()
	shop.open_shop(session)
	assert_bool(shop.toggle_lock(session, 0)).is_true()
	session.run_state.shop_offer_ids[1] = &"" # Persisted sold hole must not refill at the fork.
	var player := session.run_state.player()
	# A constructed build fixture, not a survival pilot or a purchase proof.
	player.weapon_inventory.add_weapon(ValidationContentFactory.MELEE_ID, session.content_snapshot)
	player.weapon_inventory.add_weapon(ValidationContentFactory.RANGED_ID, session.content_snapshot)
	player.weapon_inventory.combine_weapon(1)
	player.item_ids.append(&"gogobro.core:item/training_1")
	player.upgrade_ids.append(&"gogobro.core:upgrade/training_2")
	PlayerBuildService.new().rebuild_from_snapshot(session.content_snapshot, player)
	player.current_health = player.max_health - 2.0
	player.materials = 137
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	var before := session.run_state.to_dictionary()
	var rng_state := session.rng.state
	var button := _screen(app).get_node("EndlessButton") as Button
	button.pressed.emit()
	button.pressed.emit()
	var after := session.run_state.to_dictionary()
	for key in before:
		if key not in ["current_wave", "phase", "endless", "reroll_count"]:
			assert_that(after[key]).is_equal(before[key])
	assert_int(session.rng.state).is_equal(rng_state)
	assert_int(session.run_state.current_wave).is_equal(21)
	assert_str(session.run_state.shop_offer_ids[1]).is_empty()
	assert_bool(session.run_state.endless).is_true()
	assert_bool(session.run_state.ended).is_false()
	var world := _screen(app).get("world") as CombatWorld
	assert_bool(world.running).is_true()
	assert_int(world.wave_runtime.wave.wave_number).is_equal(21)
	assert_bool((_screen(app).get("latest_hud_snapshot") as GogoCombatHudSnapshot).endless).is_true()
	var checkpoint_21 := _fresh_checkpoint_state(app)
	assert_object(checkpoint_21).is_not_null()
	if checkpoint_21 != null:
		assert_dict(checkpoint_21.to_dictionary()).is_equal(session.run_state.to_dictionary())
	_screen(app).call("_open_pause")
	var pause := _screen(app).get("pause_overlay") as Control
	assert_str((pause.get_node("WaveProgress/Wave") as Label).text).is_equal("无尽 · 第 21 波")
	assert_bool((pause.get_node("WaveProgress/Progress") as ProgressBar).visible).is_false()
	await get_tree().process_frame
	_screen(app).call("_resume_from_pause")
	# Controlled duration completion exercises the real reward/upgrade/shop route.
	world.call("_finish_wave")
	await get_tree().process_frame
	await _complete_upgrades_via_ui(app)
	assert_object(_screen(app).get_node_or_null("EndlessButton")).is_null()
	assert_object(_screen(app).get_node_or_null("FinishRunButton")).is_null()
	(_screen(app).get_node("ContinueButton") as Button).pressed.emit()
	var checkpoint_22 := _fresh_checkpoint_state(app)
	assert_object(checkpoint_22).is_not_null()
	if checkpoint_22 != null:
		assert_dict(checkpoint_22.to_dictionary()).is_equal(session.run_state.to_dictionary())
	await get_tree().process_frame
	assert_int(session.run_state.current_wave).is_equal(22)
	assert_int((_screen(app).get("world") as CombatWorld).wave_runtime.wave.wave_number).is_equal(22)
	print("TASK6_CHECKPOINT_READBACK controlled=true resume_claim=false waves=21,22 live_world=22")
	await _dispose(app)


func test_authored_and_endless_world_schedules_spawn_damage_and_complete() -> void:
	# Controlled scheduler/actor contract, NOT a movement/survival/balance pilot.
	for spec in [[6, 117], [20, 280], [21, 292], [22, 304], [25, 340]]:
		var app := await _app()
		var session := app.current_session
		var number := int(spec[0])
		if number > 20:
			session.run_state.current_wave = 20
			session.transition(&"shop")
			assert_bool(session.continue_endless()).is_true()
		session.run_state.current_wave = number
		var world := CombatWorld.new()
		app.add_child(world)
		assert_int(world.start_wave(session, GogoWaveResolver.resolve(session))).is_equal(OK)
		world.set_physics_process(false)
		var counts := [0, 0, 0]
		var damage := [0.0]
		world.wave_completed.connect(func() -> void: counts[2] += 1)
		world.player_actor.damage_taken.connect(func(_p, amount, _hp, _lethal, _sequence) -> void:
			damage[0] += amount
		)
		var seen := {}
		var expected_duration := 42.0 if number == 6 else 60.0
		assert_float(world.wave_runtime.wave.duration_seconds).is_equal(expected_duration)
		while world.running and world.wave_runtime.elapsed < expected_duration + 1.0:
			world.call("_physics_process", 0.25)
			for marker in world.effect_layer.get_children():
				if marker is GogoStaticSpawnMarker:
					marker.complete_now()
			for candidate in world.enemy_layer.get_children():
				if not candidate is GogoEnemyActor:
					continue
				var enemy := candidate as GogoEnemyActor
				if enemy.defeated_once or seen.has(enemy.runtime_instance_id):
					continue
				seen[enemy.runtime_instance_id] = true
				counts[0] += 1
				assert_bool(enemy.definition.content_id.is_empty()).is_false()
				if counts[0] == 1:
					# Real actor contact on a living target, without invulnerability.
					enemy.position = world.player_actor.position + Vector2(25, 0)
					enemy.call("_physics_process", 1.0 / 60.0)
				var old_health := enemy.current_health
				enemy.take_damage(1.0)
				assert_float(enemy.current_health).is_less(old_health)
				counts[1] += 1
				# Clear the controlled target via its real damage/reward path so
				# all scheduled bodies are observed, independent of build balance.
				enemy.take_damage(enemy.current_health)
		assert_int(counts[0]).is_equal(int(spec[1]))
		assert_int(counts[1]).is_equal(int(spec[1]))
		assert_float(damage[0]).is_greater(0.0)
		assert_int(counts[2]).is_equal(1)
		assert_bool(session.run_state.ended).is_false()
		assert_bool(world.running).is_false()
		print("TASK6_RUNTIME controlled=true wave=%d scheduled=%d spawned=%d damaged=%d player_damage=%.3f seconds=%.2f completed=%d" % [number, spec[1], counts[0], counts[1], damage[0], world.wave_runtime.elapsed, counts[2]])
		await _dispose(app)


func test_invalid_combat_route_is_diagnostic_not_empty_world() -> void:
	for number in [0, -1, 21]:
		var app := await _app()
		app.current_session.run_state.current_wave = number
		app.route(FlowRoute.COMBAT)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.DIAGNOSTIC)
		assert_object(_screen(app).get("world")).is_null()
		await _dispose(app)


func test_fifth_shop_click_enters_six_without_victory_or_endless_choice() -> void:
	var app := await _app()
	var session := app.current_session
	session.run_state.current_wave = 5
	session.transition(&"shop")
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	assert_object(_screen(app).get_node_or_null("EndlessButton")).is_null()
	(_screen(app).get_node("ContinueButton") as Button).pressed.emit()
	assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.COMBAT)
	assert_int(session.run_state.current_wave).is_equal(6)
	assert_bool(session.run_state.ended).is_false()
	assert_bool(session.run_state.endless).is_false()
	assert_int((_screen(app).get("world") as CombatWorld).wave_runtime.wave.wave_number).is_equal(6)
	await _dispose(app)


func test_invalid_continue_click_never_routes_to_settlement_or_records_victory() -> void:
	var app := await _app()
	var session := app.current_session
	var records := int(app.profile_service.profile_data.completed_runs)
	session.transition(&"shop")
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	var button := _screen(app).get_node("ContinueButton") as Button
	session.transition(&"combat")
	button.pressed.emit()
	assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.SHOP)
	assert_int(session.run_state.current_wave).is_equal(1)
	assert_bool(session.run_state.ended).is_false()
	assert_int(int(app.profile_service.profile_data.completed_runs)).is_equal(records)
	session.run_state.current_wave = 20
	session.transition(&"shop")
	session.run_state.player().current_health = 0.0
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	assert_object(_screen(app).get_node_or_null("ContinueButton")).is_null()
	assert_object(_screen(app).get_node_or_null("EndlessButton")).is_null()
	session.fail_run()
	app.route(FlowRoute.SHOP)
	await get_tree().process_frame
	assert_object(_screen(app).get_node_or_null("EndlessButton")).is_null()
	assert_object(_screen(app).get_node_or_null("FinishRunButton")).is_null()
	assert_object(_screen(app).get_node_or_null("ContinueButton")).is_null()
	await _dispose(app)


func _complete_upgrades_via_ui(app: AppKernel) -> void:
	while app.current_session.run_state.pending_upgrade_count > 0:
		assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.UPGRADE)
		var choice := _screen(app).get_node_or_null("UpgradeChoiceRow/UpgradeChoice0") as Button
		assert_object(choice).is_not_null()
		if choice == null:
			return
		assert_bool(choice.disabled).is_false()
		choice.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
	assert_str(app.scene_flow.current_route()).is_equal(FlowRoute.SHOP)


func _fresh_checkpoint_state(app: AppKernel) -> GogoRunState:
	var reader := ProfileService.new()
	assert_int(reader.load_profile(app.content_snapshot)).is_equal(OK)
	assert_bool(reader.profile_data.has("run_checkpoint")).is_true()
	if not reader.profile_data.has("run_checkpoint"):
		return null
	var parsed := GogoRunState.parse_dictionary(reader.profile_data.run_checkpoint, app.content_snapshot)
	assert_int(parsed.error).is_equal(OK)
	return parsed.state as GogoRunState


func _app() -> AppKernel:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	get_tree().root.add_child(viewport)
	var app := APP_SCENE.instantiate() as AppKernel
	viewport.add_child(app)
	await get_tree().process_frame
	assert_bool(app.boot_result.is_ok()).is_true()
	app.begin_selection()
	app.selection_draft["seed"] = 62021
	app.selection_draft["character_id"] = ValidationContentFactory.CHARACTER_ID
	app.selection_draft["weapon_id"] = ValidationContentFactory.RANGED_ID
	assert_int(app.create_session_from_draft()).is_equal(OK)
	return app


func _screen(app: AppKernel) -> Node:
	return app.get_node("SceneHost").get_child(0)


func _dispose(app: AppKernel) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	app.get_parent().free()
	await get_tree().process_frame
