extends GdUnitTestSuite


class TacticalHitProbe:
	extends Node2D

	var confirmed_hits := 0
	var last_result: HitResult

	func on_hit_confirmed(result: HitResult) -> void:
		confirmed_hits += 1
		last_result = result


class DamageTextProbe:
	extends RefCounted

	var calls := 0
	var last_critical := false
	var last_display_damage := 0.0

	func record(_unit: Unit, hitbox: HitboxComponent) -> void:
		calls += 1
		last_critical = hitbox.critical
		last_display_damage = hitbox.display_damage


func after_test() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"tactical_utilities"):
		if is_instance_valid(node):
			node.free()
	Global.end_run()


func test_attack_pattern_exports_typed_tactical_utility_contract() -> void:
	var pattern := AttackPatternDef.new()
	pattern.kind = AttackPatternDef.Kind.THROWN
	pattern.utility_kind = &"flash"
	pattern.arming_delay = 0.35
	pattern.travel_duration = 0.25
	pattern.throw_arc_height = 80.0
	pattern.zone_duration = 2.0
	pattern.zone_radius = 96.0
	pattern.zone_tick_interval = 0.2
	pattern.zone_speed_multiplier = 0.55
	pattern.interrupt_ranged = true
	pattern.max_active = 2

	var modifiers := pattern.projectile_modifiers()

	assert_str(str(modifiers.utility_kind)).is_equal("flash")
	assert_float(float(modifiers.arming_delay)).is_equal(0.35)
	assert_float(float(modifiers.travel_duration)).is_equal(0.25)
	assert_float(float(modifiers.throw_arc_height)).is_equal(80.0)
	assert_float(float(modifiers.zone_duration)).is_equal(2.0)
	assert_float(float(modifiers.zone_radius)).is_equal(96.0)
	assert_float(float(modifiers.zone_speed_multiplier)).is_equal(0.55)
	assert_bool(bool(modifiers.interrupt_ranged)).is_true()
	assert_int(int(modifiers.max_active)).is_equal(2)


func test_ak_style_recoil_ramp_grows_then_caps_and_recovers() -> void:
	var pattern := AttackPatternDef.new()
	pattern.recoil_ramp_degrees_per_shot = 2.0
	pattern.recoil_ramp_cap_degrees = 5.0
	pattern.recoil_recovery_seconds = 0.55

	assert_float(pattern.recoil_ramp_degrees(0)).is_zero()
	assert_float(pattern.recoil_ramp_degrees(1)).is_equal(2.0)
	assert_float(pattern.recoil_ramp_degrees(2)).is_equal(4.0)
	assert_float(pattern.recoil_ramp_degrees(3)).is_equal(5.0)
	assert_float(Weapon.spread_half_angle_radians(1.0, pattern, 3)).is_equal_approx(
		deg_to_rad(5.0), 0.0001
	)


func test_he_damages_only_targets_inside_its_radius() -> void:
	Global.begin_run(901, null, 0)
	var near_enemy := _spawn_enemy(Vector2(25.0, 0.0))
	var far_enemy := _spawn_enemy(Vector2(220.0, 0.0))
	var near_before := near_enemy.health_component.current_health
	var far_before := far_enemy.health_component.current_health
	var utility := _spawn_utility(&"he", 10.0, 80.0)

	utility.detonate_now()

	assert_float(near_enemy.health_component.current_health).is_equal(near_before - 10.0)
	assert_float(far_enemy.health_component.current_health).is_equal(far_before)


