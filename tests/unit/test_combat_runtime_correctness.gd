extends GdUnitTestSuite


const STATIC_REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const STATIC_RUNTIME_FIXTURE_ROOT := "user://combat-runtime-static-service-tests"

var _defeat_signal_count := 0
var _static_runtime_fixture_roots := PackedStringArray()
var _static_runtime_fixture_serial := 0


func before_test() -> void:
	_defeat_signal_count = 0


func after_test() -> void:
	for fixture_root: String in _static_runtime_fixture_roots:
		_remove_static_runtime_fixture_tree(fixture_root)
	_static_runtime_fixture_roots.clear()


func test_ranged_weapon_does_not_target_beyond_attack_range() -> void:
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var enemy := auto_free(Node2D.new()) as Node2D
	add_child(weapon)
	add_child(enemy)
	enemy.add_to_group(&"gogo_enemy")
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.attack_range = 100.0
	weapon.stats = stats

	enemy.global_position = Vector2(101.0, 0.0)
	assert_object(weapon._nearest_enemy()).is_null()
	enemy.global_position = Vector2(100.0, 0.0)
	assert_object(weapon._nearest_enemy()).is_same(enemy)


func test_projectile_spawns_at_integer_visible_muzzle_position() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.projectile_count = 1
	stats.projectile_speed = 500.0
	stats.damage = 1.0
	stats.knockback = 0.0
	stats.spread_degrees = 0.0
	weapon.configure(stats, owner)
	weapon.global_position = Vector2(100.4, 100.6)
	weapon.rotation = 0.0

	weapon._fire_projectiles(Vector2.RIGHT)

	assert_int(world.projectile_layer.get_child_count()).is_equal(1)
	var projectile := world.projectile_layer.get_child(0) as GogoProjectile
	assert_vector(projectile.global_position).is_equal(Vector2(128.0, 101.0))
	assert_vector(projectile.global_position).is_equal(weapon.integer_muzzle_global_position())


func test_weapon_runtime_stats_preserve_the_definition_static_asset_id() -> void:
	var definition := GogoWeaponDefinition.new()
	definition.content_id = &"test:weapon/service"
	definition.icon_asset_id = &"service_pistol"
	var player := SessionPlayerState.new()
	var stats := WeaponRuntimeService.new().build_instance(definition, player)

	assert_object(stats).is_not_null()
	assert_str(String(stats.static_asset_id)).is_equal("service_pistol")


func test_weapon_world_sprite_uses_approved_pivot_muzzle_and_left_facing_flip() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	weapon.static_asset_snapshot_override = _weapon_visual_snapshot()
	world.add_child(weapon)
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.static_asset_id = &"service_pistol"
	stats.feedback_profile_id = &"rifle"
	weapon.configure(stats, owner)
	weapon.global_position = Vector2(100.0, 100.0)

	var sprite := weapon.get_node("WeaponVisualRoot/WeaponSprite") as Sprite2D
	assert_object(sprite).is_not_null()
	assert_bool(sprite.position == Vector2(-32.0, -64.0)).is_true()
	assert_int(sprite.texture.get_width()).is_equal(128)
	assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	weapon.rotation = 0.0
	assert_vector(weapon.integer_muzzle_global_position()).is_equal(Vector2(180.0, 84.0))
	weapon.rotation = PI
	weapon.call("_update_visual_feedback")
	assert_bool((weapon.get_node("WeaponVisualRoot") as Node2D).scale == Vector2(1.0, -1.0)).is_true()
	assert_vector(weapon.integer_muzzle_global_position()).is_equal(Vector2(20.0, 84.0))
	weapon.rotation = 0.0
	weapon.attack_flash = 1.0
	weapon.call("_update_visual_feedback")
	assert_bool((weapon.get_node("WeaponVisualRoot") as Node2D).position == Vector2(-4.0, 0.0)).is_true()
	assert_vector(weapon.integer_muzzle_global_position()).is_equal(Vector2(176.0, 84.0))


