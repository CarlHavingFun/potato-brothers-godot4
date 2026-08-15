extends GdUnitTestSuite


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
