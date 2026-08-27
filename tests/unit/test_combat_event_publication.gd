extends GdUnitTestSuite


var _trace: Array[String] = []
var _weapon_payloads: Array[Dictionary] = []
var _contact_payload: Dictionary = {}
var _death_payload: Dictionary = {}
var _contact_health_before := -1.0
var _contact_defeated_before := true
var _death_was_inactive := false
var _death_was_inert := false
var _death_reward_xp_before := -1
var _death_reward_supply_before := -1
var _legacy_reward_xp_after := -1
var _legacy_reward_supply_after := -1
var _contact_signal_count := 0
var _reentrant_damage_accepted := true
var _reentrant_reward_duplicate: StringName = &""
var _reentrant_reward_collision: StringName = &""


func before_test() -> void:
	_trace.clear()
	_weapon_payloads.clear()
	_contact_payload.clear()
	_death_payload.clear()
	_contact_health_before = -1.0
	_contact_defeated_before = true
	_death_was_inactive = false
	_death_was_inert = false
	_death_reward_xp_before = -1
	_death_reward_supply_before = -1
	_legacy_reward_xp_after = -1
	_legacy_reward_supply_after = -1
	_contact_signal_count = 0
	_reentrant_damage_accepted = true
	_reentrant_reward_duplicate = &""
	_reentrant_reward_collision = &""


func test_runtime_ids_are_session_monotonic_across_world_replacement() -> void:
	var session := _session_with_player()
	var first_world := auto_free(CombatWorld.new()) as CombatWorld
	var second_world := auto_free(CombatWorld.new()) as CombatWorld
	first_world.session = session
	second_world.session = session

	assert_int(session.allocate_runtime_instance_id(&"invalid")).is_equal(0)
	assert_int(first_world.allocate_runtime_instance_id(&"weapon")).is_equal(1)
	assert_int(first_world.allocate_runtime_instance_id(&"projectile")).is_equal(2)
	assert_int(second_world.allocate_runtime_instance_id(&"enemy")).is_equal(3)
	assert_int(first_world.allocate_runtime_instance_id(&"pickup")).is_equal(4)
	assert_int(GameSession.new().allocate_runtime_instance_id(&"weapon")).is_equal(1)

	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = first_world
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var stats := _ranged_stats(1)
	weapon.configure(stats, owner)
	var first_activation_id := weapon.runtime_instance_id
	weapon.shot_sequence = 9
	weapon.projectile_sequence = 12
	weapon.melee_sequence = 7
	weapon.configure(stats, owner)
	assert_int(first_activation_id).is_equal(5)
	assert_int(weapon.runtime_instance_id).is_equal(6)
	assert_int(weapon.shot_sequence).is_equal(0)
	assert_int(weapon.projectile_sequence).is_equal(0)
	assert_int(weapon.melee_sequence).is_equal(0)