func test_weapon_world_sprite_uses_service_resized_texture_without_double_scaling() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	var runtime_snapshot := _runtime_scaled_weapon_visual_snapshot()
	var handle := runtime_snapshot.resolve_asset(&"service_pistol", &"world_sprite")
	assert_object(handle).is_not_null()
	if handle == null:
		return
	assert_int(handle.texture.get_width()).is_equal(64)
	assert_int(handle.texture.get_height()).is_equal(64)
	assert_vector(handle.display_scale).is_equal(Vector2(2.0, 2.0))
	weapon.static_asset_snapshot_override = runtime_snapshot
	world.add_child(weapon)
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.static_asset_id = &"service_pistol"
	stats.feedback_profile_id = &"rifle"
	weapon.configure(stats, owner)
	weapon.global_position = Vector2(100.0, 100.0)

	var sprite := weapon.get_node("WeaponVisualRoot/WeaponSprite") as Sprite2D
	assert_vector(sprite.scale).is_equal(Vector2.ONE)
	assert_vector(sprite.position).is_equal(Vector2(-16.0, -32.0))
	assert_vector(weapon.integer_muzzle_global_position()).is_equal(Vector2(140.0, 92.0))


func test_projectile_sprite_uses_feedback_selector_pivot_rotation_and_nearest_filter() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var projectile := GogoProjectile.new()
	projectile.static_asset_snapshot_override = _projectile_visual_snapshot()
	projectile.direction = Vector2.UP
	projectile.activate(world, 1, 1, 1, 1, &"rifle", &"ballistic", &"normal")
	world.projectile_layer.add_child(projectile)

	var sprite := projectile.get_node("ProjectileSprite") as Sprite2D
	assert_object(sprite).is_not_null()
	assert_str(String(projectile.projectile_visual_handle.selector)).is_equal("rifle_round")
	assert_vector(sprite.position).is_equal(Vector2(-8.0, -4.0))
	assert_int(sprite.texture.get_width()).is_equal(16)
	assert_int(sprite.texture.get_height()).is_equal(8)
	assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_float(projectile.rotation).is_equal_approx(-PI * 0.5, 0.0001)
	projectile.retire()


func test_projectile_feedback_profiles_map_to_the_frozen_atlas_selectors() -> void:
	assert_str(String(GogoProjectile.selector_for_feedback_profile(&"rapid"))).is_equal("pistol_smg_round")
	assert_str(String(GogoProjectile.selector_for_feedback_profile(&"suppressed"))).is_equal("pistol_smg_round")
	assert_str(String(GogoProjectile.selector_for_feedback_profile(&"rifle"))).is_equal("rifle_round")
	assert_str(String(GogoProjectile.selector_for_feedback_profile(&"heavy"))).is_equal("sniper_round")
	assert_str(String(GogoProjectile.selector_for_feedback_profile(&"invalid"))).is_empty()


func test_cooldown_preserves_bounded_overshoot_without_reacquire_burst() -> void:
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var enemy := auto_free(Node2D.new()) as Node2D
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	add_child(weapon)
	add_child(enemy)
	enemy.add_to_group(&"gogo_enemy")
	enemy.global_position = Vector2(10.0, 0.0)
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.attack_range = 100.0
	stats.cooldown_seconds = 0.42
	stats.projectile_count = 1
	weapon.configure(stats, owner)
	weapon.cooldown_remaining = -0.01

	weapon._physics_process(0.0)
	assert_float(weapon.cooldown_remaining).is_equal_approx(0.41, 0.0001)

	enemy.remove_from_group(&"gogo_enemy")
	weapon.cooldown_remaining = -0.20
	weapon._physics_process(0.0)
	assert_float(weapon.cooldown_remaining).is_equal(0.0)


func test_enemy_defeat_signal_is_committed_exactly_once_before_deferred_free() -> void:
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	add_child(enemy)
	var definition := GogoEnemyDefinition.new()
	definition.max_health = 1.0
	definition.xp_value = 4
	definition.material_value = 2
	var difficulty := GogoDifficultyDefinition.new()
	enemy.configure(definition, null, difficulty)
	enemy.defeated.connect(_on_enemy_defeated)

	enemy.take_damage(1.0)
	enemy.take_damage(1.0)

	assert_int(_defeat_signal_count).is_equal(1)
	assert_bool(enemy.defeated_once).is_true()
	assert_float(enemy.current_health).is_equal(0.0)
	assert_bool(enemy.is_in_group(&"gogo_enemy")).is_false()
	assert_int(enemy.collision_layer).is_equal(0)
	assert_int(enemy.collision_mask).is_equal(0)


