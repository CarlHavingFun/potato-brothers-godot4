extends GdUnitTestSuite


func test_debug_catalog_exposes_every_static_weapon_item_and_upgrade_with_only_niko() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_object(content).is_not_null()
	if content == null:
		return
	assert_int(content.all(&"weapon").size()).is_equal(12)
	assert_int(content.all(&"item").size()).is_equal(30)
	assert_int(content.all(&"upgrade").size()).is_equal(6)
	assert_int(content.all(&"character").size()).is_equal(1)
	assert_str(String(content.all(&"character")[0].content_id)).is_equal(
		"character.niko:character/niko"
	)


func test_candidate_definitions_use_stable_ids_and_explicit_static_asset_icons() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_object(content).is_not_null()
	if content == null:
		return
	var weapon := content.definition(
		&"gogobro.preview:weapon/community_tapper",
		&"weapon"
	) as GogoWeaponDefinition
	assert_object(weapon).is_not_null()
	if weapon == null:
		return
	assert_str(String(weapon.icon_asset_id)).is_equal("community_tapper")
	assert_str(weapon.display_name).is_equal("爪子刀")
	assert_int(weapon.mode).is_equal(GogoWeaponDefinition.Mode.MELEE)
	assert_str(String(weapon.damage_kind)).is_equal("melee")
	assert_float(weapon.damage).is_equal_approx(3.0, 0.0001)
	assert_float(weapon.cooldown_seconds).is_equal_approx(0.18, 0.0001)


func test_literal_registry_percent_effect_is_translated_once_into_runtime_modifier() -> void:
	var content := GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())
	assert_object(content).is_not_null()
	if content == null:
		return
	var item := content.definition(
		&"gogobro.preview:item/force_buy_runners",
		&"item"
	) as GogoItemDefinition
	assert_object(item).is_not_null()
	if item == null:
		return
	assert_float(float(item.stat_modifiers.get(&"movement_speed_multiplier", 0.0))).is_equal_approx(
		0.06,
		0.0001
	)
	assert_float(float(item.stat_modifiers.get(&"armor", 0.0))).is_equal_approx(-1.0, 0.0001)


func test_release_catalog_keeps_all_static_definitions_without_candidate_preview_tags() -> void:
	var content := GogoContentRegistry.new().build_snapshot(
		ValidationContentFactory.create_packs(false)
	)
	assert_object(content).is_not_null()
	if content == null:
		return
	assert_int(content.all(&"weapon").size()).is_equal(12)
	assert_int(content.all(&"item").size()).is_equal(30)
	assert_int(content.all(&"upgrade").size()).is_equal(6)
	assert_bool(
		content.has_definition(&"gogobro.preview:weapon/community_tapper", &"weapon")
	).is_true()
	assert_bool(
		content.has_definition(&"gogobro.preview:item/force_buy_runners", &"item")
	).is_true()
	for kind in [&"weapon", &"item", &"upgrade"]:
		for definition: GogoContentDefinition in content.all(kind):
			assert_bool(definition.tags.has(&"candidate_preview")).is_false()