func test_canonical_signal_signatures_are_exact_v2() -> void:
	var weapon := auto_free(GogoWeaponInstance.new()) as GogoWeaponInstance
	var projectile := auto_free(GogoProjectile.new()) as GogoProjectile
	var enemy := auto_free(GogoEnemyActor.new()) as GogoEnemyActor
	var world := auto_free(CombatWorld.new()) as CombatWorld

	assert_array(_signal_argument_names(world, &"hud_snapshot_changed")).is_equal(["snapshot"])
	assert_array(_signal_argument_types(world, &"hud_snapshot_changed")).is_equal([TYPE_OBJECT])
	assert_array(_signal_argument_names(world, &"hud_changed")).is_equal([
		"health", "max_health", "time_left", "wave",
	])
	assert_array(_signal_argument_types(world, &"hud_changed")).is_equal([
		TYPE_FLOAT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT,
	])

	assert_array(_signal_argument_names(weapon, &"weapon_fired")).is_equal([
		"weapon_instance_id", "feedback_profile_id", "integer_muzzle_global_position",
		"shot_direction", "projectile_count", "shot_sequence",
	])
	assert_array(_signal_argument_types(weapon, &"weapon_fired")).is_equal([
		TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I, TYPE_VECTOR2, TYPE_INT, TYPE_INT,
	])
	assert_array(_signal_argument_names(weapon, &"melee_contact")).is_equal([
		"weapon_instance_id", "target_instance_id", "feedback_profile_id",
		"integer_contact_global_position", "contact_normal", "damage_kind",
		"impact_kind", "melee_sequence",
	])
	assert_array(_signal_argument_types(weapon, &"melee_contact")).is_equal([
		TYPE_INT, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I, TYPE_VECTOR2,
		TYPE_STRING_NAME, TYPE_STRING_NAME, TYPE_INT,
	])
	assert_array(_signal_argument_names(projectile, &"projectile_contact")).is_equal([
		"projectile_instance_id", "target_instance_id", "feedback_profile_id",
		"integer_contact_global_position", "contact_normal", "damage_kind",
		"impact_kind", "contact_sequence",
	])
	assert_array(_signal_argument_types(projectile, &"projectile_contact")).is_equal([
		TYPE_INT, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR2I, TYPE_VECTOR2,
		TYPE_STRING_NAME, TYPE_STRING_NAME, TYPE_INT,
	])
	assert_array(_signal_argument_names(enemy, &"enemy_defeated")).is_equal([
		"enemy_instance_id", "integer_death_global_position", "xp", "materials", "death_sequence",
	])
	assert_array(_signal_argument_types(enemy, &"enemy_defeated")).is_equal([
		TYPE_INT, TYPE_VECTOR2I, TYPE_INT, TYPE_INT, TYPE_INT,
	])

	for kind in GogoProjectile.VALID_IMPACT_KINDS:
		projectile.activate(null, 0, 0, 0, 0, &"rifle", &"ballistic", kind)
		assert_str(String(projectile.impact_kind)).is_equal(String(kind))
	projectile.activate(null, 0, 0, 0, 0, &"rifle", &"ballistic", &"conflicting_flags")
	assert_str(String(projectile.impact_kind)).is_equal("normal")


func test_world_publishes_typed_and_legacy_hud_values_from_one_immutable_snapshot() -> void:
	var session := _session_with_player()
	var player := session.run_state.player()
	player.current_health = 13.0
	player.max_health = 21.0
	player.level = 4
	player.xp = 12
	player.xp_to_next_level = 45
	player.materials = 88
	player.weapon_ids.assign([&"w1", &"w2"])
	player.item_ids.assign([&"i1"])
	var world := auto_free(CombatWorld.new()) as CombatWorld
	world.session = session
	world.wave_runtime.elapsed = 2.5
	var captured: Dictionary = {"snapshot": null, "legacy": []}
	world.hud_snapshot_changed.connect(func(snapshot: GogoCombatHudSnapshot) -> void:
		captured["snapshot"] = snapshot
	)
	world.hud_changed.connect(func(health: float, maximum: float, seconds: float, wave: int) -> void:
		captured["legacy"] = [health, maximum, seconds, wave]
	)
	world.call("_emit_hud_snapshot", 9.25)

	var snapshot := captured["snapshot"] as GogoCombatHudSnapshot
	assert_object(snapshot).is_not_null()
	assert_float(snapshot.health).is_equal_approx(13.0, 0.0001)
	assert_float(snapshot.maximum_health).is_equal_approx(21.0, 0.0001)
	assert_float(snapshot.seconds).is_equal_approx(9.25, 0.0001)
	assert_float(snapshot.wave_elapsed).is_equal_approx(2.5, 0.0001)
	assert_int(snapshot.level).is_equal(4)
	assert_int(snapshot.materials).is_equal(88)
	assert_array(captured["legacy"]).is_equal([13.0, 21.0, 9.25, 1])
	player.weapon_ids[0] = &"mutated"
	player.item_ids.clear()
	assert_array(snapshot.weapon_ids).is_equal([&"w1", &"w2"])
	assert_array(snapshot.item_ids).is_equal([&"i1"])