func test_combat_camera_follows_on_integer_world_pixels() -> void:
	var target := auto_free(Node2D.new()) as Node2D
	var camera := auto_free(GogoCombatCamera.new()) as GogoCombatCamera
	add_child(target)
	add_child(camera)
	target.global_position = Vector2(5000.4, 5000.6)
	camera.configure(target, Rect2(Vector2.ZERO, Vector2(10000.0, 10000.0)))

	assert_vector(camera.global_position).is_equal(Vector2(5000.0, 5001.0))
	target.global_position = Vector2(4999.51, 5000.49)
	camera._physics_process(0.0)
	assert_vector(camera.global_position).is_equal(Vector2(5000.0, 5000.0))


func test_enemy_xp_reward_preserves_pending_upgrade_count() -> void:
	var world := auto_free(CombatWorld.new()) as CombatWorld
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	var player := SessionPlayerState.new()
	player.xp_to_next_level = 5
	run_state.players.append(player)
	session.run_state = run_state
	world.session = session

	var result := world.commit_enemy_reward_snapshot(1, 1, 5, 3)

	assert_str(String(result[GameSession.REWARD_EXPERIENCE])).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(result[GameSession.REWARD_SUPPLY])).is_equal(String(GameSession.REWARD_APPLIED))
	assert_int(player.level).is_equal(2)
	assert_int(run_state.pending_upgrade_count).is_equal(1)
	assert_int(player.materials).is_equal(38)


func test_combat_hud_snapshot_reports_only_materials_gained_in_the_current_wave() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var session := _combat_session(content)
	session.static_asset_snapshot = _spawn_marker_snapshot()
	var player := session.run_state.player()
	player.materials = 80
	var wave := content.definition(&"gogobro.core:wave/training_1", &"wave") as GogoWaveDefinition
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	var snapshots: Array[GogoCombatHudSnapshot] = []
	world.hud_snapshot_changed.connect(func(snapshot: GogoCombatHudSnapshot) -> void:
		snapshots.append(snapshot)
	)
	assert_int(world.start_wave(session, wave)).is_equal(OK)
	assert_int(snapshots.size()).is_equal(1)
	assert_bool(_has_property(snapshots[0], &"wave_materials")).is_true()
	if not _has_property(snapshots[0], &"wave_materials"):
		return
	assert_int(snapshots[0].get(&"wave_materials")).is_zero()

	player.materials = 88
	world.call("_emit_hud_snapshot", 9.25)
	assert_int(snapshots.size()).is_equal(2)
	assert_int(snapshots[1].get(&"wave_materials")).is_equal(8)
	assert_int(player.materials).is_equal(88)


func test_enemy_stays_inactive_until_spawn_marker_completes_and_cannot_arrive_after_clear() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var session := _combat_session(content)
	session.static_asset_snapshot = _spawn_marker_snapshot()
	var wave := content.definition(&"gogobro.core:wave/training_1", &"wave") as GogoWaveDefinition
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	assert_int(world.start_wave(session, wave)).is_equal(OK)

	world.call("_spawn_enemy", &"gogobro.core:enemy/drifter")
	assert_int(world.active_enemy_count()).is_equal(0)
	var first_marker := world.effect_layer.find_child("SpawnMarker_*", false, false) as GogoStaticSpawnMarker
	assert_object(first_marker).is_not_null()
	first_marker.complete_now()
	assert_int(world.active_enemy_count()).is_equal(1)

	world.call("_clear_active_combat_actors")
	await get_tree().process_frame
	world.call("_spawn_enemy", &"gogobro.core:enemy/drifter")
	var marker_nodes := world.effect_layer.find_children("SpawnMarker_*", "GogoStaticSpawnMarker", false, false)
	var cancelled_marker := marker_nodes.back() as GogoStaticSpawnMarker
	assert_object(cancelled_marker).is_not_null()
	world.call("_clear_active_combat_actors")
	cancelled_marker.complete_now()
	assert_int(world.active_enemy_count()).is_equal(0)


