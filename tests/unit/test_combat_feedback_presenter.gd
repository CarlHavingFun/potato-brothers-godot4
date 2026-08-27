extends GdUnitTestSuite

var _feedback_trace: Array[String] = []
var _world_weapon_count := 0
var _world_melee_count := 0
var _world_contact_count := 0
var _world_death_count := 0


func before_test() -> void:
	_feedback_trace.clear()
	_world_weapon_count = 0
	_world_melee_count = 0
	_world_contact_count = 0
	_world_death_count = 0


func test_duplicate_and_stale_events_never_present_twice() -> void:
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	presenter.set_physics_process(false)
	for sequence in range(1, 521):
		assert_bool(presenter.present_weapon_fired(1, &"rapid", Vector2i(10, 20), Vector2.RIGHT, 1, sequence)).is_true()
	assert_bool(presenter.present_weapon_fired(1, &"rapid", Vector2i(10, 20), Vector2.RIGHT, 1, 1)).is_false()
	assert_bool(presenter.present_weapon_fired(1, &"rapid", Vector2i(10, 20), Vector2.RIGHT, 1, 519)).is_false()
	assert_int(presenter.active_effect_count()).is_equal(GogoCombatFeedbackPresenter.MAX_ACTIVE_EFFECTS)

	assert_bool(presenter.present_projectile_contact(2, 3, &"rifle", Vector2i(30, 40), Vector2.LEFT, &"ballistic", &"normal", 1)).is_true()
	assert_bool(presenter.present_projectile_contact(2, 3, &"rifle", Vector2i(30, 40), Vector2.LEFT, &"ballistic", &"normal", 1)).is_false()
	assert_bool(presenter.present_projectile_contact(2, 4, &"rifle", Vector2i(30, 40), Vector2.LEFT, &"ballistic", &"normal", 1)).is_false()
	assert_bool(presenter.present_projectile_contact(2, 4, &"rifle", Vector2i(30, 40), Vector2.LEFT, &"ballistic", &"normal", 2)).is_true()
	assert_bool(presenter.present_melee_contact(7, 8, &"heavy", Vector2i(12, 14), Vector2.LEFT, &"melee", &"normal", 1)).is_true()
	assert_bool(presenter.present_melee_contact(7, 9, &"heavy", Vector2i(12, 14), Vector2.LEFT, &"melee", &"normal", 1)).is_false()

	assert_bool(presenter.present_enemy_defeated(5, Vector2i(50, 60), 4, 2, 1)).is_true()
	assert_bool(presenter.present_enemy_defeated(5, Vector2i(50, 60), 4, 2, 1)).is_false()


func test_pool_caps_at_ninety_six_and_reuses_fixed_slots() -> void:
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	presenter.set_physics_process(false)
	for sequence in range(1, 98):
		presenter.present_weapon_fired(1, &"heavy", Vector2i(sequence, 0), Vector2.RIGHT, 1, sequence)

	var active := presenter.debug_effects()
	assert_int(presenter.allocated_slot_count()).is_equal(96)
	assert_int(presenter.active_effect_count()).is_equal(96)
	assert_int(active.size()).is_equal(96)
	assert_str(String(active[0].event_key)).is_equal("shot/1/2")
	assert_str(String(active[-1].event_key)).is_equal("shot/1/97")

	presenter._physics_process(1.0)
	assert_int(presenter.active_effect_count()).is_equal(0)
	assert_int(presenter.allocated_slot_count()).is_equal(96)
	assert_bool(presenter.present_weapon_fired(1, &"suppressed", Vector2i(98, 0), Vector2.UP, 1, 98)).is_true()
	var reused := presenter.debug_effects()
	assert_int(reused.size()).is_equal(1)
	assert_int(int(reused[0].slot_index)).is_equal(1)
	assert_int(int(reused[0].activation_serial)).is_equal(98)
	assert_float(float(reused[0].age)).is_equal(0.0)
	assert_str(String(reused[0].profile)).is_equal("suppressed")


func test_effect_records_and_draw_primitives_are_integer_pixel_blocks() -> void:
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	presenter.set_physics_process(false)
	presenter.present_weapon_fired(1, &"heavy", Vector2i(101, 203), Vector2(0.31, 0.95), 3, 1)
	presenter.present_projectile_contact(2, 3, &"rifle", Vector2i(207, 99), Vector2(-0.83, 0.55), &"ballistic", &"critical", 1)
	presenter.present_enemy_defeated(3, Vector2i(301, 401), 4, 2, 1)

	for effect: Dictionary in presenter.debug_effects():
		assert_bool(effect.position is Vector2i).is_true()
		assert_bool(effect.direction is Vector2i).is_true()
		assert_bool(GogoCombatFeedbackPresenter.DIRECTIONS_8.has(effect.direction as Vector2i)).is_true()
		assert_int(int(effect.size_px) % 2).is_equal(0)
		assert_int(int(effect.size_px)).is_greater_equal(4)
		assert_str(String(effect.visual_source)).is_equal("procedural_fallback")

	_assert_integer_primitives(presenter.debug_block_primitives())
	presenter._physics_process(0.035)
	_assert_integer_primitives(presenter.debug_block_primitives())


