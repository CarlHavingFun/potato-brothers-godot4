extends GdUnitTestSuite


const PICKUP_PATH := "res://game/gameplay/world/combat_pickup.gd"


func test_world_builds_dedicated_pickup_layer_and_pickup_starts_dropped() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	assert_object(world.get_node_or_null("PickupLayer")).is_not_null()
	assert_bool(FileAccess.file_exists(PICKUP_PATH)).is_true()
	if not FileAccess.file_exists(PICKUP_PATH):
		return
	var pickup_script := load(PICKUP_PATH) as GDScript
	var pickup := auto_free(pickup_script.new()) as Node2D
	assert_int(int(pickup.get("state"))).is_equal(int(pickup_script.get(&"DROPPED")))


func test_pop_offset_is_small_integer_and_determined_by_enemy_and_pickup_ids() -> void:
	var pickup_script := load(PICKUP_PATH) as GDScript
	var pickup := auto_free(pickup_script.new()) as Node2D
	assert_bool(pickup.has_method(&"deterministic_pop_offset")).is_true()
	if not pickup.has_method(&"deterministic_pop_offset"):
		return
	assert_bool(
		pickup.call(&"deterministic_pop_offset", 2, 3) == Vector2i(-10, 10)
	).is_true()
	assert_bool(
		pickup.call(&"deterministic_pop_offset", 2, 4) == Vector2i(-4, -2)
	).is_true()
	assert_bool(
		pickup.call(&"deterministic_pop_offset", 3, 3) == Vector2i(7, -11)
	).is_true()


func test_pickup_magnetizes_inside_live_range_and_accelerates_smoothly() -> void:
	var pickup_script := load(PICKUP_PATH) as GDScript
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var target := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	target.player_state = SessionPlayerState.new()
	target.player_state.final_stats[&"pickup_range"] = 115.0
	add_child(target)
	target.global_position = Vector2.ZERO
	var pickup := auto_free(pickup_script.new()) as Node2D
	world.pickup_layer.add_child(pickup)
	assert_bool(pickup.has_method(&"configure")).is_true()
	if not pickup.has_method(&"configure"):
		return
	assert_bool(bool(pickup.call(
		&"configure",
		world,
		target,
		3,
		2,
		GameSession.REWARD_EXPERIENCE,
		4,
		&"enemy/2/death/1/experience",
		1,
		null,
		Vector2(126, -10)
	))).is_true()
	assert_vector(pickup.global_position).is_equal(Vector2(116, 0))
	pickup.call(&"_physics_process", 0.1)
	assert_int(int(pickup.get("state"))).is_equal(int(pickup_script.get(&"DROPPED")))
	assert_vector(pickup.global_position).is_equal(Vector2(116, 0))

	target.player_state.final_stats[&"pickup_range"] = 116.0
	pickup.call(&"_physics_process", 0.1)
	var first_speed := (pickup.get("velocity") as Vector2).length()
	assert_int(int(pickup.get("state"))).is_equal(int(pickup_script.get(&"MAGNETIZING")))
	assert_float(first_speed).is_greater(0.0)
	assert_float(pickup.global_position.x).is_less(116.0)
	var first_position := pickup.global_position
	pickup.call(&"_physics_process", 0.1)
	assert_float((pickup.get("velocity") as Vector2).length()).is_greater(first_speed)
	assert_float(pickup.global_position.x).is_less(first_position.x)


