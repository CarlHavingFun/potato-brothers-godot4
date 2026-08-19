extends GdUnitTestSuite


const DEFAULT_PACK_PATH := "res://content_packs/default/pack.tres"


func after_test() -> void:
	Global.end_run()


func test_character_runtime_values_apply_and_survive_checkpoint_round_trip() -> void:
	var rule := CharacterRuleDef.new()
	rule.rule_id = &"character_rule/test"
	rule.allowed_weapon_tags = [&"precise"] as Array[StringName]
	rule.forbidden_weapon_tags = [&"melee"] as Array[StringName]
	rule.shop_price_multiplier = 0.75
	rule.recycle_value_multiplier = 1.25
	rule.experience_gain_multiplier = 0.5
	rule.dodge_cap_override = 90.0
	rule.consumable_healing_bonus = 3.0
	rule.materials_reset_on_wave_start = true
	var run := RunState.new(501)

	assert_bool(rule.apply_to_run(run)).is_true()
	var restored := RunState.from_dict(run.to_dict())

	assert_float(restored.shop_price_multiplier).is_equal(0.75)
	assert_float(restored.recycle_value_multiplier).is_equal(1.25)
	assert_float(restored.experience_gain_multiplier).is_equal(0.5)
	assert_float(restored.dodge_cap_override).is_equal(90.0)
	assert_float(restored.consumable_healing_bonus).is_equal(3.0)
	assert_bool(restored.materials_reset_on_wave_start).is_true()
	assert_array(restored.allowed_weapon_tags).contains_exactly([&"precise"])
	assert_array(restored.forbidden_weapon_tags).contains_exactly([&"melee"])
	assert_bool(restored.allows_weapon_tags([&"ranged", &"precise"])).is_true()
	assert_bool(restored.allows_weapon_tags([&"melee", &"precise"])).is_false()


func test_character_economy_and_experience_multipliers_affect_transactions() -> void:
	var run := RunState.new(502)
	run.shop_price_multiplier = 0.75
	run.recycle_value_multiplier = 1.25
	run.experience_gain_multiplier = 0.5
	run.materials = 100
	var pistol := Content.catalog.get_weapon(&"weapon/pistol").tiers[0]
	var shop := ShopService.new(502)
	var rewards := RewardService.new(502)

	assert_int(shop.purchase_price(run, pistol)).is_equal(ceili(pistol.item_cost * 0.75))
	assert_int(shop.refresh_price_for_run(run, 4)).is_equal(ceili(6.0 * 0.75))
	run.queued_rewards = 1
	assert_int(rewards.recycle_item(run, pistol)).is_equal(
		maxi(1, floori(pistol.item_cost * 0.5 * 1.25))
	)
	var materials_before_sale := run.materials
	run.inventory.add_weapon(&"core:weapon/pistol", 1, 20)
	assert_int(InventoryService.try_sell_weapon(run, 0)).is_equal(InventoryService.OK)
	assert_int(run.materials - materials_before_sale).is_equal(floori(20.0 * 0.75 * 1.25))

	assert_int(rewards.add_experience(run, 1)).is_zero()
	assert_float(run.experience_gain_remainder).is_equal(0.5)
	var restored := RunState.from_dict(run.to_dict())
	assert_float(restored.experience_gain_remainder).is_equal(0.5)
	assert_int(rewards.add_experience(restored, 1)).is_zero()
	assert_int(restored.experience).is_equal(1)
	assert_float(restored.experience_gain_remainder).is_zero()


func test_wave_reset_consumable_healing_and_dodge_override_are_runtime_rules() -> void:
	var run := RunState.new(503)
	run.materials = 37
	run.materials_reset_on_wave_start = true
	run.consumable_healing_bonus = 3.0
	run.pickup_healing_multiplier = 1.5
	var stats := PlayerStats.new({StatId.DODGE: 90.0})
	var resolver := CombatResolver.new(503)

	assert_float(EcologyPickup.healing_amount_for_run(8.0, run)).is_equal(15.0)
	assert_float(resolver.dodge_chance(stats)).is_equal(0.6)
	assert_float(resolver.dodge_chance(stats, run.dodge_cap_override)).is_equal(0.6)
	run.dodge_cap_override = 90.0
	assert_float(resolver.dodge_chance(stats, run.dodge_cap_override)).is_equal(0.9)
	assert_int(run.apply_wave_start_character_rules()).is_equal(37)
	assert_int(run.materials).is_zero()
	assert_int(run.apply_wave_start_character_rules()).is_zero()


func test_player_damage_pipeline_uses_the_run_dodge_cap_override() -> void:
	Global.begin_run(504, null, 0)
	Global.current_run.phase = RunPhase.COMBAT
	Global.current_run.player_stats.set_stat(StatId.DODGE, 100.0)
	Global.current_run.dodge_cap_override = 100.0
	var player: Player = auto_free(load(
		"res://scenes/unit/players/player_well_rounded.tscn"
	).instantiate() as Player) as Player
	add_child(player)
	Global.player = player
	# Choose a deterministic first roll that would fail the ordinary 60% cap but
	# must pass a character-specific 100% cap.
	var selected_seed := 0
	for candidate_seed in 1000:
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate_seed
		if probe.randf() > 0.60:
			selected_seed = candidate_seed
			break
	Global.combat_resolver.rng.seed = selected_seed
	var health_before := player.health_component.current_health

	player.receive_typed_damage(5.0, null, [&"test"] as Array[StringName])

	assert_float(player.health_component.current_health).is_equal(health_before)


