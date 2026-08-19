extends GdUnitTestSuite


const TACTICAL_WEAPON_NAMES := {
	&"weapon/axe": ["Bowie Knife", "鲍伊猎刀"],
	&"weapon/chainsaw": ["Butterfly Knife", "蝴蝶刀"],
	&"weapon/mace": ["M9 Bayonet", "M9 刺刀"],
	&"weapon/punch": ["Shadow Daggers", "暗影双匕"],
	&"weapon/sword": ["Karambit", "爪子刀"],
	&"weapon/wand": ["Zeus x27", "Zeus x27"],
	&"weapon/spear": ["Bayonet", "刺刀"],
	&"weapon/cleaver": ["Huntsman Knife", "猎杀者匕首"],
	&"weapon/laser": ["AWP", "AWP"],
	&"weapon/pistol": ["Glock-18", "Glock-18"],
	&"weapon/revolver": ["Desert Eagle", "沙漠之鹰"],
	&"weapon/shotgun": ["M4A4", "M4A4"],
	&"weapon/smg": ["P90", "P90"],
	&"weapon/carbine": ["AK-47", "AK-47"],
	&"weapon/railbow": ["M4A1-S", "M4A1-S"],
	&"weapon/shrapnel_launcher": ["UMP-45", "UMP-45"],
	&"weapon/needler": ["MP9", "MP9"],
	&"weapon/boomerang": ["MAC-10", "MAC-10"],
	&"weapon/ember_staff": ["Molotov", "燃烧瓶"],
	&"weapon/frost_orb": ["Smoke Grenade", "烟雾弹"],
	&"weapon/storm_coil": ["Flashbang", "闪光弹"],
	&"weapon/void_prism": ["HE Grenade", "高爆手雷"],
	&"weapon/turret_kit": ["C4", "C4"],
	&"weapon/drone_beacon": ["USP-S", "USP-S"],
}


func test_weapon_content_uses_the_locked_tactical_roster_and_four_tiers() -> void:
	assert_int(TACTICAL_WEAPON_NAMES.size()).is_equal(24)
	for raw_weapon_id: Variant in TACTICAL_WEAPON_NAMES:
		var weapon_id := StringName(str(raw_weapon_id))
		var weapon := Content.catalog.get_weapon(weapon_id)
		assert_object(weapon).override_failure_message(String(weapon_id)).is_not_null()
		if weapon == null:
			continue
		assert_int(weapon.tiers.size()).is_equal(4)
		for tier_index: int in weapon.tiers.size():
			assert_object(weapon.tiers[tier_index]).is_not_null()
			assert_str(String(Content.catalog.get_item_stable_id(weapon.tiers[tier_index]))).is_equal(
				String(weapon.get_stable_id(Content.catalog.pack_id))
			)


func test_weapon_groups_are_eleven_firearms_eight_close_quarters_and_five_tactical() -> void:
	var counts := {&"firearm": 0, &"close_quarters": 0, &"tactical": 0}
	for weapon: WeaponDef in Content.catalog.get_weapons():
		var matching_groups := 0
		for group_tag: StringName in counts:
			if group_tag in weapon.tags:
				counts[group_tag] += 1
				matching_groups += 1
		assert_int(matching_groups).override_failure_message(
			"%s must have exactly one primary tactical roster tag" % weapon.content_id
		).is_equal(1)
		assert_bool(&"engineering" in weapon.tags).override_failure_message(
			"Engineering allies belong to passive effects, not weapon tags: %s" % weapon.content_id
		).is_false()
		assert_bool(&"building" in weapon.tags or &"summon" in weapon.tags).override_failure_message(
			"Building/summon weapon tags are retired: %s" % weapon.content_id
		).is_false()
	assert_int(counts[&"firearm"]).is_equal(11)
	assert_int(counts[&"close_quarters"]).is_equal(8)
	assert_int(counts[&"tactical"]).is_equal(5)