func test_visible_body_contact_collects_at_50px_and_exact_boundary_without_magnet_range() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	player.final_stats[&"pickup_range"] = 0.0
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(player)
	world.add_child(world.player_actor)
	assert_bool(world.player_actor.has_method(&"pickup_interaction_radius")).is_true()
	if not world.player_actor.has_method(&"pickup_interaction_radius"):
		return
	var contact_radius := float(world.player_actor.call(&"pickup_interaction_radius"))
	assert_float(contact_radius).is_equal(60.0)
	var distances := [50.0, contact_radius, contact_radius + 0.01, 300.0]
	var pickups: Array[GogoCombatPickup] = []
	for index in distances.size():
		var enemy_id := 16 + index
		var reservations := world._reserve_enemy_reward_snapshot(enemy_id, 1, 1, 1, 0)
		assert_int(world.spawn_reserved_enemy_pickups(
			enemy_id, Vector2i.ZERO, reservations
		)).is_equal(1)
		var pickup := world.active_pickup_at(index) as GogoCombatPickup
		pickup.global_position = world.player_actor.global_position + Vector2(distances[index], 0.0)
		pickups.append(pickup)

	for pickup in pickups:
		pickup._physics_process(0.0)

	var pickup_script := load(PICKUP_PATH) as GDScript
	assert_int(int(pickups[0].state)).is_equal(int(pickup_script.get(&"COLLECTED")))
	assert_int(int(pickups[1].state)).is_equal(int(pickup_script.get(&"COLLECTED")))
	assert_int(int(pickups[2].state)).is_equal(int(pickup_script.get(&"DROPPED")))
	assert_int(int(pickups[3].state)).is_equal(int(pickup_script.get(&"DROPPED")))
	assert_int(world.active_pickup_count()).is_equal(2)
	assert_int(player.xp).is_equal(2)
	assert_int(player.materials).is_equal(SessionPlayerState.INITIAL_MATERIALS + 2)

	player.final_stats[&"pickup_range"] = contact_radius + 1.0
	pickups[2]._physics_process(0.0)
	pickups[3]._physics_process(0.0)
	assert_int(int(pickups[2].state)).is_equal(int(pickup_script.get(&"MAGNETIZING")))
	assert_int(int(pickups[3].state)).is_equal(int(pickup_script.get(&"DROPPED")))


func test_reserved_enemy_rewards_spawn_one_pickup_per_nonzero_kind_without_applying() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	player.xp_to_next_level = 5
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(player)
	world.add_child(world.player_actor)
	var reservations := world.call(
		&"_reserve_enemy_reward_snapshot", 17, 1, 4, 2, 0
	) as Dictionary
	assert_int(player.xp).is_zero()
	assert_int(player.materials).is_equal(35)
	assert_bool(world.has_method(&"spawn_reserved_enemy_pickups")).is_true()
	if not world.has_method(&"spawn_reserved_enemy_pickups"):
		return

	assert_int(int(world.call(
		&"spawn_reserved_enemy_pickups", 17, Vector2i(200, 300), reservations
	))).is_equal(2)
	assert_int(int(world.call(&"active_pickup_count"))).is_equal(2)
	assert_int(world.pickup_layer.get_child_count()).is_equal(2)
	var experience := world.call(&"active_pickup_at", 0) as Node2D
	var supply := world.call(&"active_pickup_at", 1) as Node2D
	assert_int(int(experience.get("runtime_instance_id"))).is_equal(1)
	assert_int(int(supply.get("runtime_instance_id"))).is_equal(2)
	assert_str(String(experience.get("reward_kind"))).is_equal("experience")
	assert_str(String(supply.get("reward_kind"))).is_equal("supply")
	assert_vector(experience.global_position).is_equal(Vector2(208, 294))
	assert_vector(supply.global_position).is_equal(Vector2(189, 307))
	assert_int(player.xp).is_zero()
	assert_int(player.materials).is_equal(35)

	var supply_only := world.call(
		&"_reserve_enemy_reward_snapshot", 18, 1, 0, 3, 0
	) as Dictionary
	assert_int(int(world.call(
		&"spawn_reserved_enemy_pickups", 18, Vector2i(400, 400), supply_only
	))).is_equal(1)
	assert_int(int(world.call(&"active_pickup_count"))).is_equal(3)


