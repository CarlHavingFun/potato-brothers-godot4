extends GdUnitTestSuite


const DEFAULT_PACK_PATH := "res://content_packs/default/pack.tres"


func test_baseline_profile_has_strict_content_and_economy_coverage() -> void:
	var pack := load(DEFAULT_PACK_PATH) as ContentPackDef
	var balance_pack := BalanceProfileRegistry.load_active(pack)

	assert_object(balance_pack).is_not_null()
	assert_str(balance_pack.balance_pack_id).is_equal("baseline_parity_1_1_15_4")
	assert_int(balance_pack.manifest.character_ids.size()).is_equal(12)
	assert_int(balance_pack.manifest.weapon_ids.size()).is_equal(24)
	assert_int(balance_pack.manifest.passive_ids.size()).is_equal(60)
	assert_int(balance_pack.manifest.upgrade_ids.size()).is_equal(64)
	assert_int(balance_pack.manifest.regular_enemy_ids.size()).is_equal(18)
	assert_int(balance_pack.manifest.elite_enemy_ids.size()).is_equal(2)
	assert_int(balance_pack.manifest.boss_enemy_ids.size()).is_equal(2)
	assert_int(balance_pack.manifest.wave_ids.size()).is_equal(20)
	assert_array(ContentValidator.new().validate_balance_parity(pack, balance_pack)).is_empty()
	assert_int(balance_pack.maximum_active_enemies).is_equal(100)
	assert_float(balance_pack.wave_duration(1)).is_equal(20.0)
	assert_float(balance_pack.wave_duration(20)).is_equal(90.0)
	assert_float(balance_pack.material_drop_multiplier(4)).is_equal(1.0)
	assert_float(balance_pack.material_drop_multiplier(5)).is_equal_approx(0.925, 0.0001)
	assert_float(balance_pack.material_drop_multiplier(100)).is_equal(0.5)
	assert_array(balance_pack.event_windows_for_difficulty(1)).is_empty()
	assert_array(balance_pack.event_windows_for_difficulty(5)).is_equal([
		Vector2i(11, 12), Vector2i(14, 15), Vector2i(17, 18),
	])
	assert_int(balance_pack.final_boss_count(5)).is_equal(2)


func test_neutral_baseline_tables_are_applied_to_runtime_content() -> void:
	var pack := load(DEFAULT_PACK_PATH) as ContentPackDef
	var balance_pack := BalanceProfileRegistry.load_active(pack)
	var shotgun := pack.weapons.filter(
		func(candidate: WeaponDef): return candidate.content_id == &"weapon/shotgun"
	)[0] as WeaponDef
	var arc_lens := pack.passives.filter(
		func(candidate: PassiveItemDef): return candidate.content_id == &"passive/arc_lens"
	)[0] as PassiveItemDef
	var final_boss := pack.enemies.filter(
		func(candidate: EnemyDef): return candidate.content_id == &"enemy/mouse_dog"
	)[0] as EnemyDef

	assert_object(balance_pack).is_not_null()
	assert_float(shotgun.tiers[0].stats.damage).is_equal(3.0)
	assert_float(shotgun.tiers[0].stats.cooldown).is_equal_approx(1.37, 0.0001)
	assert_int(shotgun.tiers[0].stats.projectile_count).is_equal(4)
	assert_int(shotgun.tiers[3].stats.projectile_count).is_equal(6)
	assert_int(shotgun.tiers[0].item_cost).is_equal(20)
	assert_float(arc_lens.stat_modifiers.get("ranged_damage", 0.0)).is_equal(1.0)
	assert_float(arc_lens.stat_modifiers.get("range", 0.0)).is_equal(-5.0)
	assert_int(arc_lens.item.item_cost).is_equal(20)
	assert_int(final_boss.stats.health).is_equal(29250)


func test_balance_ids_are_neutral_stable_links_and_character_gaps_are_explicit() -> void:
	var pack := load(DEFAULT_PACK_PATH) as ContentPackDef
	var balance_pack := BalanceProfileRegistry.load_active(pack)
	var character := pack.characters.filter(
		func(candidate: CharacterDef): return candidate.content_id == &"character/glass_cannon"
	)[0] as CharacterDef

	assert_str(character.get_balance_id(pack.pack_id)).is_equal(
		"core:character/glass_cannon"
	)
	assert_float(character.rules.starting_stat_modifiers.get("attack_speed", 0.0)).is_equal(200.0)
	assert_int(character.rules.weapon_slot_limit).is_equal(1)
	assert_bool(character.rules.runtime_support.get("stat_modification_multipliers", false)).is_true()
	var gaps := ContentValidator.new().balance_runtime_gaps(balance_pack)
	var has_explicit_gap := false
	for gap: String in gaps:
		if "runtime_supported=false" in gap:
			has_explicit_gap = true
			break
	assert_bool(has_explicit_gap).is_true()