func test_he_uses_typed_critical_hit_triggers_damage_text_and_confirmation() -> void:
	Global.begin_run(9011, null, 0)
	var enemy := _spawn_enemy(Vector2(25.0, 0.0))
	var health_before := enemy.health_component.current_health
	var source := auto_free(TacticalHitProbe.new()) as TacticalHitProbe
	add_child(source)
	var critical_bonus := EffectDef.new()
	critical_bonus.effect_id = &"effect/test/tactical_critical_bonus"
	critical_bonus.trigger_events = [GameplayEvent.Type.CRITICAL_HIT]
	critical_bonus.operations = [EffectOperationDef.extra_damage(1.0)]
	assert_bool(Global.gameplay_effects.register_effect(critical_bonus)).is_true()
	var damage_text := DamageTextProbe.new()
	Global.on_create_damage_text.connect(damage_text.record, CONNECT_ONE_SHOT)
	var utility := _spawn_utility(&"he", 2.0, 80.0, source)
	utility.is_critical = true
	utility.gameplay_tags = [&"tactical", &"explosion"]

	utility.detonate_now()

	assert_float(enemy.health_component.current_health).is_equal(health_before - 3.0)
	assert_int(source.confirmed_hits).is_equal(1)
	assert_object(source.last_result.target).is_same(enemy)
	assert_bool(source.last_result.critical).is_true()
	assert_float(source.last_result.damage).is_equal(3.0)
	assert_int(damage_text.calls).is_equal(1)
	assert_bool(damage_text.last_critical).is_true()
	assert_float(damage_text.last_display_damage).is_equal(3.0)


func test_flash_applies_blind_and_interrupts_ranged_attacks() -> void:
	Global.begin_run(902, null, 0)
	var enemy := _spawn_enemy(Vector2(20.0, 0.0))
	var utility := _spawn_utility(&"flash", 1.0, 100.0)
	utility.status_duration = 1.6
	utility.interrupt_ranged = true

	utility.detonate_now()

	assert_int(enemy.effect_status_stacks(&"blind")).is_equal(1)
	assert_bool(enemy.is_ranged_attack_interrupted()).is_true()


func test_smoke_zone_slows_enemies_and_enemy_projectiles() -> void:
	Global.begin_run(903, null, 0)
	var enemy := _spawn_enemy(Vector2(20.0, 0.0))
	var projectile := auto_free(load(
		"res://scenes/projectiles/projectile_pistol.tscn"
	).instantiate() as Projectile) as Projectile
	add_child(projectile)
	projectile.global_position = Vector2(10.0, 0.0)
	projectile.hitbox.collision_layer = 4
	projectile.set_projectile(
		Vector2(100.0, 0.0), 1.0, false, 0.0, projectile, null, [], 0, 0
	)
	var utility := _spawn_utility(&"smoke", 0.0, 100.0)
	utility.zone_speed_multiplier = 0.5

	utility.tick_zone_now()

	assert_int(enemy.effect_status_stacks(&"smoke")).is_equal(1)
	assert_float(enemy.effect_speed_multiplier()).is_equal(0.5)
	assert_float(projectile.temporary_speed_multiplier()).is_equal(0.5)


func test_molotov_zone_applies_owned_burn() -> void:
	Global.begin_run(904, null, 0)
	var enemy := _spawn_enemy(Vector2(20.0, 0.0))
	var source := auto_free(Node2D.new()) as Node2D
	add_child(source)
	var utility := _spawn_utility(&"molotov", 8.0, 100.0, source)
	utility.status_damage_scale = 0.25

	utility.tick_zone_now()

	assert_int(enemy.effect_status_stacks(&"burn")).is_equal(1)
	assert_object(enemy.status_source(&"burn")).is_same(source)


func test_c4_waits_for_arming_delay_before_detonating() -> void:
	Global.begin_run(905, null, 0)
	var enemy := _spawn_enemy(Vector2(20.0, 0.0))
	var health_before := enemy.health_component.current_health
	var utility := _spawn_utility(&"c4", 6.0, 100.0)
	utility.arming_delay = 0.5
	utility.start_armed_phase()

	utility.advance_simulation(0.49)
	assert_float(enemy.health_component.current_health).is_equal(health_before)
	utility.advance_simulation(0.02)

	assert_float(enemy.health_component.current_health).is_equal(health_before - 6.0)
	assert_bool(utility.is_queued_for_deletion()).is_true()


