extends GdUnitTestSuite


const UPGRADE_SCREEN := preload("res://game/ui/upgrade_screen.gd")

const LEGACY_UPGRADES := [
	{
		"id": &"gogobro.core:upgrade/training_1",
		"title": "重甲头盔",
		"icon": &"one_more_round",
		"modifiers": {&"max_health": 2.0},
	},
	{
		"id": &"gogobro.core:upgrade/training_2",
		"title": "轻量战术靴",
		"icon": &"trade_step_drills",
		"modifiers": {&"movement_speed": 18.0},
	},
	{
		"id": &"gogobro.core:upgrade/training_3",
		"title": "爆头靶纸",
		"icon": &"pre_aim_drills",
		"modifiers": {&"damage_multiplier": 0.08},
	},
	{
		"id": &"gogobro.core:upgrade/training_4",
		"title": "经济局硬币弹匣",
		"icon": &"economy_sense",
		"modifiers": {&"pickup_range": 24.0},
	},
	{
		"id": &"gogobro.core:upgrade/training_5",
		"title": "凯夫拉插板组",
		"icon": &"kevlar_reinforcement",
		"modifiers": {&"armor": 1.0},
	},
	{
		"id": &"gogobro.core:upgrade/training_6",
		"title": "医疗针",
		"icon": &"medical_timeout",
		"modifiers": {&"health_regen": 0.6},
	},
]

const NEW_UPGRADES := [
	{
		"id": &"gogobro.core:upgrade/economy_readout",
		"title": "经济训练",
		"icon": &"economy_sense",
		"modifiers": {&"economy": 8.0},
		"rows": ["经济 +8"],
	},
	{
		"id": &"gogobro.core:upgrade/reticle_breathing",
		"title": "暴击训练",
		"icon": &"pre_aim_drills",
		"modifiers": {&"critical_chance": 0.05},
		"rows": ["暴击率 +5%"],
	},
	{
		"id": &"gogobro.core:upgrade/firing_cadence",
		"title": "射击节奏",
		"icon": &"pre_aim_drills",
		"modifiers": {&"attack_speed_multiplier": 0.08},
		"rows": ["攻击速度 +8%"],
	},
	{
		"id": &"gogobro.core:upgrade/ranged_drill",
		"title": "远程训练",
		"icon": &"pre_aim_drills",
		"modifiers": {&"ranged_damage": 1.0},
		"rows": ["远程伤害 +1"],
	},
	{
		"id": &"gogobro.core:upgrade/melee_drill",
		"title": "近战训练",
		"icon": &"trade_step_drills",
		"modifiers": {&"melee_damage": 1.0},
		"rows": ["近战伤害 +1"],
	},
	{
		"id": &"gogobro.core:upgrade/range_gauge",
		"title": "射程训练",
		"icon": &"pre_aim_drills",
		"modifiers": {&"attack_range_bonus": 24.0},
		"rows": ["射程 +24"],
	},
	{
		"id": &"gogobro.core:upgrade/evasive_peek",
		"title": "闪避训练",
		"icon": &"trade_step_drills",
		"modifiers": {&"dodge": 0.04},
		"rows": ["闪避 +4%"],
	},
	{
		"id": &"gogobro.core:upgrade/counter_strafe_drill",
		"title": "急停训练",
		"icon": &"trade_step_drills",
		"modifiers": {&"counter_strafe_brake": 25.0},
		"rows": ["急停制动 +25%"],
	},
	{
		"id": &"gogobro.core:upgrade/running_recoil_control",
		"title": "跑打控枪",
		"icon": &"pre_aim_drills",
		"modifiers": {&"moving_recoil_control": 15.0},
		"rows": ["跑打控枪 +15%"],
	},
	{
		"id": &"gogobro.core:upgrade/field_sutures",
		"title": "战地恢复",
		"icon": &"medical_timeout",
		"modifiers": {&"health_regen": 1.0},
		"rows": ["生命恢复 +1"],
	},
	{
		"id": &"gogobro.core:upgrade/breacher_plate",
		"title": "突破防护",
		"icon": &"kevlar_reinforcement",
		"modifiers": {&"max_health": 1.0, &"armor": 1.0},
		"rows": ["最大生命 +1", "护甲 +1"],
	},
	{
		"id": &"gogobro.core:upgrade/scavenge_route",
		"title": "回收路线",
		"icon": &"trade_step_drills",
		"modifiers": {&"movement_speed_multiplier": 0.04, &"pickup_range": 12.0},
		"rows": ["移动速度 +4%", "拾取范围 +12"],
	},
]