func test_baseline_character_restrictions_have_real_nonempty_weapon_families() -> void:
	var pack := ResourceLoader.load(
		DEFAULT_PACK_PATH, "ContentPackDef", ResourceLoader.CACHE_MODE_REPLACE
	) as ContentPackDef
	var balance := BalanceProfileRegistry.load_active(pack)
	var catalog := ContentCatalog.new()
	assert_int(catalog.register_pack(pack, balance)).is_equal(OK)

	var expected_allowed := {
		"character/brawler": "weapon/punch",
		"character/bunny": "weapon/pistol",
		"character/crazy": "weapon/spear",
		"character/dash_raider": "weapon/chainsaw",
	}
	for raw_character_id: Variant in expected_allowed:
		var character := catalog.get_character(StringName(str(raw_character_id)))
		assert_object(character).is_not_null()
		var allowed: Array[WeaponDef] = []
		for starter_id: StringName in character.starter_weapon_ids:
			var weapon := catalog.get_weapon(starter_id)
			if weapon != null and character.rules.allows_weapon(weapon.tags):
				allowed.append(weapon)
		assert_bool(allowed.is_empty()).is_false()
		assert_bool(allowed.any(func(weapon: WeaponDef):
			return String(weapon.content_id) == str(expected_allowed[raw_character_id])
		)).is_true()

	var brawler := catalog.get_character(&"character/brawler")
	var bunny := catalog.get_character(&"character/bunny")
	var crazy := catalog.get_character(&"character/crazy")
	var dash_raider := catalog.get_character(&"character/dash_raider")
	var knight := catalog.get_character(&"character/knight")
	assert_bool(brawler.rules.runtime_support.get("unarmed_only", false)).is_true()
	assert_bool(bunny.rules.runtime_support.get("no_melee_weapons", false)).is_true()
	assert_bool(crazy.rules.runtime_support.get("forced_starting_weapon", false)).is_true()
	assert_bool(dash_raider.rules.runtime_support.get("ethereal_only", false)).is_true()
	assert_bool(knight.rules.runtime_support.get("life_steal_floor", false)).is_true()
	assert_float(knight.rules.starting_stat_modifiers.get("life_steal", 0.0)).is_equal(-100.0)
	var knight_run := RunState.new(509)
	assert_bool(knight.rules.apply_to_run(knight_run)).is_true()
	assert_float(knight_run.player_stats.get_stat(StatId.LIFE_STEAL)).is_equal(-100.0)
	assert_array(catalog.get_weapon(&"weapon/punch").tags).contains([&"burst"])
	assert_array(catalog.get_weapon(&"weapon/chainsaw").tags).contains([&"mobility"])


func test_shop_and_reward_reject_weapons_forbidden_by_the_active_character() -> void:
	var run := RunState.new(505)
	run.forbidden_weapon_tags = [&"melee"] as Array[StringName]
	run.materials = 1000
	var axe := Content.catalog.get_weapon(&"weapon/axe").tiers[0]
	var shop := ShopService.new(505)
	var rewards := RewardService.new(505)

	assert_int(shop.try_purchase(run, axe, Content.catalog)).is_equal(
		InventoryService.INVALID_REQUEST
	)
	run.queued_rewards = 1
	assert_int(rewards.try_claim_item(run, axe, Content.catalog)).is_equal(
		InventoryService.INVALID_REQUEST
	)
	assert_int(run.inventory.weapon_count()).is_zero()
	assert_int(run.queued_rewards).is_equal(1)


func test_selected_run_hydrates_economy_rules_and_rejects_an_illegal_starter() -> void:
	var broker := Content.catalog.get_character(&"character/scrap_broker")
	var bunny := Content.catalog.get_character(&"character/bunny")
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")
	var axe := Content.catalog.get_weapon(&"weapon/axe")

	assert_bool(Global.select_character(broker)).is_true()
	assert_bool(Global.select_starting_weapon(pistol)).is_true()
	assert_bool(Global.begin_selected_run(506)).is_true()
	assert_float(Global.current_run.shop_price_multiplier).is_equal(0.75)
	assert_float(Global.current_run.recycle_value_multiplier).is_equal(1.25)
	assert_bool(Global.current_run.materials_reset_on_wave_start).is_true()
	Global.end_run()

	assert_bool(Global.select_character(bunny)).is_true()
	assert_bool(Global.select_starting_weapon(axe)).is_true()
	assert_bool(Global.begin_selected_run(507)).is_false()
	assert_object(Global.current_run).is_null()


func test_resume_rehydrates_runtime_rules_for_an_older_v4_checkpoint() -> void:
	var checkpoint := RunState.new(508)
	checkpoint.character_id = &"core:character/scrap_broker"
	checkpoint.starting_weapon_id = &"core:weapon/pistol"
	checkpoint.phase = RunPhase.COMBAT
	checkpoint.character_rule_applied = true
	var legacy_v4_data := checkpoint.to_dict()
	for field_name: String in [
		"shop_price_multiplier",
		"recycle_value_multiplier",
		"experience_gain_multiplier",
		"dodge_cap_override",
		"consumable_healing_bonus",
		"materials_reset_on_wave_start",
		"allowed_weapon_tags",
		"forbidden_weapon_tags",
	]:
		legacy_v4_data.erase(field_name)

	assert_bool(Global.resume_run_state(RunState.from_dict(legacy_v4_data))).is_true()
	assert_float(Global.current_run.shop_price_multiplier).is_equal(0.75)
	assert_float(Global.current_run.recycle_value_multiplier).is_equal(1.25)
	assert_bool(Global.current_run.materials_reset_on_wave_start).is_true()