func test_world_exit_frees_pending_enemy_spawn() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var session := _combat_session(content)
	session.static_asset_snapshot = _spawn_marker_snapshot()
	var wave := content.definition(&"gogobro.core:wave/training_1", &"wave") as GogoWaveDefinition
	var world := CombatWorld.new()
	add_child(world)
	assert_int(world.start_wave(session, wave)).is_equal(OK)

	world.call("_spawn_enemy", &"gogobro.core:enemy/drifter")
	var pending: Dictionary = world.get("_pending_spawn_enemies")
	assert_int(pending.size()).is_equal(1)
	var pending_enemy_ref: WeakRef = weakref(pending.values()[0])

	world.free()
	await get_tree().process_frame

	assert_object(pending_enemy_ref.get_ref()).is_null()


func test_targeting_and_projectiles_ignore_defeat_committed_enemies() -> void:
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var defeated_enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	var live_enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	add_child(weapon)
	add_child(defeated_enemy)
	add_child(live_enemy)
	defeated_enemy.global_position = Vector2(5.0, 0.0)
	defeated_enemy.defeated_once = true
	live_enemy.global_position = Vector2(50.0, 0.0)
	var stats := GogoWeaponRuntimeStats.new()
	stats.attack_range = 100.0
	weapon.stats = stats

	assert_object(weapon._nearest_enemy()).is_same(live_enemy)

	var projectile := auto_free(GogoProjectile.new()) as GogoProjectile
	add_child(projectile)
	projectile.global_position = defeated_enemy.global_position
	projectile.speed = 0.0
	projectile._physics_process(0.0)
	assert_bool(projectile.is_queued_for_deletion()).is_false()


func test_six_pivoted_weapon_footprints_clear_niko_and_each_other() -> void:
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	assert_bool(player.has_method("weapon_visual_footprint_radius")).is_true()
	if not player.has_method("weapon_visual_footprint_radius"):
		return
	var bounds: Array[Vector2i] = []
	var pivots: Array[Vector2i] = []
	for _index in 6:
		bounds.append(Vector2i(96, 64))
		pivots.append(Vector2i(38, 40))
	var footprint := float(player.call("weapon_visual_footprint_radius", bounds[0], pivots[0]))
	assert_float(footprint).is_equal_approx(sqrt(58.0 * 58.0 + 40.0 * 40.0), 0.001)
	var radius := float(player.call("weapon_orbit_radius", 6, bounds, pivots))
	for index in 6:
		var offset := player.weapon_orbit_offset(index, 6, radius)
		assert_float(offset.length() - footprint).is_greater_equal(76.0)
		for prior in index:
			var other := player.weapon_orbit_offset(prior, 6, radius)
			assert_float(offset.distance_to(other)).is_greater_equal(
				footprint * 2.0 + 12.0 - 0.001
			)