const REGISTERED_UPGRADE_ICONS: Array[StringName] = [
	&"one_more_round",
	&"trade_step_drills",
	&"pre_aim_drills",
	&"economy_sense",
	&"kevlar_reinforcement",
	&"medical_timeout",
]


func test_core_upgrade_catalog_preserves_six_and_adds_exact_twelve_complete_definitions() -> void:
	var snapshot := _snapshot()
	assert_object(snapshot).is_not_null()
	if snapshot == null:
		return
	var upgrades := snapshot.all(&"upgrade")
	assert_int(upgrades.size()).is_equal(18)
	var seen_ids: Dictionary = {}
	for definition: GogoContentDefinition in upgrades:
		assert_bool(definition is GogoUpgradeDefinition).is_true()
		assert_bool(seen_ids.has(definition.content_id)).is_false()
		seen_ids[definition.content_id] = true
	for spec: Dictionary in LEGACY_UPGRADES + NEW_UPGRADES:
		var definition := snapshot.definition(spec["id"], &"upgrade") as GogoUpgradeDefinition
		assert_object(definition).is_not_null()
		if definition == null:
			continue
		assert_str(definition.display_name).is_equal(String(spec["title"]))
		assert_str(String(definition.icon_asset_id)).is_equal(String(spec["icon"]))
		assert_bool(REGISTERED_UPGRADE_ICONS.has(definition.icon_asset_id)).is_true()
		assert_int(definition.tier).is_equal(1)
		_assert_modifier_map(definition.stat_modifiers, spec["modifiers"] as Dictionary)


func test_upgrade_offer_sampling_is_repeatable_distinct_and_reaches_expanded_pool() -> void:
	var session := _session(91001)
	var service := PlayerBuildService.new()
	var added_lookup: Dictionary = {}
	for spec: Dictionary in NEW_UPGRADES:
		added_lookup[spec["id"]] = true
	var saw_added_id := false
	for sample in [[91001, 1, 1, 0], [17, 5, 2, 0], [8821, 12, 1, 1], [44021, 20, 3, 2]]:
		session.run_state.run_seed = int(sample[0])
		session.run_state.current_wave = int(sample[1])
		session.run_state.pending_upgrade_count = int(sample[2])
		session.run_state.upgrade_reroll_count = int(sample[3])
		var first := service.upgrade_reward_offers(session)
		var second := service.upgrade_reward_offers(session)
		var first_ids := _definition_ids(first)
		assert_array(first_ids).is_equal(_definition_ids(second))
		assert_int(first_ids.size()).is_equal(4)
		var unique: Dictionary = {}
		for definition: GogoUpgradeDefinition in first:
			assert_str(String(definition.kind)).is_equal("upgrade")
			unique[definition.content_id] = true
			saw_added_id = saw_added_id or added_lookup.has(definition.content_id)
		assert_int(unique.size()).is_equal(4)
	assert_bool(saw_added_id).is_true()