func test_missing_texture_collects_exactly_once_and_publishes_only_when_applied() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	player.xp_to_next_level = 5
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(player)
	world.add_child(world.player_actor)
	world.player_actor.global_position = Vector2(100, 100)
	var reservations := world.call(
		&"_reserve_enemy_reward_snapshot", 21, 1, 5, 0, 0
	) as Dictionary
	assert_int(int(world.call(
		&"spawn_reserved_enemy_pickups", 21, Vector2i(100, 100), reservations
	))).is_equal(1)
	var pickup := world.call(&"active_pickup_at", 0) as Node2D
	assert_object(pickup.get("visual_sprite")).is_null()
	assert_bool(pickup.get("fallback_visual_active") == true).is_true()
	assert_bool(world.has_signal(&"pickup_collected")).is_true()
	assert_bool(pickup.has_method(&"collect_now")).is_true()
	if not world.has_signal(&"pickup_collected") or not pickup.has_method(&"collect_now"):
		return
	var collected_payloads: Array[Dictionary] = []
	var state_was_collected_during_apply: Array[bool] = []
	world.connect(&"pickup_collected", func(
		pickup_instance_id: int,
		kind: StringName,
		amount: int,
		integer_collection_global_position: Vector2i,
		collection_sequence: int
	) -> void:
		collected_payloads.append({
			&"id": pickup_instance_id,
			&"kind": kind,
			&"amount": amount,
			&"position": integer_collection_global_position,
			&"sequence": collection_sequence,
		})
	)
	session.reward_committed.connect(func(
		_token: StringName,
		_kind: StringName,
		_amount: int,
		_player_index: int
	) -> void:
		state_was_collected_during_apply.append(
			int(pickup.get("state")) == int((load(PICKUP_PATH) as GDScript).get(&"COLLECTED"))
		)
	)

	assert_str(String(pickup.call(&"collect_now"))).is_equal(String(GameSession.REWARD_APPLIED))
	assert_int(int(pickup.get("state"))).is_equal(int((load(PICKUP_PATH) as GDScript).get(&"COLLECTED")))
	assert_array(state_was_collected_during_apply).is_equal([true])
	assert_int(player.level).is_equal(2)
	assert_int(player.xp).is_zero()
	assert_int(int(world.call(&"active_pickup_count"))).is_zero()
	assert_int(collected_payloads.size()).is_equal(1)
	assert_int(int(collected_payloads[0].id)).is_equal(int(pickup.get("runtime_instance_id")))
	assert_str(String(collected_payloads[0].kind)).is_equal("experience")
	assert_int(int(collected_payloads[0].amount)).is_equal(5)
	assert_int(int(collected_payloads[0].sequence)).is_equal(1)

	assert_str(String(pickup.call(&"collect_now"))).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_int(player.level).is_equal(2)
	assert_int(collected_payloads.size()).is_equal(1)

	var already_applied := world.call(
		&"_reserve_enemy_reward_snapshot", 22, 1, 0, 3, 0
	) as Dictionary
	assert_int(int(world.call(
		&"spawn_reserved_enemy_pickups", 22, Vector2i(100, 100), already_applied
	))).is_equal(1)
	var stale_pickup := world.call(&"active_pickup_at", 0) as Node2D
	var supply_reservation := already_applied[GameSession.REWARD_SUPPLY] as Dictionary
	assert_str(String(session.apply_reserved_reward(
		StringName(supply_reservation.token), int(supply_reservation.reservation_id)
	))).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(stale_pickup.call(&"collect_now"))).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_int(player.materials).is_equal(38)
	assert_int(collected_payloads.size()).is_equal(1)


func test_enemy_death_reserves_and_spawns_instead_of_applying_immediately() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(player)
	world.add_child(world.player_actor)
	var definition := GogoEnemyDefinition.new()
	definition.max_health = 1.0
	definition.xp_value = 4
	definition.material_value = 2
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, null, GogoDifficultyDefinition.new(), world, 31)
	world.enemy_layer.add_child(enemy)
	enemy.global_position = Vector2(240, 180)
	assert_bool(world.register_active_enemy(enemy)).is_true()

	assert_bool(enemy.take_damage(1.0)).is_true()
	assert_int(player.xp).is_zero()
	assert_int(player.materials).is_equal(35)
	assert_int(world.active_pickup_count()).is_equal(2)
	assert_int(world.pickup_layer.get_child_count()).is_equal(2)