func test_real_physics_clamp_keeps_rotated_weapon_footprints_inside_arena(
	weapon_count: int,
	test_parameters := [[1], [2], [3], [4], [5], [6]]
) -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	var session := _combat_session(content)
	session.static_asset_snapshot = _orbit_weapon_visual_snapshot()
	var player_state := session.run_state.player()
	player_state.weapon_ids.clear()
	for _index in weapon_count:
		player_state.weapon_ids.append(ValidationContentFactory.RANGED_ID)
	var wave := content.definition(&"gogobro.core:wave/training_1", &"wave") as GogoWaveDefinition
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	assert_int(world.start_wave(session, wave)).is_equal(OK)
	var player := world.player_actor
	var weapons := player.weapon_orbit.get_children()
	assert_int(weapons.size()).is_equal(weapon_count)
	if weapons.size() != weapon_count:
		return

	for index in weapons.size():
		(weapons[index] as GogoWeaponInstance).rotation = deg_to_rad(17.0 + 31.0 * float(index))
	var center := world.arena_rect.get_center()
	var outside_positions := [
		Vector2(world.arena_rect.position.x - 500.0, center.y),
		Vector2(world.arena_rect.end.x + 500.0, center.y),
		Vector2(center.x, world.arena_rect.position.y - 500.0),
		Vector2(center.x, world.arena_rect.end.y + 500.0),
	]
	var edge_names := ["left", "right", "top", "bottom"]
	for edge_index in outside_positions.size():
		player.global_position = outside_positions[edge_index]
		player._physics_process(0.0)
		for weapon_index in weapons.size():
			var weapon := weapons[weapon_index] as GogoWeaponInstance
			var handle := weapon.weapon_visual_handle
			assert_object(handle).is_not_null()
			if handle == null:
				continue
			var footprint := player.weapon_visual_footprint_radius(
				handle.display_size_px,
				handle.pivot_px
			)
			var context := "count=%d edge=%s weapon=%d" % [
				weapon_count,
				edge_names[edge_index],
				weapon_index,
			]
			assert_float(weapon.global_position.x - footprint).override_failure_message(
				"Weapon footprint crossed arena left: %s" % context
			).is_greater_equal(world.arena_rect.position.x - 0.001)
			assert_float(weapon.global_position.x + footprint).override_failure_message(
				"Weapon footprint crossed arena right: %s" % context
			).is_less_equal(world.arena_rect.end.x + 0.001)
			assert_float(weapon.global_position.y - footprint).override_failure_message(
				"Weapon footprint crossed arena top: %s" % context
			).is_greater_equal(world.arena_rect.position.y - 0.001)
			assert_float(weapon.global_position.y + footprint).override_failure_message(
				"Weapon footprint crossed arena bottom: %s" % context
			).is_less_equal(world.arena_rect.end.y + 0.001)


func test_enemy_role_palette_uses_rust_olive_and_amber_body_colors() -> void:
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	assert_bool(enemy.has_method("visual_color_for_role")).is_true()
	if not enemy.has_method("visual_color_for_role"):
		return
	assert_str(String(enemy.call(
		"visual_color_for_role", GogoEnemyDefinition.Role.CHASER
	).to_html(false))).is_equal("b86d52")
	assert_str(String(enemy.call(
		"visual_color_for_role", GogoEnemyDefinition.Role.SHOOTER
	).to_html(false))).is_equal("9aa75a")
	assert_str(String(enemy.call(
		"visual_color_for_role", GogoEnemyDefinition.Role.CHARGER
	).to_html(false))).is_equal("d68a3a")


func test_high_speed_projectile_uses_nearest_swept_contact() -> void:
	var far_enemy := _configured_enemy(80.0)
	var near_enemy := _configured_enemy(40.0)
	var projectile := auto_free(GogoProjectile.new()) as GogoProjectile
	add_child(projectile)
	projectile.direction = Vector2.RIGHT
	projectile.speed = 1000.0
	projectile.damage = 1.0
	projectile.lifetime = 1.0

	projectile._physics_process(0.1)

	assert_float(near_enemy.current_health).is_equal(99.0)
	assert_float(far_enemy.current_health).is_equal(100.0)
	assert_bool(projectile.contact_committed).is_true()
	assert_float(projectile.global_position.x).is_equal_approx(21.0, 0.001)


func test_projectile_sweeps_its_final_partial_lifetime_before_expiring() -> void:
	var enemy := _configured_enemy(40.0)
	var projectile := auto_free(GogoProjectile.new()) as GogoProjectile
	add_child(projectile)
	projectile.direction = Vector2.RIGHT
	projectile.speed = 1000.0
	projectile.damage = 1.0
	projectile.lifetime = 0.05

	projectile._physics_process(0.1)

	assert_float(enemy.current_health).is_equal(99.0)
	assert_bool(projectile.contact_committed).is_true()


func _configured_enemy(x_position: float) -> GogoEnemyActor:
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	var definition := GogoEnemyDefinition.new()
	definition.max_health = 100.0
	var difficulty := GogoDifficultyDefinition.new()
	enemy.configure(definition, null, difficulty)
	add_child(enemy)
	enemy.global_position = Vector2(x_position, 0.0)
	return enemy