func test_shop_pool_stays_item_weapon_only_and_content_fingerprint_survives_upgrades() -> void:
	var session := _session(91002)
	var player := session.run_state.player()
	var before := _shop_content_fingerprint(session.content_snapshot)
	assert_int(before.size()).is_equal(92)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	var offers := ItemPoolService.new().generate_shop_offers(
		session.content_snapshot,
		player,
		5,
		4,
		rng
	)
	assert_int(offers.size()).is_equal(4)
	for definition: GogoContentDefinition in offers:
		assert_bool(definition.kind in [&"item", &"weapon"]).is_true()
		assert_bool(String(definition.content_id).begins_with("gogobro.core:upgrade/")).is_false()
	var service := PlayerBuildService.new()
	for spec: Dictionary in NEW_UPGRADES:
		assert_int(service.apply_upgrade(session, player, spec["id"])).is_equal(OK)
	assert_array(_shop_content_fingerprint(session.content_snapshot)).is_equal(before)


func test_each_new_upgrade_applies_exact_increment_and_stacks_without_inventory_mutation() -> void:
	var session := _session(91003)
	var player := session.run_state.player()
	var service := PlayerBuildService.new()
	var item_ids_before := player.item_ids.duplicate()
	var weapon_ids_before := player.weapon_ids.duplicate()
	var watched_keys: Array[StringName] = []
	for spec: Dictionary in NEW_UPGRADES:
		for key: StringName in (spec["modifiers"] as Dictionary).keys():
			if not watched_keys.has(key):
				watched_keys.append(key)
	var expected: Dictionary = {}
	for key: StringName in watched_keys:
		expected[key] = float(player.final_stats.get(key, 0.0))
	for spec: Dictionary in NEW_UPGRADES:
		var upgrade_id := spec["id"] as StringName
		assert_int(service.apply_upgrade(session, player, upgrade_id)).is_equal(OK)
		for key: StringName in (spec["modifiers"] as Dictionary).keys():
			expected[key] = float(expected[key]) + float((spec["modifiers"] as Dictionary)[key])
		for key: StringName in watched_keys:
			assert_float(float(player.final_stats.get(key, 0.0))).is_equal_approx(
				float(expected[key]),
				0.0001
			)
		assert_int(player.upgrade_ids.count(upgrade_id)).is_equal(1)
		assert_array(player.item_ids).is_equal(item_ids_before)
		assert_array(player.weapon_ids).is_equal(weapon_ids_before)
	var ranged_before := float(player.final_stats.get(&"ranged_damage", 0.0))
	assert_int(service.apply_upgrade(
		session,
		player,
		&"gogobro.core:upgrade/ranged_drill"
	)).is_equal(OK)
	assert_int(player.upgrade_ids.count(&"gogobro.core:upgrade/ranged_drill")).is_equal(2)
	assert_float(float(player.final_stats.get(&"ranged_damage", 0.0))).is_equal_approx(
		ranged_before + 1.0,
		0.0001
	)


