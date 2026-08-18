extends GdUnitTestSuite


class ConfirmedHitSource:
	extends Node2D

	var confirmed_hits := 0
	var last_result: HitResult

	func on_hit_confirmed(result: HitResult) -> void:
		confirmed_hits += 1
		last_result = result


class LifeStealProbe:
	extends WeaponBehavior

	var attempts := 0

	func apply_life_steal() -> void:
		attempts += 1


func after_test() -> void:
	_free_projectiles()
	Global.end_run()


func test_hit_resolver_returns_a_typed_deterministic_result() -> void:
	var resolver := HitResolver.new(CombatResolver.new(71))
	var request := HitRequest.new()
	request.raw_damage = 30.0
	request.armor = 15.0
	request.damage_multiplier = 0.5
	request.critical = true

	var result := resolver.resolve(request)

	assert_bool(result.landed).is_true()
	assert_bool(result.dodged).is_false()
	assert_bool(result.critical).is_true()
	assert_float(result.damage).is_equal_approx(7.5, 0.001)
	assert_float(result.raw_damage).is_equal(30.0)


func test_hit_resolver_reports_guaranteed_dodge_without_damage() -> void:
	var resolver := HitResolver.new(CombatResolver.new(72))
	var request := HitRequest.new()
	request.raw_damage = 20.0
	request.dodge_chance = 1.0

	var result := resolver.resolve(request)

	assert_bool(result.landed).is_false()
	assert_bool(result.dodged).is_true()
	assert_float(result.damage).is_zero()


func test_hitbox_only_notifies_gameplay_source_after_a_confirmed_hit() -> void:
	var source: ConfirmedHitSource = auto_free(ConfirmedHitSource.new()) as ConfirmedHitSource
	var hitbox: HitboxComponent = auto_free(HitboxComponent.new()) as HitboxComponent
	add_child(source)
	add_child(hitbox)
	hitbox.setup(10.0, false, 0.0, source, source)
	var missed := HitResult.new()
	missed.source = source
	hitbox.confirm_hit(missed)
	assert_int(source.confirmed_hits).is_zero()

	var landed := HitResult.new()
	landed.landed = true
	landed.damage = 10.0
	landed.source = source
	hitbox.confirm_hit(landed)

	assert_int(source.confirmed_hits).is_equal(1)
	assert_object(source.last_result).is_same(landed)


func test_unit_damage_flow_confirms_the_typed_result_after_health_changes() -> void:
	Global.begin_run(721, null, 0)
	var definition: EnemyDef = Content.catalog.get_enemy(&"enemy/swarm_mite")
	var enemy: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
	enemy.definition = definition
	add_child(enemy)
	var source: ConfirmedHitSource = auto_free(ConfirmedHitSource.new()) as ConfirmedHitSource
	var hitbox: HitboxComponent = auto_free(HitboxComponent.new()) as HitboxComponent
	add_child(source)
	add_child(hitbox)
	hitbox.setup(2.0, false, 0.0, source, source)
	var health_before := enemy.health_component.current_health

	enemy._on_hurtbox_component_on_damaged(hitbox)

	assert_float(enemy.health_component.current_health).is_equal(health_before - 2.0)
	assert_int(source.confirmed_hits).is_equal(1)
	assert_object(source.last_result.target).is_same(enemy)
	assert_float(source.last_result.health_before).is_equal(health_before)
	assert_float(source.last_result.health_after).is_equal(health_before - 2.0)


func test_pattern_status_and_explosion_are_consumed_on_confirmed_hit() -> void:
	Global.begin_run(73, null, 0)
	var definition: EnemyDef = Content.catalog.get_enemy(&"enemy/swarm_mite")
	var primary: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
	var secondary: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
	primary.definition = definition
	secondary.definition = definition
	add_child(primary)
	add_child(secondary)
	primary.global_position = Vector2.ZERO
	secondary.global_position = Vector2(30.0, 0.0)
	var secondary_health := secondary.health_component.current_health
	var source: ConfirmedHitSource = auto_free(ConfirmedHitSource.new()) as ConfirmedHitSource
	var hitbox: HitboxComponent = auto_free(HitboxComponent.new()) as HitboxComponent
	add_child(source)
	add_child(hitbox)
	hitbox.setup(20.0, false, 0.0, source, source, [], {
		"status_id": "burn",
		"status_duration": 2.5,
		"status_stacks": 2,
		"status_damage_scale": 0.1,
		"explosion_radius": 80.0,
		"explosion_damage_scale": 0.5,
	})
	var result := HitResult.new()
	result.landed = true
	result.damage = 20.0
	result.target = primary
	result.source = source

	hitbox.confirm_hit(result)

	assert_int(primary.effect_status_stacks(&"burn")).is_equal(2)
	assert_float(secondary.health_component.current_health).is_equal(
		maxf(0.0, secondary_health - 10.0)
	)