func test_approved_impact_texture_replaces_the_procedural_contact_blocks_at_exact_size() -> void:
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	presenter.set_physics_process(false)
	presenter.configure(null, _impact_visual_snapshot())

	assert_bool(presenter.present_projectile_contact(
		2,
		3,
		&"rifle",
		Vector2i(207, 99),
		Vector2.LEFT,
		&"ballistic",
		&"critical",
		1
	)).is_true()
	var effect := presenter.debug_effects()[0]
	assert_str(String(effect.visual_source)).is_equal("static_asset")
	assert_str(String(effect.visual_selector)).is_equal("static_critical_mark")
	assert_bool(effect.texture_size == Vector2i(64, 64)).is_true()
	assert_bool(effect.texture_pivot == Vector2i(32, 32)).is_true()
	assert_array(presenter.debug_block_primitives()).is_empty()


func test_canonical_shipping_snapshot_drives_all_four_approved_impact_selectors() -> void:
	var service := GogoStaticAssetRuntimeService.new()
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(service.stage(content)).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	presenter.set_physics_process(false)
	presenter.configure(null, service.active_snapshot())
	var expected_selectors := [
		&"static_hit_mark",
		&"static_critical_mark",
		&"static_pierce_mark",
		&"static_explosion_mark",
	]
	var impacts := [&"normal", &"critical", &"pierce_exit", &"explosion"]
	for index in impacts.size():
		assert_bool(presenter.present_projectile_contact(
			index + 1,
			index + 101,
			&"rifle",
			Vector2i(100 + index * 80, 100),
			Vector2.LEFT,
			&"ballistic",
			impacts[index],
			1
		)).is_true()
	var effects := presenter.debug_effects()
	assert_int(effects.size()).is_equal(4)
	for index in effects.size():
		assert_str(String(effects[index].visual_source)).is_equal("static_asset")
		assert_str(String(effects[index].visual_selector)).is_equal(String(expected_selectors[index]))
		assert_bool(effects[index].texture_size == Vector2i(64, 64)).is_true()
	assert_array(presenter.debug_block_primitives()).is_empty()


func test_camera_impulse_uses_integer_offset_without_moving_follow_anchor() -> void:
	var target := auto_free(Node2D.new()) as Node2D
	var camera := auto_free(GogoCombatCamera.new()) as GogoCombatCamera
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	add_child(target)
	add_child(camera)
	target.global_position = Vector2(5000.4, 5000.6)
	camera.configure(target, Rect2(Vector2.ZERO, Vector2(10000.0, 10000.0)))
	presenter.configure(camera)
	var base_position := camera.global_position
	var original_time_scale := Engine.time_scale

	assert_bool(presenter.present_weapon_fired(1, &"heavy", Vector2i(5000, 5001), Vector2.RIGHT, 1, 1)).is_true()
	camera._physics_process(0.016)

	assert_vector(camera.global_position).is_equal(base_position)
	assert_vector(camera.offset).is_equal(camera.offset.round())
	assert_bool(absf(camera.offset.x) <= GogoCombatCamera.MAX_VISUAL_IMPULSE).is_true()
	assert_bool(absf(camera.offset.y) <= GogoCombatCamera.MAX_VISUAL_IMPULSE).is_true()
	assert_float(Engine.time_scale).is_equal(original_time_scale)
	presenter.clear_feedback()
	assert_vector(camera.offset).is_equal(Vector2.ZERO)
	assert_vector(camera.global_position).is_equal(base_position)