func test_new_upgrades_reach_regen_economy_and_weapon_runtime_consumers() -> void:
	var regen_session := _session(91004)
	var regen_player := regen_session.run_state.player()
	var service := PlayerBuildService.new()
	assert_int(service.apply_upgrade(
		regen_session,
		regen_player,
		&"gogobro.core:upgrade/field_sutures"
	)).is_equal(OK)
	assert_float(float(regen_player.final_stats.get(&"health_regen", 0.0))).is_equal(1.0)
	assert_float(GogoCombatStatRuntime.health_regen_interval_seconds(1.0)).is_equal_approx(5.0, 0.0001)
	var actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	actor.player_state = regen_player
	regen_player.current_health = regen_player.max_health - 2.0
	assert_float(actor.tick_health_regeneration(4.99)).is_zero()
	assert_float(actor.tick_health_regeneration(0.01)).is_equal(1.0)

	var economy_session := _session(91005)
	var economy_player := economy_session.run_state.player()
	assert_int(service.apply_upgrade(
		economy_session,
		economy_player,
		&"gogobro.core:upgrade/economy_readout"
	)).is_equal(OK)
	var materials_before := economy_player.materials
	var granted := 0
	for _index in 13:
		granted += economy_player.add_reward_materials(1)
	assert_int(granted).is_equal(14)
	assert_int(economy_player.materials).is_equal(materials_before + 14)
	assert_float(economy_player.economy_material_remainder).is_equal_approx(0.04, 0.0001)

	var weapon_session := _session(91006)
	var weapon_player := weapon_session.run_state.player()
	var weapon_runtime := WeaponRuntimeService.new()
	var ranged_definition := weapon_session.content_snapshot.definition(
		ValidationContentFactory.RANGED_ID,
		&"weapon"
	) as GogoWeaponDefinition
	var melee_definition := weapon_session.content_snapshot.definition(
		ValidationContentFactory.MELEE_ID,
		&"weapon"
	) as GogoWeaponDefinition
	var ranged_before := weapon_runtime.build_instance(ranged_definition, weapon_player)
	var melee_before := weapon_runtime.build_instance(melee_definition, weapon_player)
	for upgrade_id: StringName in [
		&"gogobro.core:upgrade/ranged_drill",
		&"gogobro.core:upgrade/melee_drill",
		&"gogobro.core:upgrade/firing_cadence",
		&"gogobro.core:upgrade/range_gauge",
		&"gogobro.core:upgrade/reticle_breathing",
	]:
		assert_int(service.apply_upgrade(weapon_session, weapon_player, upgrade_id)).is_equal(OK)
	var ranged_after := weapon_runtime.build_instance(ranged_definition, weapon_player)
	var melee_after := weapon_runtime.build_instance(melee_definition, weapon_player)
	assert_float(ranged_after.damage).is_equal_approx(ranged_before.damage + 1.0, 0.0001)
	assert_float(melee_after.damage).is_equal_approx(melee_before.damage + 1.0, 0.0001)
	assert_float(ranged_after.cooldown_seconds).is_equal_approx(
		ranged_before.cooldown_seconds / 1.08,
		0.0001
	)
	assert_float(melee_after.cooldown_seconds).is_equal_approx(
		melee_before.cooldown_seconds / 1.08,
		0.0001
	)
	assert_float(ranged_after.attack_range).is_equal_approx(ranged_before.attack_range + 24.0, 0.0001)
	assert_float(melee_after.attack_range).is_equal_approx(melee_before.attack_range + 24.0, 0.0001)
	assert_float(ranged_after.critical_chance).is_equal_approx(0.05, 0.0001)