func test_tactical_weapon_names_are_complete_in_core_and_release_skin_catalogs() -> void:
	var catalogs := [
		[load("res://content_packs/default/i18n/game.en.po") as Translation, 0],
		[load("res://content_packs/default/i18n/game.zh_CN.po") as Translation, 1],
		[load("res://content_packs/skins/lets_gooooo/i18n/skin.en.po") as Translation, 0],
		[load("res://content_packs/skins/lets_gooooo/i18n/skin.zh_CN.po") as Translation, 1],
	]
	for catalog_entry: Array in catalogs:
		var catalog := catalog_entry[0] as Translation
		assert_object(catalog).is_not_null()
		if catalog == null:
			continue
		var language_index := int(catalog_entry[1])
		for raw_weapon_id: Variant in TACTICAL_WEAPON_NAMES:
			var weapon := Content.catalog.get_weapon(StringName(str(raw_weapon_id)))
			assert_str(String(catalog.get_message(weapon.display_name_key))).is_equal(
				TACTICAL_WEAPON_NAMES[raw_weapon_id][language_index]
			)


func test_character_starter_pools_follow_the_tactical_roster_groups() -> void:
	var expectations := {
		&"character/brawler": [&"close_quarters", 8],
		&"character/bunny": [&"firearm", 11],
		&"character/ember_sage": [&"tactical", 5],
	}
	for raw_character_id: Variant in expectations:
		var character := Content.catalog.get_character(StringName(str(raw_character_id)))
		var expected: Array = expectations[raw_character_id]
		assert_object(character).is_not_null()
		assert_int(character.starter_weapon_ids.size()).is_equal(int(expected[1]))
		for starter_id: StringName in character.starter_weapon_ids:
			var weapon := Content.catalog.get_weapon(starter_id)
			assert_object(weapon).override_failure_message(String(starter_id)).is_not_null()
			if weapon != null:
				assert_array(weapon.tags).contains([expected[0]])
	var engineer := Content.catalog.get_character(&"character/scrapwright")
	assert_array(engineer.starter_weapon_ids).contains([&"core:weapon/drone_beacon"])
	assert_array(Content.catalog.get_weapon(&"weapon/drone_beacon").tags).contains([&"sidearm"])


func test_locked_weapon_behaviors_are_encoded_in_content_patterns() -> void:
	var utility_expectations := {
		&"weapon/ember_staff": [&"molotov", AttackPatternDef.Kind.THROWN],
		&"weapon/frost_orb": [&"smoke", AttackPatternDef.Kind.THROWN],
		&"weapon/storm_coil": [&"flash", AttackPatternDef.Kind.THROWN],
		&"weapon/void_prism": [&"he", AttackPatternDef.Kind.THROWN],
		&"weapon/turret_kit": [&"c4", AttackPatternDef.Kind.DEPLOYABLE],
	}
	for raw_weapon_id: Variant in utility_expectations:
		var weapon := Content.catalog.get_weapon(StringName(str(raw_weapon_id)))
		var expected: Array = utility_expectations[raw_weapon_id]
		assert_str(String(weapon.attack_pattern.utility_kind)).is_equal(String(expected[0]))
		assert_int(weapon.attack_pattern.kind).is_equal(int(expected[1]))
		assert_bool(weapon.effects.is_empty()).is_true()
	var flash := Content.catalog.get_weapon(&"weapon/storm_coil").attack_pattern
	assert_bool(flash.interrupt_ranged).is_true()
	assert_str(String(flash.status_id)).is_equal("blind")
	var c4 := Content.catalog.get_weapon(&"weapon/turret_kit").attack_pattern
	assert_bool(c4.arming_delay > 0.0 and c4.explosion_radius > 0.0).is_true()
	assert_int(c4.max_active).is_equal(1)

	var ak := Content.catalog.get_weapon(&"weapon/carbine").attack_pattern
	assert_bool(ak.recoil_ramp_degrees_per_shot > 0.0).is_true()
	assert_bool(ak.recoil_ramp_cap_degrees > ak.recoil_ramp_degrees_per_shot).is_true()
	assert_bool(ak.recoil_recovery_seconds > 0.0).is_true()
	assert_int(Content.catalog.get_weapon(&"weapon/pistol").attack_pattern.burst_count).is_equal(3)
	assert_int(Content.catalog.get_weapon(&"weapon/shotgun").attack_pattern.kind).is_equal(
		AttackPatternDef.Kind.BURST
	)
	for tier: ItemWeapon in Content.catalog.get_weapon(&"weapon/shotgun").tiers:
		assert_int(tier.stats.projectile_count).is_equal(1)
	assert_int(Content.catalog.get_weapon(&"weapon/chainsaw").attack_pattern.kind).is_equal(
		AttackPatternDef.Kind.CONTINUOUS
	)
	var usp := Content.catalog.get_weapon(&"weapon/drone_beacon")
	assert_bool(usp.effects.is_empty()).is_true()
	assert_int(usp.attack_pattern.summon_count).is_zero()
	assert_int(usp.attack_pattern.kind).is_equal(AttackPatternDef.Kind.CHARGED)