func _weapon_visual_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color8(58, 66, 74, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"service_pistol|world_sprite|",
		"asset_id": &"service_pistol",
		"role": &"world_sprite",
		"selector": &"",
		"display_size_px": Vector2i(128, 128),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(32, 64),
		"anchors_px": {"muzzle": Vector2i(112, 48)},
		"atlas_rect_px": Rect2i(0, 0, 128, 128),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{&"service_pistol": &"ready"},
		{"service_pistol|world_sprite|": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot


func _orbit_weapon_visual_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color8(58, 66, 74, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"service_pistol|world_sprite|",
		"asset_id": &"service_pistol",
		"role": &"world_sprite",
		"selector": &"",
		"display_size_px": Vector2i(96, 64),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(38, 40),
		"anchors_px": {"muzzle": Vector2i(86, 28)},
		"atlas_rect_px": Rect2i(0, 0, 96, 64),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"orbit_fixture",
		70,
		{&"service_pistol": &"ready"},
		{"service_pistol|world_sprite|": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot


func _runtime_scaled_weapon_visual_snapshot() -> GogoStaticAssetSnapshot:
	var fixture := _write_scaled_world_sprite_fixture()
	var service := GogoStaticAssetRuntimeService.new(
		String(fixture.manifest_path),
		String(fixture.registry_path),
		String(fixture.allowed_asset_root)
	)
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_int(service.stage(content)).is_equal(OK)
	assert_int(service.activate_staged(&"", null)).is_equal(OK)
	var snapshot := service.active_snapshot()
	assert_int(snapshot.ready_count()).is_equal(1)
	assert_int(snapshot.issues().size()).is_zero()
	return snapshot


func _write_scaled_world_sprite_fixture() -> Dictionary:
	_static_runtime_fixture_serial += 1
	var fixture_root := "%s/fixture-%s-%s" % [
		STATIC_RUNTIME_FIXTURE_ROOT,
		Time.get_ticks_usec(),
		_static_runtime_fixture_serial,
	]
	var allowed_asset_root := fixture_root.path_join("allowed-assets")
	var resource_path := allowed_asset_root.path_join("service_pistol.png")
	_static_runtime_fixture_roots.append(fixture_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(allowed_asset_root))

	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color8(234, 151, 39, 255))
	image.fill_rect(Rect2i(2, 14, 28, 4), Color8(44, 51, 57, 255))
	assert_int(image.save_png(ProjectSettings.globalize_path(resource_path))).is_equal(OK)
	var byte_sha256 := FileAccess.get_sha256(resource_path).to_lower()
	var rgba8_sha256 := _rgba8_sha256(image)
	var bindings: Array = [{
		"binding_key": "service_pistol|world_sprite|",
		"role": "world_sprite",
		"selector": "",
		"display_size_px": [64, 64],
		"display_scale": [2, 2],
		"pivot_px": [16, 32],
		"atlas_rect_px": [0, 0, 32, 32],
		"anchors_px": {"muzzle": [56, 24]},
		"consumers": [],
	}]

	var registry := JSON.parse_string(FileAccess.get_file_as_string(STATIC_REGISTRY_PATH)) as Dictionary
	for unit_variant: Variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("asset_id", "")) != "service_pistol":
			continue
		unit["approval_status"] = "approved"
		unit["hashes"] = {"sha256": byte_sha256, "rgba8_sha256": rgba8_sha256}
		unit["intended_file_paths"] = [resource_path]
		unit["output_spec"] = {"type": "png", "width": 32, "height": 32, "alpha": true}
		unit["runtime_bindings"] = bindings.duplicate(true)
		var evidence := (unit.get("shipping_approval_evidence", {}) as Dictionary).duplicate(true)
		evidence["runtime_bindings_sha256"] = _canonical_variant_sha256(bindings)
		evidence["scope"] = {"kind": "whole_texture", "selectors": []}
		evidence["shipping_texture"] = {
			"sha256": byte_sha256,
			"rgba8_sha256": rgba8_sha256,
			"pixel_size": [32, 32],
			"output_spec": {"format": "PNG", "width": 32, "height": 32, "alpha": true},
		}
		unit["shipping_approval_evidence"] = evidence

	var registry_path := fixture_root.path_join("registry.json")
	_write_json(registry_path, registry)
	var manifest_units: Array = []
	for unit_variant: Variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) == "character_creature":
			continue
		var asset_id := String(unit.get("asset_id", ""))
		var manifest_unit := {
			"asset_id": asset_id,
			"static_content_id": unit.get("content_id", ""),
			"category": unit.get("category", ""),
			"declared_runtime_state": "requested_active" if asset_id == "service_pistol" else "inactive",
			"approval_status": "approved" if asset_id == "service_pistol" else unit.get("approval_status", "planned"),
		}
		if asset_id == "service_pistol":
			manifest_unit["shipping"] = {
				"resource_path": resource_path,
				"sha256": byte_sha256,
				"rgba8_sha256": rgba8_sha256,
				"pixel_size": [32, 32],
				"texture_filter": "nearest",
				"mipmaps": false,
			}
			manifest_unit["bindings"] = bindings
		manifest_units.append(manifest_unit)
	var manifest := {
		"schema_version": GogoStaticAssetRuntimeService.SCHEMA_VERSION,
		"kind": GogoStaticAssetRuntimeService.MANIFEST_KIND,
		"canonical_registry_sha256": FileAccess.get_sha256(registry_path).to_lower(),
		"expected_noncharacter_units": 70,
		"units": manifest_units,
	}
	var manifest_path := fixture_root.path_join("manifest.json")
	_write_json(manifest_path, manifest)
	return {
		"manifest_path": manifest_path,
		"registry_path": registry_path,
		"allowed_asset_root": allowed_asset_root,
	}


func _write_json(path: String, payload: Dictionary) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(JSON.stringify(payload))
	file.close()


func _rgba8_sha256(source: Image) -> String:
	var rgba8 := source.duplicate()
	rgba8.convert(Image.FORMAT_RGBA8)
	var hashing := HashingContext.new()
	assert_int(hashing.start(HashingContext.HASH_SHA256)).is_equal(OK)
	assert_int(hashing.update(rgba8.get_data())).is_equal(OK)
	return hashing.finish().hex_encode()


func _canonical_variant_sha256(value: Variant) -> String:
	var normalized: Variant = JSON.parse_string(JSON.stringify(value))
	return JSON.stringify(normalized, "", true).sha256_text()


func _remove_static_runtime_fixture_tree(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not absolute_path.contains("combat-runtime-static-service-tests"):
		fail("Refusing unsafe combat runtime fixture cleanup: %s" % absolute_path)
		return
	_remove_absolute_fixture_tree(absolute_path)


func _remove_absolute_fixture_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_remove_absolute_fixture_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _projectile_visual_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color8(245, 215, 110, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"projectile_hit_kit|projectile_sprite|rifle_round",
		"asset_id": &"projectile_hit_kit",
		"role": &"projectile_sprite",
		"selector": &"rifle_round",
		"display_size_px": Vector2i(16, 8),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(8, 4),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(64, 0, 16, 8),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{&"projectile_hit_kit": &"ready"},
		{"projectile_hit_kit|projectile_sprite|rifle_round": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot


func _spawn_marker_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color8(245, 132, 59, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"spawn_marker|world_sprite|",
		"asset_id": &"spawn_marker",
		"role": &"world_sprite",
		"selector": &"",
		"display_size_px": Vector2i(96, 64),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(48, 32),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(0, 0, 96, 64),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"fixture",
		70,
		{&"spawn_marker": &"ready"},
		{"spawn_marker|world_sprite|": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot


func _combat_session(content: ContentSnapshot) -> GameSession:
	var config := SessionConfig.new()
	config.seed = 9137
	config.character_id = NikoContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, content)).is_equal(OK)
	return session


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false


func _on_enemy_defeated(_enemy: GogoEnemyActor, _xp: int, _materials: int) -> void:
	_defeat_signal_count += 1