func test_multishot_shares_sequence_and_uses_unique_projectile_ids() -> void:
	var session := _session_with_player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	weapon.configure(_ranged_stats(3), owner)
	weapon.global_position = Vector2(100.4, 100.6)
	weapon.weapon_fired.connect(_on_weapon_fired.bind(world))

	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(3)
	assert_int(weapon._fire_projectiles(Vector2.RIGHT)).is_equal(3)

	assert_int(_weapon_payloads.size()).is_equal(2)
	assert_int(_weapon_payloads[0].shot_sequence).is_equal(1)
	assert_int(_weapon_payloads[1].shot_sequence).is_equal(2)
	assert_int(_weapon_payloads[0].projectile_count).is_equal(3)
	assert_int(_weapon_payloads[0].layer_count_at_emit).is_equal(3)
	assert_int(_weapon_payloads[1].layer_count_at_emit).is_equal(6)
	assert_bool(_weapon_payloads[0].muzzle == _weapon_payloads[1].muzzle).is_true()
	assert_float((_weapon_payloads[0].direction as Vector2).length()).is_equal_approx(1.0, 0.0001)

	var runtime_ids: Array[int] = []
	var local_projectile_sequences: Array[int] = []
	var internal_shot_sequences: Array[int] = []
	for child in world.projectile_layer.get_children():
		var projectile := child as GogoProjectile
		runtime_ids.append(projectile.runtime_instance_id)
		local_projectile_sequences.append(projectile.projectile_sequence)
		internal_shot_sequences.append(projectile.shot_sequence)
	assert_array(runtime_ids).is_equal([2, 3, 4, 5, 6, 7])
	assert_array(local_projectile_sequences).is_equal([1, 2, 3, 4, 5, 6])
	assert_array(internal_shot_sequences).is_equal([1, 1, 1, 2, 2, 2])


func test_lethal_trace_is_weapon_contact_death_reward_then_legacy() -> void:
	var session := _session_with_player()
	var player := session.run_state.players[0]
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	var owner := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	owner.combat_world = world
	var weapon := GogoWeaponInstance.new()
	world.add_child(weapon)
	var stats := _ranged_stats(1)
	stats.damage = 100.0
	stats.projectile_speed = 1000.0
	stats.feedback_profile_id = &"heavy"
	stats.impact_kind = &"critical"
	weapon.configure(stats, owner)
	weapon.weapon_fired.connect(_on_weapon_fired.bind(world))

	var enemy := _enemy_with_runtime_id(world, world.allocate_runtime_instance_id(&"enemy"), 40.0, 1.0, 4, 2)
	enemy.enemy_defeated.connect(_on_enemy_canonical.bind(world, enemy, session))
	enemy.defeated.connect(_on_legacy_defeated.bind(session))
	session.reward_committed.connect(_on_reward_committed)

	weapon._fire_projectiles(Vector2.RIGHT)
	var projectile := world.projectile_layer.get_child(0) as GogoProjectile
	projectile.projectile_contact.connect(_on_projectile_contact.bind(enemy))
	projectile._physics_process(0.1)

	assert_array(_trace).is_equal([
		"weapon_fired", "projectile_contact", "enemy_defeated",
		"reward_experience", "reward_supply", "legacy_defeated",
	])
	assert_float(_contact_health_before).is_equal(1.0)
	assert_bool(_contact_defeated_before).is_false()
	assert_bool(_death_was_inactive).is_true()
	assert_bool(_death_was_inert).is_true()
	assert_int(_death_reward_xp_before).is_equal(0)
	assert_int(_death_reward_supply_before).is_equal(35)
	assert_bool(_reentrant_damage_accepted).is_false()
	assert_str(String(_reentrant_reward_duplicate)).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_str(String(_reentrant_reward_collision)).is_equal(String(GameSession.REWARD_TOKEN_COLLISION))
	assert_int(_legacy_reward_xp_after).is_equal(4)
	assert_int(_legacy_reward_supply_after).is_equal(37)
	assert_int(player.xp).is_equal(4)
	assert_int(player.materials).is_equal(37)
	assert_int(session.committed_reward_count()).is_equal(2)

	assert_int(_contact_payload.projectile_instance_id).is_equal(projectile.runtime_instance_id)
	assert_int(_contact_payload.target_instance_id).is_equal(enemy.runtime_instance_id)
	assert_bool(_contact_payload.position == Vector2i(26, 0)).is_true()
	assert_vector(_contact_payload.normal).is_equal(Vector2.LEFT)
	assert_str(String(_contact_payload.profile)).is_equal("heavy")
	assert_str(String(_contact_payload.damage_kind)).is_equal("ballistic")
	assert_str(String(_contact_payload.impact_kind)).is_equal("critical")
	assert_int(_contact_payload.contact_sequence).is_equal(1)
	assert_int(_death_payload.enemy_instance_id).is_equal(enemy.runtime_instance_id)
	assert_bool(_death_payload.position == Vector2i(40, 0)).is_true()
	assert_int(_death_payload.death_sequence).is_equal(1)
	assert_bool(projectile.active).is_false()
	assert_bool(projectile.is_queued_for_deletion()).is_true()