func test_engineering_allies_are_never_spawned_by_a_weapon_effect() -> void:
	for weapon: WeaponDef in Content.catalog.get_weapons():
		for effect: EffectDef in weapon.effects:
			if effect == null:
				continue
			for operation: EffectOperationDef in effect.operations:
				assert_bool(operation.kind in [
					EffectOperationDef.Kind.SUMMON,
					EffectOperationDef.Kind.BUILD,
				]).override_failure_message(
					"%s still spawns an engineering ally through %s" % [
						weapon.content_id, effect.effect_id,
					]
				).is_false()


func test_all_weapon_families_have_unique_observable_attack_patterns() -> void:
	var signatures: Dictionary = {}
	for weapon: WeaponDef in Content.catalog.get_weapons():
		assert_object(weapon.attack_pattern).override_failure_message(String(weapon.content_id)).is_not_null()
		if weapon.attack_pattern == null:
			continue
		var signature: String = weapon.attack_pattern.behavior_signature()
		assert_bool(signatures.has(signature)).override_failure_message(
			"%s duplicates %s" % [weapon.content_id, signatures.get(signature, "")]
		).is_false()
		signatures[signature] = String(weapon.content_id)
	assert_int(signatures.size()).is_equal(24)


func test_attack_patterns_produce_distinct_shot_and_melee_geometry() -> void:
	var shotgun: Variant = Content.catalog.get_weapon(&"weapon/shotgun").attack_pattern
	var railbow: Variant = Content.catalog.get_weapon(&"weapon/railbow").attack_pattern
	var spear: Variant = Content.catalog.get_weapon(&"weapon/spear").attack_pattern
	var axe: Variant = Content.catalog.get_weapon(&"weapon/axe").attack_pattern

	assert_bool(shotgun.shot_rotations(0.0).size() > 1).is_true()
	assert_int(railbow.projectile_modifiers().pierce).is_greater(0)
	assert_str(String(spear.kind_key())).is_equal("thrust")
	assert_str(String(axe.kind_key())).is_equal("arc")
	assert_bool(spear.melee_reach_multiplier > axe.melee_reach_multiplier).is_true()


func test_every_character_has_a_unique_core_rule_that_applies_once() -> void:
	var abilities: Dictionary = {}
	for character: CharacterDef in Content.catalog.get_characters():
		assert_object(character.rules).override_failure_message(String(character.content_id)).is_not_null()
		if character.rules == null:
			continue
		assert_bool(character.rules.core_ability_id.is_empty()).is_false()
		assert_bool(abilities.has(character.rules.core_ability_id)).is_false()
		abilities[character.rules.core_ability_id] = true
	assert_int(abilities.size()).is_equal(12)

	var broker := Content.catalog.get_character(&"character/scrap_broker")
	var run := RunState.new(77, PlayerStats.new())
	var before := run.materials
	assert_bool(broker.rules.apply_to_run(run)).is_true()
	assert_bool(run.materials > before).is_true()
	var after_first := run.to_dict()
	assert_bool(broker.rules.apply_to_run(run)).is_false()
	assert_dict(run.to_dict()).is_equal(after_first)