func test_crit_dodge_movement_braking_recoil_and_pickup_caps_use_existing_consumers() -> void:
	var session := _session(91007)
	var player := session.run_state.player()
	var service := PlayerBuildService.new()
	for _index in 25:
		assert_int(service.apply_upgrade(
			session,
			player,
			&"gogobro.core:upgrade/reticle_breathing"
		)).is_equal(OK)
	for _index in 20:
		assert_int(service.apply_upgrade(
			session,
			player,
			&"gogobro.core:upgrade/evasive_peek"
		)).is_equal(OK)
	for upgrade_id: StringName in [
		&"gogobro.core:upgrade/counter_strafe_drill",
		&"gogobro.core:upgrade/running_recoil_control",
		&"gogobro.core:upgrade/scavenge_route",
	]:
		assert_int(service.apply_upgrade(session, player, upgrade_id)).is_equal(OK)
	assert_float(float(player.final_stats.get(&"critical_chance", 0.0))).is_equal(1.0)
	assert_float(float(player.final_stats.get(&"dodge", 0.0))).is_equal(0.6)
	assert_float(float(player.final_stats.get(&"movement_speed", 0.0))).is_equal_approx(312.0, 0.0001)
	assert_float(float(player.final_stats.get(&"pickup_range", 0.0))).is_equal_approx(127.0, 0.0001)
	var ordinary_stop := GogoMovementCombatRuntime.move_toward_velocity(
		Vector2(100.0, 0.0), Vector2.ZERO, 312.0, 1.0 / 60.0, 0.0
	)
	var improved_stop := GogoMovementCombatRuntime.move_toward_velocity(
		Vector2(100.0, 0.0), Vector2.ZERO, 312.0, 1.0 / 60.0, 25.0
	)
	assert_float(improved_stop.length()).is_less(ordinary_stop.length())
	var ordinary_forward := GogoMovementCombatRuntime.move_toward_velocity(
		Vector2.ZERO, Vector2.RIGHT, 312.0, 0.05, 0.0
	)
	var improved_forward := GogoMovementCombatRuntime.move_toward_velocity(
		Vector2.ZERO, Vector2.RIGHT, 312.0, 0.05, 25.0
	)
	assert_vector(improved_forward).is_equal_approx(ordinary_forward, Vector2(0.0001, 0.0001))
	var ordinary_penalty := GogoMovementCombatRuntime.ranged_movement_penalty(Vector2(235.0, 0.0), 0.0)
	var improved_penalty := GogoMovementCombatRuntime.ranged_movement_penalty(Vector2(235.0, 0.0), 15.0)
	assert_float(float(improved_penalty[&"spread_degrees"])).is_less(
		float(ordinary_penalty[&"spread_degrees"])
	)
	assert_float(float(improved_penalty[&"recoil_multiplier"])).is_less(
		float(ordinary_penalty[&"recoil_multiplier"])
	)
	var baseline_session := _session(91008)
	var baseline_actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	baseline_actor.player_state = baseline_session.run_state.player()
	var baseline_pickup := auto_free(GogoCombatPickup.new()) as GogoCombatPickup
	baseline_pickup.target = baseline_actor
	baseline_pickup.global_position = Vector2(121.0, 0.0)
	baseline_pickup.call(&"_physics_process", 0.0)
	assert_int(baseline_pickup.state).is_equal(GogoCombatPickup.DROPPED)
	var upgraded_actor := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	upgraded_actor.player_state = player
	assert_float(upgraded_actor.pickup_interaction_radius()).is_equal(
		baseline_actor.pickup_interaction_radius()
	)
	var upgraded_pickup := auto_free(GogoCombatPickup.new()) as GogoCombatPickup
	upgraded_pickup.target = upgraded_actor
	upgraded_pickup.global_position = Vector2(121.0, 0.0)
	upgraded_pickup.call(&"_physics_process", 0.0)
	assert_int(upgraded_pickup.state).is_equal(GogoCombatPickup.MAGNETIZING)


func test_actual_upgrade_cards_have_complete_rows_and_correct_point_percent_units() -> void:
	var snapshot := _snapshot()
	assert_object(snapshot).is_not_null()
	if snapshot == null:
		return
	var screen := auto_free(UPGRADE_SCREEN.new()) as GogoScreenBase
	for spec: Dictionary in NEW_UPGRADES:
		var definition := snapshot.definition(spec["id"], &"upgrade") as GogoUpgradeDefinition
		assert_object(definition).is_not_null()
		if definition == null:
			continue
		var rows := GogoStaticCardPresenter.localized_stat_rows(definition)
		var expected_rows := spec["rows"] as Array
		assert_int(rows.size()).is_equal(expected_rows.size())
		for index in expected_rows.size():
			assert_str(String(rows[index].get("text", ""))).is_equal(String(expected_rows[index]))
		var card := auto_free(GogoStaticCardPresenter.build_card(
			definition,
			"选择",
			null
		)) as Button
		screen.call(&"_configure_choice_card", card)
		add_child(card)
		await get_tree().process_frame
		var stat_rows := card.get_node("StatRows") as VBoxContainer
		assert_vector(stat_rows.size).is_equal_approx(Vector2(200.0, 38.0), Vector2(0.01, 0.01))
		assert_int(stat_rows.get_child_count()).is_equal(2)
		for index in expected_rows.size():
			var label := stat_rows.get_node("Stat%d/Text" % (index + 1)) as Label
			var icon := stat_rows.get_node("Stat%d/Icon" % (index + 1)) as TextureRect
			assert_str(label.text).is_equal(String(expected_rows[index]))
			assert_object(icon.texture).is_not_null()
			assert_bool(icon.visible).is_true()
			var row := label.get_parent() as HBoxContainer
			assert_bool(
				row.position.y + label.position.y + label.size.y <= stat_rows.size.y + 0.01
			).is_true()
			assert_str(card.tooltip_text).contains(String(expected_rows[index]))
	assert_str(_row_text(snapshot, &"gogobro.core:upgrade/counter_strafe_drill")).is_equal(
		"急停制动 +25%"
	)
	assert_str(_row_text(snapshot, &"gogobro.core:upgrade/counter_strafe_drill")).not_contains(
		"2500%"
	)
	assert_str(_row_text(snapshot, &"gogobro.core:upgrade/running_recoil_control")).is_equal(
		"跑打控枪 +15%"
	)
	assert_str(_row_text(snapshot, &"gogobro.core:upgrade/running_recoil_control")).not_contains(
		"1500%"
	)