func test_dynamic_pickup_uses_static_texture_and_records_the_real_consumer() -> void:
	GogoStaticConsumerRegistry.reset_current()
	var session := _session_with_player()
	var handle := _pickup_handle(&"experience_pickup")
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"pickup_fixture",
		70,
		{&"experience_pickup": &"ready"},
		{String(handle.binding_key): handle},
		{},
		{},
		{},
		[]
	)
	session.static_asset_snapshot = snapshot
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(session.run_state.player())
	world.add_child(world.player_actor)
	var reservations := world.call(
		&"_reserve_enemy_reward_snapshot", 41, 1, 2, 0, 0
	) as Dictionary
	assert_int(world.spawn_reserved_enemy_pickups(41, Vector2i(300, 200), reservations)).is_equal(1)
	var pickup := world.active_pickup_at(0)
	var sprite := pickup.get_node_or_null("StaticVisual") as Sprite2D
	assert_object(sprite).is_not_null()
	if sprite == null:
		return
	assert_object(sprite.texture).is_same(handle.texture)
	assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_vector(sprite.position).is_equal(Vector2(-48, -32))
	assert_bool(pickup.get("fallback_visual_active") == false).is_true()
	var records := GogoStaticConsumerRegistry.current().records()
	assert_int(records.size()).is_equal(1)
	assert_str(String((records[0] as Dictionary).asset_id)).is_equal("experience_pickup")
	assert_str(String((records[0] as Dictionary).scene)).is_equal(PICKUP_PATH)


func test_wave_finish_auto_collects_in_runtime_id_order_before_final_hud_and_transition() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.player_actor = _player_actor(player)
	world.add_child(world.player_actor)
	world.set("_wave_start_materials", player.materials)
	world.running = true
	for spec in [
		{&"id": 9, &"amount": 1},
		{&"id": 3, &"amount": 2},
		{&"id": 7, &"amount": 3},
	]:
		var token := StringName("wave/pickup/%d" % int(spec.id))
		var reservation := session.reserve_reward_once(
			token, GameSession.REWARD_SUPPLY, int(spec.amount), 0
		)
		var pickup_script := load(PICKUP_PATH) as GDScript
		var pickup := pickup_script.new() as Node2D
		world.pickup_layer.add_child(pickup)
		assert_bool(bool(pickup.call(
			&"configure",
			world,
			world.player_actor,
			int(spec.id),
			51,
			GameSession.REWARD_SUPPLY,
			int(spec.amount),
			token,
			int(reservation.reservation_id),
			null,
			Vector2(300, 300)
		))).is_true()
		assert_bool(world.register_active_pickup(pickup)).is_true()
	var trace: Array[String] = []
	var final_hud_materials := [-1]
	var final_hud_wave_materials := [-1]
	world.pickup_collected.connect(func(
		pickup_instance_id: int,
		_kind: StringName,
		_amount: int,
		_integer_collection_global_position: Vector2i,
		_collection_sequence: int
	) -> void:
		trace.append("pickup_%d" % pickup_instance_id)
	)
	world.hud_snapshot_changed.connect(func(snapshot: GogoCombatHudSnapshot) -> void:
		trace.append("hud")
		final_hud_materials[0] = snapshot.materials
		final_hud_wave_materials[0] = snapshot.wave_materials
	)
	world.wave_completed.connect(func() -> void:
		trace.append("wave")
	)

	world.call(&"_finish_wave")

	assert_array(trace).is_equal(["pickup_3", "pickup_7", "pickup_9", "hud", "wave"])
	assert_int(final_hud_materials[0]).is_equal(41)
	assert_int(final_hud_wave_materials[0]).is_equal(6)
	assert_int(player.materials).is_equal(57)
	assert_int(world.active_pickup_count()).is_zero()


func _session_with_player() -> GameSession:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	run_state.phase = &"combat"
	var player := SessionPlayerState.new()
	player.player_index = 0
	player.final_stats[&"pickup_range"] = 115.0
	run_state.players.append(player)
	session.run_state = run_state
	return session


func _player_actor(player: SessionPlayerState) -> GogoPlayerActor:
	var actor := GogoPlayerActor.new()
	actor.player_state = player
	return actor


func _pickup_handle(asset_id: StringName) -> GogoStaticAssetHandle:
	var size := Vector2i(96, 64)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color8(91, 196, 232, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": StringName("%s|world_sprite|" % asset_id),
		"asset_id": asset_id,
		"role": &"world_sprite",
		"selector": &"",
		"display_size_px": size,
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(48, 32),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(Vector2i.ZERO, size),
	}, ImageTexture.create_from_image(image))
	return handle