func test_reference_tables_are_applied_to_runtime_content_by_neutral_id() -> void:
	var pack := load(DEFAULT_PACK_PATH) as ContentPackDef
	var balance_pack := BalanceProfileRegistry.load_active(pack)

	assert_int(balance_pack.weapon_values.size()).is_equal(24)
	assert_int(balance_pack.passive_values.size()).is_equal(60)
	assert_int(balance_pack.enemy_values.size()).is_equal(22)

	var weapon := pack.weapons.filter(
		func(candidate: WeaponDef):
			return candidate.get_balance_id(pack.pack_id) == &"core:weapon/shotgun"
	)[0] as WeaponDef
	assert_float(weapon.tiers[3].stats.damage).is_equal(9.0)
	assert_float(weapon.tiers[3].stats.cooldown).is_equal(1.2)
	assert_int(weapon.tiers[3].stats.projectile_count).is_equal(6)

	var passive := pack.passives.filter(
		func(candidate: PassiveItemDef):
			return candidate.get_balance_id(pack.pack_id) == &"core:passive/coffee"
	)[0] as PassiveItemDef
	assert_float(passive.stat_modifiers.get("attack_speed", 0.0)).is_equal(10.0)
	assert_float(passive.stat_modifiers.get("damage", 0.0)).is_equal(-2.0)
	assert_int(passive.item.item_cost).is_equal(20)

	var enemy := pack.enemies.filter(
		func(candidate: EnemyDef):
			return candidate.get_balance_id(pack.pack_id) == &"core:enemy/shooter"
	)[0] as EnemyDef
	assert_int(enemy.stats.health).is_equal(8)
	assert_float(enemy.stats.health_increase_per_wave).is_equal(1.0)
	assert_int(enemy.stats.speed).is_equal(200)


func test_run_state_versions_new_runs_and_preserves_legacy_rebuild_inputs() -> void:
	var current := RunState.new(12)
	assert_str(current.stat_rules_version).is_equal(StatRulesDef.CURRENT_VERSION)
	assert_str(current.balance_pack_version).is_equal(BalancePackDef.BASELINE_VERSION)
	assert_bool(current.requires_stat_rebuild()).is_false()

	var legacy := RunState.from_dict({
		"character_id": "core:character/well_rounded",
		"starting_weapon_id": "core:weapon/pistol",
		"player_stats": {"damage": 19.0, "range": 10.0},
		"inventory": {},
	})
	assert_bool(legacy.requires_stat_rebuild()).is_true()
	assert_float(legacy.stat_rebuild_source.get("legacy_player_stats", {}).get(
		"damage", 0.0
	)).is_equal(19.0)
	assert_bool(legacy.mark_stats_rebuilt(PlayerStats.new({StatId.DAMAGE: 7.0}))).is_true()
	assert_bool(legacy.requires_stat_rebuild()).is_false()
	assert_bool(legacy.stat_rebuild_source.is_empty()).is_true()
	assert_float(legacy.player_stats.get_stat(StatId.DAMAGE)).is_equal(7.0)


func test_stat_rebuild_service_preserves_v3_and_rebuilds_versioned_ledgers() -> void:
	var pack := load(DEFAULT_PACK_PATH) as ContentPackDef
	var balance_pack := BalanceProfileRegistry.load_active(pack)
	var catalog := ContentCatalog.new()
	assert_int(catalog.register_pack(pack, balance_pack)).is_equal(OK)
	var service := StatRebuildService.new()

	var legacy := RunState.from_dict({
		"character_id": "core:character/well_rounded",
		"player_stats": {"damage": 19.0, "range": 10.0},
		"inventory": {},
	})
	assert_bool(service.rebuild_if_required(legacy, catalog, balance_pack)).is_true()
	assert_float(legacy.player_stats.get_stat(StatId.DAMAGE)).is_equal(19.0)
	assert_str(legacy.stat_rules_version).is_equal(balance_pack.stat_rules.rules_version)
	assert_str(legacy.balance_pack_version).is_equal(balance_pack.balance_pack_version)

	var versioned := RunState.new(9, PlayerStats.new({StatId.DAMAGE: 999.0}))
	versioned.character_id = &"core:character/well_rounded"
	versioned.inventory.add_passive(&"core:passive/coffee")
	versioned.record_applied_upgrade(
		&"core:upgrade/ranged_damage/common",
		StatId.RANGED_DAMAGE,
		2.0
	)
	versioned.stat_rules_version = "previous_rules"
	versioned.balance_pack_version = "previous_balance"

	assert_bool(service.rebuild_if_required(versioned, catalog, balance_pack)).is_true()
	assert_float(versioned.player_stats.get_stat(StatId.MAX_HEALTH)).is_equal(15.0)
	assert_float(versioned.player_stats.get_stat(StatId.MOVE_SPEED)).is_equal(5.0)
	assert_float(versioned.player_stats.get_stat(StatId.HARVESTING)).is_equal(8.0)
	assert_float(versioned.player_stats.get_stat(StatId.ATTACK_SPEED)).is_equal(10.0)
	assert_float(versioned.player_stats.get_stat(StatId.DAMAGE)).is_equal(-2.0)
	assert_float(versioned.player_stats.get_stat(StatId.RANGED_DAMAGE)).is_equal(2.0)

	var scaled := RunState.new(10)
	scaled.character_id = &"core:character/glass_cannon"
	scaled.inventory.add_passive(&"core:passive/coffee")
	scaled.stat_rules_version = "previous_rules"
	scaled.balance_pack_version = "previous_balance"
	assert_bool(service.rebuild_if_required(scaled, catalog, balance_pack)).is_true()
	assert_float(scaled.player_stats.get_stat(StatId.ATTACK_SPEED)).is_equal(210.0)
	assert_float(scaled.player_stats.get_stat(StatId.DAMAGE)).is_equal(-4.0)