func _snapshot() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _session(seed: int) -> GameSession:
	var config := SessionConfig.new()
	config.seed = seed
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	assert_int(session.start(config, _snapshot())).is_equal(OK)
	return session


func _assert_modifier_map(actual: Dictionary, expected: Dictionary) -> void:
	assert_int(actual.size()).is_equal(expected.size())
	for key: StringName in expected.keys():
		assert_bool(actual.has(key)).is_true()
		assert_float(float(actual.get(key, 0.0))).is_equal_approx(float(expected[key]), 0.0001)


func _definition_ids(definitions: Array[GogoUpgradeDefinition]) -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: GogoUpgradeDefinition in definitions:
		result.append(definition.content_id)
	return result


func _shop_content_fingerprint(snapshot: ContentSnapshot) -> Array[String]:
	var result: Array[String] = []
	for kind: StringName in [&"item", &"weapon"]:
		for definition: GogoContentDefinition in snapshot.all(kind):
			var fields: Array[String] = [
				String(definition.content_id),
				definition.display_name,
				String(definition.icon_asset_id),
				String(definition.kind),
			]
			if definition is GogoItemDefinition:
				var item := definition as GogoItemDefinition
				fields.append_array([
					str(item.tier), str(item.price), str(item.max_count),
					_canonical_string_names(item.owner_character_ids),
					_canonical_modifiers(item.stat_modifiers),
				])
			elif definition is GogoWeaponDefinition:
				var weapon := definition as GogoWeaponDefinition
				fields.append_array([
					str(weapon.tier), str(weapon.price), str(weapon.mode),
					str(weapon.damage), str(weapon.cooldown_seconds),
					str(weapon.attack_range), str(weapon.projectile_speed),
					str(weapon.projectile_count), str(weapon.spread_degrees),
					str(weapon.knockback), String(weapon.feedback_profile_id),
					String(weapon.damage_kind), String(weapon.impact_kind),
				])
			result.append("|".join(fields))
	result.sort()
	return result


func _canonical_modifiers(modifiers: Dictionary) -> String:
	var keys: Array[String] = []
	for key: Variant in modifiers.keys():
		keys.append(String(key))
	keys.sort()
	var result: Array[String] = []
	for key_text: String in keys:
		result.append("%s=%s" % [key_text, str(float(modifiers.get(StringName(key_text), 0.0)))])
	return ",".join(result)


func _canonical_string_names(values: Array[StringName]) -> String:
	var strings: Array[String] = []
	for value: StringName in values:
		strings.append(String(value))
	strings.sort()
	return ",".join(strings)


func _row_text(snapshot: ContentSnapshot, upgrade_id: StringName) -> String:
	var definition := snapshot.definition(upgrade_id, &"upgrade") as GogoUpgradeDefinition
	var rows := GogoStaticCardPresenter.localized_stat_rows(definition)
	return String(rows[0].get("text", "")) if not rows.is_empty() else ""