func test_equal_toi_uses_lower_logical_id_not_registration_order() -> void:
	var session := _session_with_player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	var weapon_id := world.allocate_runtime_instance_id(&"weapon")
	var projectile_id := world.allocate_runtime_instance_id(&"projectile")
	var lower_enemy_id := world.allocate_runtime_instance_id(&"enemy")
	var higher_enemy_id := world.allocate_runtime_instance_id(&"enemy")
	var higher_enemy := _enemy_with_runtime_id(world, higher_enemy_id, 40.0, 100.0, 0, 0)
	var lower_enemy := _enemy_with_runtime_id(world, lower_enemy_id, 40.0, 100.0, 0, 0)
	var projectile := GogoProjectile.new()
	projectile.activate(world, projectile_id, weapon_id, 1, 1, &"rifle", &"ballistic", &"normal")
	projectile.direction = Vector2.RIGHT
	projectile.speed = 1000.0
	projectile.damage = 1.0
	world.projectile_layer.add_child(projectile)
	projectile.projectile_contact.connect(_on_tie_contact)

	projectile._physics_process(0.1)

	assert_float(lower_enemy.current_health).is_equal(99.0)
	assert_float(higher_enemy.current_health).is_equal(100.0)
	assert_int(_contact_payload.target_instance_id).is_equal(lower_enemy_id)
	assert_int(_contact_signal_count).is_equal(1)


func test_invalid_feedback_profile_cannot_publish_orphan_contact() -> void:
	var session := _session_with_player()
	var world := auto_free(CombatWorld.new()) as CombatWorld
	add_child(world)
	world.session = session
	var weapon_id := world.allocate_runtime_instance_id(&"weapon")
	var projectile_id := world.allocate_runtime_instance_id(&"projectile")
	var enemy := _enemy_with_runtime_id(world, world.allocate_runtime_instance_id(&"enemy"), 40.0, 100.0, 0, 0)
	var projectile := GogoProjectile.new()
	projectile.activate(world, projectile_id, weapon_id, 1, 1, &"unknown_profile", &"ballistic", &"normal")
	projectile.direction = Vector2.RIGHT
	projectile.speed = 1000.0
	projectile.damage = 1.0
	world.projectile_layer.add_child(projectile)
	projectile.projectile_contact.connect(_on_tie_contact)

	projectile._physics_process(0.1)

	assert_int(_contact_signal_count).is_equal(0)
	assert_float(enemy.current_health).is_equal(100.0)
	assert_str(String(projectile.feedback_profile_id)).is_empty()
	assert_bool(projectile.active).is_false()


func _session_with_player() -> GameSession:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	var player := SessionPlayerState.new()
	player.player_index = 0
	run_state.players.append(player)
	session.run_state = run_state
	return session


func _ranged_stats(projectile_count: int) -> GogoWeaponRuntimeStats:
	var stats := GogoWeaponRuntimeStats.new()
	stats.mode = GogoWeaponDefinition.Mode.RANGED
	stats.attack_range = 520.0
	stats.cooldown_seconds = 0.42
	stats.projectile_speed = 620.0
	stats.projectile_count = projectile_count
	stats.spread_degrees = 4.0
	stats.damage = 4.0
	stats.knockback = 22.0
	stats.feedback_profile_id = &"rifle"
	stats.damage_kind = &"ballistic"
	stats.impact_kind = &"normal"
	return stats


func _enemy_with_runtime_id(
	world: CombatWorld,
	runtime_id: int,
	x_position: float,
	health: float,
	xp: int,
	materials: int
) -> GogoEnemyActor:
	var definition := GogoEnemyDefinition.new()
	definition.max_health = health
	definition.xp_value = xp
	definition.material_value = materials
	var difficulty := GogoDifficultyDefinition.new()
	var enemy := GogoEnemyActor.new()
	enemy.configure(definition, null, difficulty, world, runtime_id)
	enemy.global_position = Vector2(x_position, 0.0)
	world.enemy_layer.add_child(enemy)
	assert_bool(world.register_active_enemy(enemy)).is_true()
	return enemy