func test_player_hit_uses_one_bounded_red_white_slot_and_camera_impulse() -> void:
	var target := auto_free(Node2D.new()) as Node2D
	var camera := auto_free(GogoCombatCamera.new()) as GogoCombatCamera
	var presenter := auto_free(GogoCombatFeedbackPresenter.new()) as GogoCombatFeedbackPresenter
	add_child(target)
	add_child(camera)
	target.global_position = Vector2(5000.0, 5000.0)
	camera.configure(target, Rect2(Vector2.ZERO, Vector2(10000.0, 10000.0)))
	presenter.configure(camera)
	assert_bool(presenter.has_method(&"present_player_damage_taken")).is_true()
	if not presenter.has_method(&"present_player_damage_taken"):
		return

	assert_bool(bool(presenter.call(
		&"present_player_damage_taken", Vector2i(5000, 5000), 3.0, 17.0, false, 1
	))).is_true()
	assert_bool(bool(presenter.call(
		&"present_player_damage_taken", Vector2i(5000, 5000), 3.0, 17.0, false, 1
	))).is_false()
	assert_int(presenter.allocated_slot_count()).is_equal(GogoCombatFeedbackPresenter.MAX_ACTIVE_EFFECTS)
	assert_int(presenter.active_effect_count()).is_equal(1)
	assert_int(presenter.active_effect_count(&"player_hit")).is_equal(1)
	var effect := presenter.debug_effects()[0]
	assert_str(String(effect.event_key)).is_equal("player_hit/1")
	assert_float(float(effect.duration)).is_equal_approx(0.10, 0.0001)
	assert_int(int(effect.size_px)).is_equal(36)
	var colors: Array[Color] = []
	for primitive: Dictionary in presenter.debug_block_primitives():
		colors.append(primitive.color as Color)
	assert_bool(colors.has(Color("fff4f2"))).is_true()
	assert_bool(colors.has(Color("ef3340"))).is_true()
	assert_float(camera.visual_impulse_magnitude()).is_greater(0.0)


func test_world_bindings_present_lethal_trace_once_without_changing_gameplay() -> void:
	var session := _session_with_player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.feedback_presenter.set_physics_process(false)
	world.feedback_presenter.feedback_spawned.connect(_on_feedback_spawned)
	world.weapon_fired.connect(_on_world_weapon_fired)
	world.projectile_contact.connect(_on_world_projectile_contact)
	world.enemy_defeated.connect(_on_world_enemy_defeated)

	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	owner.player_state = session.run_state.players[0]
	world.player_actor = owner
	world.add_child(owner)
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	var stats := _ranged_stats()
	weapon.configure(stats, owner)
	world.bind_weapon_feedback(weapon)
	world.bind_weapon_feedback(weapon)

	var enemy := _enemy(world, world.allocate_runtime_instance_id(&"enemy"), 60.0)
	world.bind_enemy_feedback(enemy)
	world.bind_enemy_feedback(enemy)
	var original_time_scale := Engine.time_scale
	var original_paused := get_tree().paused

	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	var projectile := world.projectile_layer.get_child(0) as GogoProjectile
	world.bind_projectile_feedback(projectile)
	world.bind_projectile_feedback(projectile)
	projectile._physics_process(0.1)

	assert_array(_feedback_trace).is_equal(["muzzle", "contact", "death"])
	assert_int(_world_weapon_count).is_equal(1)
	assert_int(_world_contact_count).is_equal(1)
	assert_int(_world_death_count).is_equal(1)
	assert_int(world.feedback_presenter.active_effect_count(&"muzzle")).is_equal(1)
	assert_int(world.feedback_presenter.active_effect_count(&"contact")).is_equal(1)
	assert_int(world.feedback_presenter.active_effect_count(&"death")).is_equal(1)
	assert_float(enemy.current_health).is_equal(0.0)
	assert_int(session.run_state.players[0].xp).is_zero()
	assert_int(session.run_state.players[0].materials).is_equal(35)
	assert_int(session.committed_reward_count()).is_equal(2)
	assert_int(world.active_pickup_count()).is_equal(2)
	assert_float(Engine.time_scale).is_equal(original_time_scale)
	assert_bool(get_tree().paused).is_equal(original_paused)
	world.collect_all_live_pickups()
	assert_int(session.run_state.players[0].xp).is_equal(4)
	assert_int(session.run_state.players[0].materials).is_equal(37)
	assert_int(world.active_pickup_count()).is_zero()

	assert_bool(world.feedback_presenter.present_enemy_defeated(999, Vector2i(0, 0), 999, 999, 1)).is_true()
	assert_int(session.run_state.players[0].xp).is_equal(4)
	assert_int(session.run_state.players[0].materials).is_equal(37)
	assert_int(session.committed_reward_count()).is_equal(2)


