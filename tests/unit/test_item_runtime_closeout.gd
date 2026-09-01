extends GdUnitTestSuite


const TRAINING_6_ID := &"gogobro.core:item/training_6"
const TRAINING_6_UPGRADE_ID := &"gogobro.core:upgrade/training_6"
const FORCE_BUY_RUNNERS_ID := &"gogobro.preview:item/force_buy_runners"
const POST_MATCH_DESK_ID := &"gogobro.preview:item/post_match_analysis_desk"


func test_fractional_regen_is_effective_without_changing_integer_cadence() -> void:
	assert_float(GogoCombatStatRuntime.health_regen_interval_seconds(0.6)).is_equal_approx(5.0 / 0.6, 0.0001)
	assert_float(GogoCombatStatRuntime.health_regen_interval_seconds(1.0)).is_equal_approx(5.0, 0.0001)
	assert_float(GogoCombatStatRuntime.health_regen_interval_seconds(2.0)).is_equal_approx(
		5.0 / (1.0 + 1.0 / 2.25),
		0.0001
	)

	for source_kind in [&"item", &"upgrade"]:
		var session := _session(901 + int(source_kind == &"upgrade"))
		var player := session.run_state.players[0]
		var apply_error := OK
		if source_kind == &"item":
			apply_error = PlayerBuildService.new().apply_item(session, player, TRAINING_6_ID)
		else:
			apply_error = PlayerBuildService.new().apply_upgrade(
				session, player, TRAINING_6_UPGRADE_ID
			)
		assert_int(apply_error).is_equal(OK)
		assert_float(float(player.final_stats.get(&"health_regen", 0.0))).is_equal_approx(0.6, 0.0001)

		var actor: GogoPlayerActor = auto_free(GogoPlayerActor.new())
		actor.player_state = player
		player.current_health = player.max_health - 2.0
		actor.tick_health_regeneration(8.32)
		assert_float(player.current_health).is_equal_approx(player.max_health - 2.0, 0.0001)
		actor.tick_health_regeneration(0.02)
		assert_float(player.current_health).is_equal_approx(player.max_health - 1.0, 0.0001)


func test_force_buy_runners_remains_offerable_and_reaches_live_consumers() -> void:
	var content := _snapshot()
	var definition := content.definition(FORCE_BUY_RUNNERS_ID, &"item") as GogoItemDefinition
	assert_object(definition).is_not_null()
	assert_str(String(definition.content_id)).is_equal(String(FORCE_BUY_RUNNERS_ID))
	assert_int(definition.tier).is_equal(1)
	assert_int(definition.price).is_equal(12)
	assert_int(definition.max_count).is_equal(99)
	assert_float(float(definition.stat_modifiers.get(&"movement_speed_multiplier", 0.0))).is_equal_approx(0.06, 0.0001)
	assert_float(float(definition.stat_modifiers.get(&"armor", 0.0))).is_equal_approx(-1.0, 0.0001)
	assert_bool(definition.has_method(&"is_shop_offerable_to")).is_true()
	if not definition.has_method(&"is_shop_offerable_to"):
		return
	assert_bool(bool(definition.call(
		&"is_shop_offerable_to", ValidationContentFactory.CHARACTER_ID
	))).is_true()

	var session := _session(903)
	var offers := ItemPoolService.new().generate_shop_offers(
		content,
		session.run_state.player(),
		1,
		1,
		RandomNumberGenerator.new(),
		_exclude_all_except(content, FORCE_BUY_RUNNERS_ID)
	)
	assert_array(offers).has_size(1)
	assert_str(String(offers[0].content_id)).is_equal(String(FORCE_BUY_RUNNERS_ID))

	var player := session.run_state.players[0]
	assert_int(PlayerBuildService.new().apply_item(session, player, FORCE_BUY_RUNNERS_ID)).is_equal(OK)
	assert_float(float(player.final_stats.get(&"movement_speed", 0.0))).is_equal_approx(318.0, 0.0001)
	assert_float(float(player.final_stats.get(&"armor", 0.0))).is_equal_approx(-1.0, 0.0001)