func _signal_argument_names(object: Object, signal_name: StringName) -> Array[String]:
	var result: Array[String] = []
	for signal_info in object.get_signal_list():
		if StringName(signal_info.get("name", "")) != signal_name:
			continue
		for argument in signal_info.get("args", []):
			result.append(String(argument.get("name", "")))
		break
	return result


func _signal_argument_types(object: Object, signal_name: StringName) -> Array[int]:
	var result: Array[int] = []
	for signal_info in object.get_signal_list():
		if StringName(signal_info.get("name", "")) != signal_name:
			continue
		for argument in signal_info.get("args", []):
			result.append(int(argument.get("type", TYPE_NIL)))
		break
	return result


func _on_weapon_fired(
	weapon_instance_id: int,
	feedback_profile_id: StringName,
	integer_muzzle_global_position: Vector2i,
	shot_direction: Vector2,
	projectile_count: int,
	shot_sequence: int,
	world: CombatWorld
) -> void:
	_trace.append("weapon_fired")
	_weapon_payloads.append({
		"weapon_instance_id": weapon_instance_id,
		"profile": feedback_profile_id,
		"muzzle": integer_muzzle_global_position,
		"direction": shot_direction,
		"projectile_count": projectile_count,
		"shot_sequence": shot_sequence,
		"layer_count_at_emit": world.projectile_layer.get_child_count(),
	})


func _on_projectile_contact(
	projectile_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	contact_sequence: int,
	enemy: GogoEnemyActor
) -> void:
	_trace.append("projectile_contact")
	_contact_signal_count += 1
	_contact_health_before = enemy.current_health
	_contact_defeated_before = enemy.defeated_once
	_reentrant_damage_accepted = enemy.take_damage(999.0)
	_contact_payload = {
		"projectile_instance_id": projectile_instance_id,
		"target_instance_id": target_instance_id,
		"profile": feedback_profile_id,
		"position": integer_contact_global_position,
		"normal": contact_normal,
		"damage_kind": damage_kind,
		"impact_kind": impact_kind,
		"contact_sequence": contact_sequence,
	}


func _on_enemy_canonical(
	enemy_instance_id: int,
	integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int,
	world: CombatWorld,
	enemy: GogoEnemyActor,
	session: GameSession
) -> void:
	_trace.append("enemy_defeated")
	_death_was_inactive = not world.is_active_enemy(enemy) and not enemy.is_in_group(&"gogo_enemy")
	_death_was_inert = enemy.defeated_once and enemy.collision_layer == 0 and enemy.collision_mask == 0
	_death_reward_xp_before = session.run_state.players[0].xp
	_death_reward_supply_before = session.run_state.players[0].materials
	var experience_token := CombatWorld.enemy_reward_token(
		enemy_instance_id,
		death_sequence,
		GameSession.REWARD_EXPERIENCE
	)
	_reentrant_reward_duplicate = session.commit_reward_once(
		experience_token,
		GameSession.REWARD_EXPERIENCE,
		xp,
		0
	)
	_reentrant_reward_collision = session.commit_reward_once(
		experience_token,
		GameSession.REWARD_EXPERIENCE,
		xp + 1,
		0
	)
	_death_payload = {
		"enemy_instance_id": enemy_instance_id,
		"position": integer_death_global_position,
		"xp": xp,
		"materials": materials,
		"death_sequence": death_sequence,
	}


func _on_reward_committed(_token: StringName, kind: StringName, _amount: int, _player_index: int) -> void:
	_trace.append("reward_%s" % String(kind))


func _on_legacy_defeated(_enemy: GogoEnemyActor, _xp: int, _materials: int, session: GameSession) -> void:
	_trace.append("legacy_defeated")
	_legacy_reward_xp_after = session.run_state.players[0].xp
	_legacy_reward_supply_after = session.run_state.players[0].materials


func _on_tie_contact(
	_projectile_instance_id: int,
	target_instance_id: int,
	_feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	_contact_normal: Vector2,
	_damage_kind: StringName,
	_impact_kind: StringName,
	_contact_sequence: int
) -> void:
	_contact_signal_count += 1
	_contact_payload["target_instance_id"] = target_instance_id