func test_nonlethal_melee_contact_is_presented_before_damage_without_fake_muzzle() -> void:
	var session := _session_with_player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.feedback_presenter.set_physics_process(false)
	world.feedback_presenter.feedback_spawned.connect(_on_feedback_spawned)
	world.weapon_fired.connect(_on_world_weapon_fired)
	world.melee_contact.connect(_on_world_melee_contact)
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	weapon.configure(_melee_stats(), owner)
	world.bind_weapon_feedback(weapon)
	world.bind_weapon_feedback(weapon)
	var enemy := _enemy(world, world.allocate_runtime_instance_id(&"enemy"), 60.0, 100.0)

	weapon._physics_process(0.0)

	assert_array(_feedback_trace).is_equal(["melee_contact"])
	assert_int(_world_melee_count).is_equal(1)
	assert_int(_world_weapon_count).is_equal(0)
	assert_float(enemy.current_health).is_equal(93.0)
	assert_int(session.committed_reward_count()).is_equal(0)
	assert_int(world.feedback_presenter.active_effect_count(&"muzzle")).is_equal(0)
	assert_int(world.feedback_presenter.active_effect_count(&"contact")).is_equal(1)
	assert_float(world.debug_local_hitstop_remaining()).is_equal_approx(0.035, 0.0001)
	var effect := world.feedback_presenter.debug_effects()[0]
	assert_str(String(effect.event_key)).is_equal("melee/1/2/1")
	assert_bool(effect.position == Vector2i(46, 0)).is_true()
	assert_str(String(effect.damage_kind)).is_equal("melee")


func _assert_integer_primitives(primitives: Array[Dictionary]) -> void:
	assert_bool(primitives.is_empty()).is_false()
	for primitive: Dictionary in primitives:
		assert_bool(primitive.rect is Rect2i).is_true()
		var rect := primitive.rect as Rect2i
		assert_int(rect.size.x).is_greater_equal(4)
		assert_int(rect.size.y).is_greater_equal(4)
		assert_int(rect.size.x % 2).is_equal(0)
		assert_int(rect.size.y % 2).is_equal(0)
		assert_float((primitive.color as Color).a).is_equal(1.0)


func _session_with_player() -> GameSession:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	var player := SessionPlayerState.new()
	player.player_index = 0
	run_state.players.append(player)
	session.run_state = run_state
	return session


func _ranged_stats() -> GogoWeaponRuntimeStats:
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.attack_range = 520.0
	stats.cooldown_seconds = 0.42
	stats.projectile_speed = 1000.0
	stats.projectile_count = 1
	stats.spread_degrees = 0.0
	stats.damage = 100.0
	stats.knockback = 22.0
	stats.feedback_profile_id = &"heavy"
	stats.damage_kind = &"ballistic"
	stats.impact_kind = &"critical"
	return stats


func _melee_stats() -> GogoWeaponRuntimeStats:
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.MELEE
	stats.attack_range = 100.0
	stats.cooldown_seconds = 0.55
	stats.damage = 7.0
	stats.knockback = 46.0
	stats.feedback_profile_id = &"heavy"
	stats.damage_kind = &"melee"
	stats.impact_kind = &"normal"
	return stats


func _impact_visual_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color8(255, 240, 168, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"projectile_hit_kit|impact_sprite|static_critical_mark",
		"asset_id": &"projectile_hit_kit",
		"role": &"impact_sprite",
		"selector": &"static_critical_mark",
		"display_size_px": Vector2i(64, 64),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(32, 32),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(320, 0, 64, 64),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{&"projectile_hit_kit": &"ready"},
		{"projectile_hit_kit|impact_sprite|static_critical_mark": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot


func _enemy(world: CombatWorld, runtime_id: int, x_position: float, max_health: float = 1.0) -> GogoEnemyActor:
	var definition := GogoEnemyDefinition.new()
	definition.max_health = max_health
	definition.xp_value = 4
	definition.material_value = 2
	var difficulty := GogoDifficultyDefinition.new()
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, null, difficulty, world, runtime_id)
	enemy.global_position = Vector2(x_position, 0.0)
	world.enemy_layer.add_child(enemy)
	assert_bool(world.register_active_enemy(enemy)).is_true()
	return enemy


func _on_feedback_spawned(kind: StringName, _position: Vector2i, _key: StringName) -> void:
	_feedback_trace.append(String(kind))


func _on_world_weapon_fired(
	_weapon_id: int,
	_profile: StringName,
	_position: Vector2i,
	_direction: Vector2,
	_count: int,
	_sequence: int
) -> void:
	_world_weapon_count += 1


func _on_world_projectile_contact(
	_projectile_id: int,
	_target_id: int,
	_profile: StringName,
	_position: Vector2i,
	_normal: Vector2,
	_damage_kind: StringName,
	_impact_kind: StringName,
	_sequence: int
) -> void:
	_world_contact_count += 1


func _on_world_melee_contact(
	_weapon_id: int,
	_target_id: int,
	_profile: StringName,
	_position: Vector2i,
	_normal: Vector2,
	_damage_kind: StringName,
	_impact_kind: StringName,
	_sequence: int
) -> void:
	_world_melee_count += 1


func _on_world_enemy_defeated(
	_enemy_id: int,
	_position: Vector2i,
	_xp: int,
	_materials: int,
	_sequence: int
) -> void:
	_world_death_count += 1
