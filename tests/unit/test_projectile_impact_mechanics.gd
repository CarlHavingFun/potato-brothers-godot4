extends GdUnitTestSuite


const BASE_DAMAGE := 10.0

var _impact_kinds: Array[StringName] = []
var _contact_target_ids: Array[int] = []
var _published_impacts: Array[Dictionary] = []


func before_test() -> void:
	_impact_kinds.clear()
	_contact_target_ids.clear()
	_published_impacts.clear()


func test_critical_weapon_contact_deals_double_damage() -> void:
	var setup := _weapon_setup(&"critical")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	var enemy := _enemy(world, 70.0)

	var projectile := _fire_one(weapon, world)
	projectile._physics_process(0.2)

	assert_float(enemy.current_health).is_equal(80.0)
	assert_array(_impact_kinds).is_equal([&"critical"])
	assert_bool(projectile.active).is_false()


func test_piercing_weapon_contact_hits_two_aligned_enemies() -> void:
	var setup := _weapon_setup(&"pierce_exit")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	var first_enemy := _enemy(world, 70.0)
	var second_enemy := _enemy(world, 115.0)

	var projectile := _fire_one(weapon, world)
	projectile._physics_process(0.2)

	assert_float(first_enemy.current_health).is_equal(90.0)
	assert_float(second_enemy.current_health).is_equal(90.0)
	assert_array(_impact_kinds).is_equal([&"pierce_exit", &"pierce_exit"])
	assert_array(_contact_target_ids).is_equal([
		first_enemy.runtime_instance_id,
		second_enemy.runtime_instance_id,
	])
	assert_int(projectile.contact_sequence).is_equal(2)
	assert_bool(projectile.active).is_false()


func test_explosive_weapon_contact_damages_nearby_enemies_only() -> void:
	var setup := _weapon_setup(&"explosion")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	var direct_enemy := _enemy(world, 70.0)
	var nearby_enemy := _enemy(world, 125.0)
	var distant_enemy := _enemy(world, 220.0)

	var projectile := _fire_one(weapon, world)
	projectile._physics_process(0.25)

	assert_float(direct_enemy.current_health).is_equal(90.0)
	assert_float(nearby_enemy.current_health).is_equal(90.0)
	assert_float(distant_enemy.current_health).is_equal(100.0)
	assert_array(_impact_kinds).is_equal([&"explosion"])
	assert_array(_contact_target_ids).is_equal([direct_enemy.runtime_instance_id])
	assert_bool(projectile.active).is_false()


func test_owned_skyline_grenade_naturally_adds_a_slow_explosive_seventh_projectile() -> void:
	var setup := _weapon_setup(&"normal")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	world.session.static_asset_snapshot = _skyline_grenade_snapshot()
	var player := world.session.run_state.player()
	player.item_ids.append(&"gogobro.preview:item/skyline_grenade")
	for _index in 7:
		assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)

	assert_int(world.projectile_layer.get_child_count()).is_equal(8)
	var grenade: GogoProjectile
	for child in world.projectile_layer.get_children():
		var projectile := child as GogoProjectile
		if projectile != null and projectile.impact_kind == &"explosion":
			grenade = projectile
			break
	assert_object(grenade).is_not_null()
	if grenade == null:
		return
	assert_str(String(grenade.get("source_item_id"))).is_equal(
		"gogobro.preview:item/skyline_grenade"
	)
	assert_float(grenade.damage).is_equal_approx(BASE_DAMAGE, 0.0001)
	assert_float(grenade.speed).is_equal_approx(500.0, 0.0001)
	assert_vector(grenade.global_position).is_equal(weapon.integer_muzzle_global_position())
	var grenade_sprite := grenade.get_node_or_null("TriggeredItemProjectileSprite") as Sprite2D
	assert_object(grenade_sprite).is_not_null()
	if grenade_sprite != null:
		assert_vector(grenade_sprite.scale).is_equal(Vector2(0.5, 0.5))
		assert_vector(grenade_sprite.position).is_equal(Vector2(-16.0, -16.0))
	assert_bool(world.has_signal(&"projectile_contact_published")).is_true()
	if not world.has_signal(&"projectile_contact_published"):
		return
	world.connect(&"projectile_contact_published", _on_projectile_contact_published)
	var enemy := _enemy(world, 70.0)
	grenade._physics_process(0.2)

	assert_float(enemy.current_health).is_equal(90.0)
	assert_int(_published_impacts.size()).is_equal(1)
	assert_str(String(_published_impacts[0].impact_kind)).is_equal("explosion")
	assert_str(String(_published_impacts[0].source_item_id)).is_equal(
		"gogobro.preview:item/skyline_grenade"
	)