func test_post_match_desk_is_excluded_from_generated_item_pool() -> void:
	var content := _snapshot()
	var definition := content.definition(POST_MATCH_DESK_ID, &"item") as GogoItemDefinition
	assert_object(definition).is_not_null()
	assert_str(String(definition.content_id)).is_equal(String(POST_MATCH_DESK_ID))
	assert_bool(definition.has_method(&"is_shop_offerable_to")).is_true()
	if definition.has_method(&"is_shop_offerable_to"):
		assert_bool(bool(definition.call(
			&"is_shop_offerable_to", ValidationContentFactory.CHARACTER_ID
		))).is_false()

	var session := _session(906)
	var offers := ItemPoolService.new().generate_shop_offers(
		content,
		session.run_state.player(),
		5,
		1,
		RandomNumberGenerator.new(),
		_exclude_all_except(content, POST_MATCH_DESK_ID)
	)
	assert_array(offers).is_empty()


func test_post_match_desk_cache_is_normalized_but_old_ownership_survives() -> void:
	var content := _snapshot()
	var session := _session(904)
	var state := session.run_state
	state.players[0].item_ids.append(POST_MATCH_DESK_ID)
	state.shop_offer_ids = [POST_MATCH_DESK_ID, &"", &"", &""]
	state.locked_shop_offer_ids = [POST_MATCH_DESK_ID]
	state.shop_offer_wave = state.current_wave
	state.shop_offer_initialized = true

	var restored := GogoRunState.from_dictionary(state.to_dictionary(), content)
	assert_object(restored).is_not_null()
	assert_int(restored.players[0].item_ids.count(POST_MATCH_DESK_ID)).is_equal(1)
	session.run_state = restored

	var offers := ShopRuntimeService.new().open_shop(session)
	assert_array(offers).has_size(4)
	assert_object(offers[0]).is_null()
	assert_str(String(session.run_state.shop_offer_ids[0])).is_empty()
	assert_bool(session.run_state.locked_shop_offer_ids.has(POST_MATCH_DESK_ID)).is_false()
	assert_int(session.run_state.players[0].item_ids.count(POST_MATCH_DESK_ID)).is_equal(1)


func test_post_match_desk_direct_buy_is_transactionally_rejected() -> void:
	var content := _snapshot()
	var definition := content.definition(POST_MATCH_DESK_ID, &"item") as GogoItemDefinition
	assert_object(definition).is_not_null()
	assert_int(definition.tier).is_equal(4)
	assert_int(definition.price).is_equal(45)
	assert_int(definition.max_count).is_equal(4)

	var session := _session(905)
	var shop := ShopRuntimeService.new()
	shop.offers = [definition]
	var state_before := session.run_state.to_dictionary().duplicate(true)
	var rng_before := session.rng.state

	assert_int(shop.buy(session, 0)).is_equal(ERR_INVALID_DATA)
	assert_str(shop.last_failure_reason).is_equal("unavailable_content")
	assert_dict(session.run_state.to_dictionary()).is_equal(state_before)
	assert_int(session.rng.state).is_equal(rng_before)


func _snapshot() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _session(seed: int) -> GameSession:
	var session := GameSession.new()
	var config := SessionConfig.new()
	config.seed = seed
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	assert_int(session.start(config, _snapshot())).is_equal(OK)
	assert_int(session.transition(&"shop")).is_equal(OK)
	session.run_state.player().materials = 1000
	return session


func _exclude_all_except(content: ContentSnapshot, keep_id: StringName) -> Array[StringName]:
	var excluded: Array[StringName] = []
	for definition: GogoContentDefinition in content.all(&"item"):
		if definition.content_id != keep_id:
			excluded.append(definition.content_id)
	for definition: GogoContentDefinition in content.all(&"weapon"):
		if definition.content_id != keep_id:
			excluded.append(definition.content_id)
	return excluded