func test_enemy_behavior_resources_cover_all_required_combat_responsibilities() -> void:
	var roles: Dictionary = {}
	for enemy: EnemyDef in Content.catalog.get_enemies():
		assert_object(enemy.behavior).override_failure_message(String(enemy.content_id)).is_not_null()
		if enemy.behavior != null:
			roles[String(enemy.behavior.role_id)] = true
	for required_role: String in [
		"swarm", "charger", "ranged", "tank", "healer", "buffer", "spawner",
		"flanker", "hazard", "resource_disrupt", "ambusher", "debuffer",
	]:
		assert_bool(roles.has(required_role)).override_failure_message(required_role).is_true()

	var healer: EnemyRoleProfile = Content.catalog.get_enemy(&"enemy/medic_spore").behavior.to_role_profile()
	var disruptor: EnemyRoleProfile = Content.catalog.get_enemy(&"enemy/scrap_thief").behavior.to_role_profile()
	assert_bool(healer.heal_amount > 0.0).is_true()
	assert_bool(disruptor.material_steal > 0).is_true()
	assert_array(
		Content.catalog.get_enemy(&"enemy/scrap_titan").behavior.status_immunities
	).contains([&"slow", &"burn"])


func test_five_difficulties_have_progressive_rule_mutators() -> void:
	var previous_pressure := -1.0
	for level: int in range(1, 6):
		var difficulty: DifficultyDef = Content.catalog.get_difficulty(level)
		assert_object(difficulty.mutator).is_not_null()
		assert_int(difficulty.mutator.level).is_equal(level)
		assert_bool(difficulty.mutator.pressure_score() > previous_pressure).is_true()
		previous_pressure = difficulty.mutator.pressure_score()
	assert_bool(Content.catalog.get_difficulty(4).mutator.hazards_enabled).is_true()
	assert_bool(Content.catalog.get_difficulty(5).mutator.boss_extra_phase).is_true()


func test_engineering_allies_inherit_engineering_and_respect_quantity_cap() -> void:
	Global.begin_run(333, null, 0)
	Global.current_run.player_stats.set_stat(StatId.ENGINEERING, 20.0)
	Global.player = auto_free(
		load("res://scenes/unit/players/player_well_rounded.tscn").instantiate() as Player
	)
	var arena: Arena = auto_free(Arena.new())

	arena.spawn_effect_entities(
		&"building", [{"content_id": "building/test", "count": 20}],
		GameplayEventContext.new(GameplayEvent.Type.WAVE_STARTED)
	)

	assert_int(arena.effect_entities.size()).is_equal(Arena.MAX_EFFECT_ENTITIES_PER_KIND)
	assert_bool(arena.effect_entities[0].damage > 4.0).is_true()
	assert_bool(arena.effect_entities[0].attack_range > 340.0).is_true()
	Global.end_run()


func test_character_rule_permanent_effects_are_registered_in_the_run_runtime() -> void:
	var character := CharacterDef.new()
	character.content_id = &"character/test_rule_effect"
	character.rules = CharacterRuleDef.new()
	var effect := EffectDef.new()
	effect.effect_id = &"effect/test_rule_damage"
	effect.trigger_events = [GameplayEvent.Type.WAVE_STARTED]
	effect.operations = [EffectOperationDef.add_stat(StatId.DAMAGE, 5.0)]
	character.rules.permanent_effects = [effect]
	Global.begin_run(1122, UnitStats.new(), 0)
	Global.main_character_selected = character
	var before := Global.current_run.player_stats.get_stat(StatId.DAMAGE)

	Global.rebuild_run_effects()
	Global.dispatch_gameplay_event(GameplayEvent.Type.WAVE_STARTED)

	assert_float(Global.current_run.player_stats.get_stat(StatId.DAMAGE)).is_equal(before + 5.0)
	Global.end_run()