func test_without_skyline_grenade_seven_normal_attacks_never_add_an_explosion() -> void:
	var setup := _weapon_setup(&"normal")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	for _index in 7:
		assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	assert_int(world.projectile_layer.get_child_count()).is_equal(7)
	for child in world.projectile_layer.get_children():
		assert_str(String((child as GogoProjectile).impact_kind)).is_equal("normal")


func test_clearing_combat_resets_the_per_weapon_skyline_counter() -> void:
	var setup := _weapon_setup(&"normal")
	var world := setup.world as CombatWorld
	var weapon := setup.weapon as GogoWeaponInstance
	world.session.run_state.player().item_ids.append(
		&"gogobro.preview:item/skyline_grenade"
	)
	for _index in 6:
		assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	world.call("_clear_active_combat_actors")
	await get_tree().process_frame
	assert_int(world.projectile_layer.get_child_count()).is_equal(0)
	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	assert_int(world.projectile_layer.get_child_count()).is_equal(1)
	assert_str(String((world.projectile_layer.get_child(0) as GogoProjectile).impact_kind)).is_equal(
		"normal"
	)


func _weapon_setup(impact_kind: StringName) -> Dictionary:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	var player := SessionPlayerState.new()
	player.player_index = 0
	run_state.players.append(player)
	session.run_state = run_state
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	world.projectile_contact.connect(_on_projectile_contact)
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	var stats := GogoWeaponRuntimeStats.new()
	stats.definition_id = &"gogobro.preview:weapon/test_rifle"
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.attack_range = 520.0
	stats.cooldown_seconds = 0.42
	stats.projectile_speed = 1000.0
	stats.projectile_count = 1
	stats.spread_degrees = 0.0
	stats.damage = BASE_DAMAGE
	stats.knockback = 0.0
	stats.feedback_profile_id = &"rifle"
	stats.damage_kind = &"ballistic"
	stats.impact_kind = impact_kind
	weapon.configure(stats, owner)
	return {"world": world, "weapon": weapon}


func _fire_one(weapon: GogoWeaponInstance, world: CombatWorld) -> GogoProjectile:
	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(1)
	assert_int(world.projectile_layer.get_child_count()).is_equal(1)
	return world.projectile_layer.get_child(0) as GogoProjectile


func _enemy(world: CombatWorld, x_position: float) -> GogoEnemyActor:
	var definition := GogoEnemyDefinition.new()
	definition.max_health = 100.0
	definition.xp_value = 0
	definition.material_value = 0
	var difficulty := GogoDifficultyDefinition.new()
	var enemy := GogoEnemyActor.new()
	enemy.configure(
		definition,
		null,
		difficulty,
		world,
		world.allocate_runtime_instance_id(&"enemy")
	)
	enemy.global_position = Vector2(x_position, 0.0)
	world.enemy_layer.add_child(enemy)
	assert_bool(world.register_active_enemy(enemy)).is_true()
	return enemy


func _on_projectile_contact(
	_projectile_instance_id: int,
	target_instance_id: int,
	_feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	_contact_normal: Vector2,
	_damage_kind: StringName,
	impact_kind: StringName,
	_contact_sequence: int
) -> void:
	_impact_kinds.append(impact_kind)
	_contact_target_ids.append(target_instance_id)


func _on_projectile_contact_published(event: Dictionary) -> void:
	_published_impacts.append(event.duplicate(true))


func _skyline_grenade_snapshot() -> GogoStaticAssetSnapshot:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color8(100, 115, 91, 255))
	var handle := GogoStaticAssetHandle.new()
	handle._configure({
		"binding_key": &"skyline_grenade|icon|",
		"asset_id": &"skyline_grenade",
		"role": &"icon",
		"selector": &"",
		"display_size_px": Vector2i(64, 64),
		"display_scale": Vector2.ONE,
		"pivot_px": Vector2i(32, 32),
		"anchors_px": {},
		"atlas_rect_px": Rect2i(0, 0, 64, 64),
	}, ImageTexture.create_from_image(image))
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		1,
		"skyline-fixture",
		1,
		{&"skyline_grenade": &"ready"},
		{"skyline_grenade|icon|": handle},
		{},
		{},
		{},
		[]
	)
	return snapshot