func test_c4_confirmed_typed_hit_reaches_real_weapon_life_steal() -> void:
	Global.begin_run(9052, null, 0)
	var player := auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	player.health_component.current_health = player.health_component.max_health - 2.0
	var health_before := player.health_component.current_health
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/pistol")
	var item := definition.tiers[0].duplicate(true) as ItemWeapon
	item.stats.life_steal = 1.0
	var weapon := auto_free(item.scene.instantiate() as Weapon) as Weapon
	player.add_child(weapon)
	weapon.setup_weapon(item)
	Global.combat_resolver.reset_life_steal_rate_limit()
	_spawn_enemy(Vector2(20.0, 0.0))
	var utility := _spawn_utility(&"c4", 1.0, 100.0, weapon)

	utility.detonate_now()

	assert_float(player.health_component.current_health).is_equal(health_before + 1.0)


func test_thrown_tactical_visual_follows_a_parabola_and_lands_at_target() -> void:
	Global.begin_run(9051, null, 0)
	var utility := auto_free(TacticalUtilityRuntime.new()) as TacticalUtilityRuntime
	add_child(utility)
	var pattern := AttackPatternDef.new()
	pattern.kind = AttackPatternDef.Kind.THROWN
	pattern.utility_kind = &"he"
	pattern.travel_duration = 1.0
	pattern.throw_arc_height = 64.0
	pattern.explosion_radius = 60.0
	utility.configure(
		pattern, Vector2.ZERO, Vector2(100.0, 0.0), 0.0, utility, [], &"weapon.void_prism"
	)
	var visual := utility.get_node("Sprite2D") as Sprite2D

	utility.advance_simulation(0.5)
	assert_object(utility.global_position).is_equal(Vector2(50.0, 0.0))
	assert_float(visual.position.y).is_equal(-64.0)
	utility.advance_simulation(0.5)

	assert_object(utility.global_position).is_equal(Vector2(100.0, 0.0))
	assert_object(visual.position).is_equal(Vector2.ZERO)


func test_flash_cancels_an_enemy_ranged_windup() -> void:
	Global.begin_run(906, null, 0)
	assert_bool(Global.enter_phase(RunPhase.COMBAT)).is_true()
	var enemy := auto_free(load(
		"res://scenes/unit/enemy/enemy_shooter.tscn"
	).instantiate() as Enemy) as Enemy
	add_child(enemy)
	var behavior := enemy.get_node("ShootingBehavior") as ShootingBehavior
	behavior._start_windup()
	enemy.apply_effect_status({
		"status_id": "blind",
		"duration": 1.0,
		"stacks": 1,
		"interrupt_ranged": true,
	})

	behavior._process(0.01)

	assert_int(behavior.shooting_state).is_equal(ShootingBehavior.ShootingState.APPROACH)
	assert_bool(enemy.can_move).is_true()


func test_range_behavior_spawns_typed_utility_and_enforces_active_limit() -> void:
	Global.begin_run(907, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/pistol")
	var holder := auto_free(Node2D.new()) as Node2D
	var weapon := auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var behavior := weapon.weapon_behavior as RangeBehavior
	var pattern := AttackPatternDef.new()
	pattern.kind = AttackPatternDef.Kind.DEPLOYABLE
	pattern.utility_kind = &"c4"
	pattern.arming_delay = 5.0
	pattern.explosion_radius = 100.0
	pattern.max_active = 1

	var first := behavior._spawn_tactical_utility(pattern)
	var second := behavior._spawn_tactical_utility(pattern)

	assert_object(first).is_not_null()
	assert_object(second).is_not_null()
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_bool(second.is_queued_for_deletion()).is_false()
	assert_int(second.phase).is_equal(TacticalUtilityRuntime.Phase.ARMING)


func _spawn_enemy(position: Vector2) -> Enemy:
	var definition: EnemyDef = Content.catalog.get_enemy(&"enemy/swarm_mite")
	var enemy := auto_free(definition.scene.instantiate() as Enemy) as Enemy
	enemy.definition = definition
	add_child(enemy)
	enemy.global_position = position
	return enemy


func _spawn_utility(
	kind: StringName,
	damage: float,
	radius: float,
	source: Node2D = null
) -> TacticalUtilityRuntime:
	var utility := auto_free(TacticalUtilityRuntime.new()) as TacticalUtilityRuntime
	add_child(utility)
	utility.global_position = Vector2.ZERO
	utility.configure_for_test(kind, damage, radius, source)
	return utility
