extends GdUnitTestSuite


const BASE_DAMAGE := 10.0

var _impact_kinds: Array[StringName] = []
var _contact_target_ids: Array[int] = []


func before_test() -> void:
	_impact_kinds.clear()
	_contact_target_ids.clear()


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