func test_elemental_weapon_copies_its_pattern_modifiers_to_the_melee_hitbox() -> void:
	Global.begin_run(730, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/ember_staff")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])

	var behavior := weapon.weapon_behavior as MeleeBehavior
	behavior.execute_attack()

	assert_str(str(behavior.hitbox.hit_modifiers.get("status_id", ""))).is_equal("burn")
	assert_float(float(behavior.hitbox.hit_modifiers.get("explosion_radius", 0.0))).is_equal(72.0)


func test_life_steal_is_attempted_only_after_damage_lands() -> void:
	var behavior: LifeStealProbe = auto_free(LifeStealProbe.new()) as LifeStealProbe
	var missed := HitResult.new()
	var landed := HitResult.new()
	landed.landed = true
	landed.damage = 1.0

	behavior.on_hit_confirmed(missed)
	assert_int(behavior.attempts).is_zero()
	behavior.on_hit_confirmed(landed)
	assert_int(behavior.attempts).is_equal(1)


func test_real_weapon_does_not_life_steal_when_its_attack_misses() -> void:
	Global.begin_run(731, null, 0)
	var player: Player = auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	player.health_component.current_health = player.health_component.max_health - 2.0
	var health_before := player.health_component.current_health
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/pistol")
	var item := definition.tiers[0].duplicate(true) as ItemWeapon
	item.stats.life_steal = 1.0
	var weapon: Weapon = auto_free(item.scene.instantiate() as Weapon) as Weapon
	player.add_child(weapon)
	weapon.setup_weapon(item)

	weapon.weapon_behavior.execute_attack()
	assert_float(player.health_component.current_health).is_equal(health_before)
	var projectile := _first_projectile()
	assert_object(projectile).is_not_null()
	if projectile == null:
		return
	var landed := HitResult.new()
	landed.landed = true
	landed.damage = 1.0
	projectile.hitbox.confirm_hit(landed)

	assert_float(player.health_component.current_health).is_equal(health_before + 1.0)


func test_projectile_uses_bounce_then_pierce_retention() -> void:
	var projectile: Projectile = auto_free(load(
		"res://scenes/projectiles/projectile_pistol.tscn"
	).instantiate() as Projectile) as Projectile
	add_child(projectile)
	projectile.set_projectile(
		Vector2(100.0, 0.0), 100.0, false, 0.0, projectile, null, [], 1, 1,
		&"projectile.enemy", {
			"pierce_damage_retention": 0.75,
			"bounce_damage_retention": 0.60,
		}
	)

	projectile.apply_transition_damage_decay(&"bounce")
	assert_float(projectile.hitbox.damage).is_equal_approx(60.0, 0.001)
	projectile.apply_transition_damage_decay(&"pierce")
	assert_float(projectile.hitbox.damage).is_equal_approx(45.0, 0.001)


func test_attack_pattern_separates_volleys_from_timed_bursts() -> void:
	var pattern := AttackPatternDef.new()
	pattern.kind = AttackPatternDef.Kind.BURST
	pattern.projectile_count = 2
	pattern.burst_count = 3
	pattern.spread_degrees = 10.0

	assert_int(pattern.volley_rotations(0.0).size()).is_equal(2)
	assert_int(pattern.shot_rotations(0.0).size()).is_equal(6)
	assert_float(pattern.attack_windup()).is_zero()
	assert_float(pattern.sequence_duration()).is_equal_approx(
		pattern.burst_interval * 2.0, 0.001
	)


func test_range_burst_spawns_followup_shots_after_an_interval() -> void:
	Global.begin_run(74, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/smg")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var behavior := weapon.weapon_behavior as RangeBehavior
	var before := _projectile_count()

	behavior.execute_attack()
	var immediate := _projectile_count() - before
	await get_tree().create_timer(definition.attack_pattern.burst_interval + 0.02).timeout
	var after_interval := _projectile_count() - before

	assert_int(immediate).is_equal(1)
	assert_bool(after_interval > immediate).is_true()


func test_equipped_weapon_refreshes_detection_radius_after_range_stat_changes() -> void:
	Global.begin_run(741, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/pistol")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var circle := weapon.collision.shape as CircleShape2D
	var initial_range := weapon.resolved_attack_range()

	assert_object(circle).is_not_null()
	assert_float(circle.radius).is_equal_approx(initial_range, 0.001)
	Global.current_run.player_stats.add_stat(StatId.RANGE, 47.0)
	await get_tree().process_frame

	assert_float(weapon.resolved_attack_range()).is_equal_approx(initial_range + 47.0, 0.001)
	assert_float(circle.radius).is_equal_approx(initial_range + 47.0, 0.001)


func test_melee_reach_contract_uses_resolved_runtime_attack_range() -> void:
	Global.begin_run(742, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/sword")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var behavior := weapon.weapon_behavior as MeleeBehavior
	var pattern := weapon.current_attack_pattern()
	var base_position := behavior._resolved_attack_position(pattern)

	Global.current_run.player_stats.add_stat(StatId.RANGE, 63.0)
	var resolved_position := behavior._resolved_attack_position(pattern)
	var multiplier := pattern.melee_reach_multiplier if pattern != null else 1.0

	assert_float(resolved_position.x).is_equal_approx(
		weapon.atk_start_pos.x + weapon.resolved_attack_range() * multiplier,
		0.001
	)
	assert_float(resolved_position.x - base_position.x).is_equal_approx(63.0 * multiplier, 0.001)


func test_charged_range_attack_waits_before_spawning_its_projectile() -> void:
	Global.begin_run(75, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/railbow")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var before := _projectile_count()

	weapon.weapon_behavior.execute_attack()
	assert_int(_projectile_count() - before).is_zero()
	await get_tree().create_timer(definition.attack_pattern.charge_duration + 0.02).timeout

	assert_int(_projectile_count() - before).is_equal(1)


func test_beam_attack_emits_damage_slices_over_time() -> void:
	Global.begin_run(76, null, 0)
	var definition: WeaponDef = Content.catalog.get_weapon(&"weapon/laser")
	var holder: Node2D = auto_free(Node2D.new()) as Node2D
	var weapon: Weapon = auto_free(definition.tiers[0].scene.instantiate() as Weapon) as Weapon
	add_child(holder)
	holder.add_child(weapon)
	weapon.setup_weapon(definition.tiers[0])
	var before := _projectile_count()

	weapon.weapon_behavior.execute_attack()
	var immediate := _projectile_count() - before
	await get_tree().create_timer(definition.attack_pattern.beam_pulse_interval + 0.02).timeout

	assert_int(immediate).is_equal(1)
	assert_bool(_projectile_count() - before > immediate).is_true()


func test_charged_beam_and_boomerang_have_observable_runtime_profiles() -> void:
	var charged := AttackPatternDef.new()
	charged.kind = AttackPatternDef.Kind.CHARGED
	var beam := AttackPatternDef.new()
	beam.kind = AttackPatternDef.Kind.BEAM
	var boomerang := AttackPatternDef.new()
	boomerang.kind = AttackPatternDef.Kind.BOOMERANG

	assert_bool(charged.attack_windup() > 0.0).is_true()
	assert_bool(beam.runtime_shot_count() > 1).is_true()
	assert_bool(beam.sequence_duration() > 0.0).is_true()
	assert_str(String(boomerang.projectile_modifiers().runtime_motion)).is_equal("boomerang")


func test_boomerang_projectile_turns_back_toward_its_owner() -> void:
	var owner_node: Node2D = auto_free(Node2D.new()) as Node2D
	var projectile: Projectile = auto_free(load(
		"res://scenes/projectiles/projectile_pistol.tscn"
	).instantiate() as Projectile) as Projectile
	add_child(owner_node)
	add_child(projectile)
	owner_node.global_position = Vector2.ZERO
	projectile.global_position = Vector2(100.0, 0.0)
	projectile.set_projectile(
		Vector2(100.0, 0.0), 5.0, false, 0.0, owner_node, null, [], 0, 0,
		&"projectile.enemy", {
			"runtime_motion": "boomerang",
			"boomerang_outbound_duration": 0.2,
		}
	)

	projectile._process(0.21)

	assert_bool(projectile.velocity.x < 0.0).is_true()
	assert_bool(projectile.is_queued_for_deletion()).is_false()


func _projectile_count() -> int:
	var result := 0
	for child: Node in get_tree().root.get_children():
		if child is Projectile:
			result += 1
	return result


func _first_projectile() -> Projectile:
	for child: Node in get_tree().root.get_children():
		if child is Projectile:
			return child as Projectile
	return null


func _free_projectiles() -> void:
	for child: Node in get_tree().root.get_children():
		if child is Projectile:
			child.free()
