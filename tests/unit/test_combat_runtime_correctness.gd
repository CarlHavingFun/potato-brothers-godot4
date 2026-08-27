extends GdUnitTestSuite


var _defeat_signal_count := 0


func before_test() -> void:
	_defeat_signal_count = 0


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


func _on_enemy_defeated(_enemy: GogoEnemyActor, _xp: int, _materials: int) -> void:
	_defeat_signal_count += 1
