extends GdUnitTestSuite

const RANGED := ValidationContentFactory.RANGED_ID
const MAX_ID := 9007199254740991


func test_profile_json_roundtrip_restores_runtime_stat_dictionary_exactly() -> void:
	# A raw pass-through of decoded stats leaves String keys and integral number
	# variants behind; both are observable at the strict whole-checkpoint boundary.
	var expected := _v3()
	expected.run_seed = 9007199254740993
	expected.players[0].base_stats = {&"max_health": 20.0, &"movement_speed": 300.0, &"pickup_range": 115.0, &"armor": 0.0}
	expected.players[0].final_stats = {&"max_health": 20.0, &"movement_speed": 300.0, &"pickup_range": 115.0, &"armor": 0.0, &"critical_chance": 0.0}
	var wire := JSON.stringify({"run_checkpoint": expected}, "", true, true)
	var decoded := ProfileService.JSON_CODEC.decode(wire, ProfileService._numeric_domain)
	assert_int(decoded.error).is_equal(OK)
	if decoded.error != OK: return
	var checkpoint: Dictionary = decoded.value.run_checkpoint
	var before := var_to_bytes(checkpoint)
	var restored := _parse(checkpoint)
	assert_array(var_to_bytes(checkpoint)).is_equal(before)
	assert_int(restored.error).is_equal(OK)
	if restored.error != OK: return
	assert_bool(restored.state.to_dictionary() == expected).is_true()


func test_stat_dictionary_equality_characterizes_single_representation_changes() -> void:
	var expected := {&"armor": 0.0, &"movement_speed": 300.0}
	var only_integral_values := {&"armor": 0, &"movement_speed": 300}
	var only_text_keys := {"armor": 0.0, "movement_speed": 300.0}
	var only_insertion_order := {&"movement_speed": 300.0, &"armor": 0.0}
	print("STAT_DICT_EQUALITY integral_values=%s text_keys=%s insertion_order=%s" % [
		expected == only_integral_values,
		expected == only_text_keys,
		expected == only_insertion_order,
	])
	assert_bool(expected == only_integral_values).is_false()
	assert_bool(expected == only_text_keys).is_true()
	assert_bool(expected == only_insertion_order).is_true()


func test_profile_json_stat_roundtrip_keeps_fractional_negative_zero_lookup_and_input_detached() -> void:
	var expected := _v3()
	expected.players[0].base_stats = {&"health_regen": -1.25, &"armor": 0.0, &"movement_speed": 300.5}
	expected.players[0].final_stats = {&"critical_chance": 0.0, &"damage_multiplier": 1.125}
	var decoded := ProfileService.JSON_CODEC.decode(JSON.stringify({"run_checkpoint": expected}, "", true, true), ProfileService._numeric_domain)
	assert_int(decoded.error).is_equal(OK)
	if decoded.error != OK: return
	var checkpoint: Dictionary = decoded.value.run_checkpoint
	var before := var_to_bytes(checkpoint)
	var restored := _parse(checkpoint)
	assert_array(var_to_bytes(checkpoint)).is_equal(before)
	assert_int(restored.error).is_equal(OK)
	if restored.error != OK: return
	var player := (restored.state as GogoRunState).player()
	assert_float(player.base_stats[&"health_regen"]).is_equal(-1.25)
	assert_float(player.base_stats[&"armor"]).is_equal(0.0)
	assert_float(player.base_stats[&"movement_speed"]).is_equal(300.5)
	assert_float(player.final_stats[&"critical_chance"]).is_equal(0.0)
	assert_float(player.final_stats[&"damage_multiplier"]).is_equal(1.125)
	for stat in player.base_stats:
		assert_int(typeof(stat)).is_equal(TYPE_STRING_NAME)
	for stat in player.final_stats:
		assert_int(typeof(stat)).is_equal(TYPE_STRING_NAME)
	assert_dict(restored.state.to_dictionary()).is_equal(expected)


func test_profile_json_stat_normalization_preserves_int64_values_not_exactly_representable_as_float() -> void:
	var source := _v3()
	source.players[0].base_stats = {
		&"positive_safe": 9007199254740992,
		&"negative_safe": -9007199254740992,
		&"even_above_safe": 9007199254740994,
		&"odd_above_safe": 9007199254740993,
		&"int64_min": -9223372036854775808,
		&"int64_max": 9223372036854775807,
	}
	var decoded := ProfileService.JSON_CODEC.decode(JSON.stringify({"run_checkpoint": source}, "", true, true), ProfileService._numeric_domain)
	assert_int(decoded.error).is_equal(OK)
	if decoded.error != OK: return
	var checkpoint: Dictionary = decoded.value.run_checkpoint
	var before := var_to_bytes(checkpoint)
	var restored := _parse(checkpoint)
	assert_array(var_to_bytes(checkpoint)).is_equal(before)
	assert_int(restored.error).is_equal(OK)
	if restored.error != OK: return
	var stats := (restored.state as GogoRunState).player().base_stats
	for key in [&"positive_safe", &"negative_safe", &"even_above_safe"]:
		assert_int(typeof(stats[key])).is_equal(TYPE_FLOAT)
	assert_float(stats[&"positive_safe"]).is_equal(9007199254740992.0)
	assert_float(stats[&"negative_safe"]).is_equal(-9007199254740992.0)
	assert_float(stats[&"even_above_safe"]).is_equal(9007199254740994.0)
	for pair in [[&"odd_above_safe", 9007199254740993], [&"int64_min", -9223372036854775808], [&"int64_max", 9223372036854775807]]:
		assert_int(typeof(stats[pair[0]])).is_equal(TYPE_INT)
		assert_int(stats[pair[0]]).is_equal(pair[1])


func test_stat_normalization_keeps_boolean_nonfinite_and_nontext_keys_rejected() -> void:
	for pair in [["base_stats", {&"damage": true}], ["base_stats", {&"damage": INF}],
		["final_stats", {&"damage": NAN}], ["final_stats", {1: 2.0}]]:
		var data := _v3()
		data.players[0][pair[0]] = pair[1]
		_reject(data, "players[0]." + pair[0])


func test_weapon_shape_errors_name_the_exact_missing_or_unknown_field() -> void:
	for key in ["instance_id", "content_id", "quality"]:
		var data := _v3()
		data.players[0].weapons[0].erase(key)
		assert_str(_parse(data).path).is_equal("players[0].weapons[0]." + key)
	var data := _v3()
	data.players[0].weapons[0].extra = 1
	assert_str(_parse(data).path).is_equal("players[0].weapons[0].extra")


func test_serializer_preserves_invalid_candidates_as_rejectable_data_without_throwing() -> void:
	var state := _parse(_v3()).state as GogoRunState
	state.players.append(null)
	_reject(state.to_dictionary(), "players[1]")
	state.players.remove_at(1)
	state.player().weapon_inventory = null
	_reject(state.to_dictionary(), "players[0].")
	state = _parse(_v3()).state as GogoRunState
	var malformed: Array[Dictionary] = [{"instance_id": 1, "quality": 1}]
	state.player().weapon_inventory.set("_records", malformed)
	_reject(state.to_dictionary(), "players[0].weapons[0]")


func test_explicit_context_is_mandatory_and_detached_parse_keeps_owned_order_and_duplicates() -> void:
	var payload := _v3()
	assert_int(GogoRunState.parse_dictionary(payload, null).error).is_not_equal(OK)
	assert_object(GogoRunState.from_dictionary(payload, null)).is_null()
	payload.players[0].character_id = ValidationContentFactory.CHARACTER_ID
	payload.players[0].weapons[0].content_id = RANGED
	payload.players[0].item_ids = [&"gogobro.core:item/training_1", &"gogobro.core:item/training_1"]
	payload.players[0].upgrade_ids = [&"gogobro.core:upgrade/training_2", &"gogobro.core:upgrade/training_2"]
	var result := _parse(payload)
	assert_int(result.error).is_equal(OK)
	var state := result.state as GogoRunState
	assert_array(state.player().item_ids).is_equal(payload.players[0].item_ids)
	assert_array(state.player().upgrade_ids).is_equal(payload.players[0].upgrade_ids)
	payload.players[0].base_stats["after_parse"] = 999
	assert_bool(state.player().base_stats.has("after_parse")).is_false()


func test_schema_two_migrates_rng_and_preserves_holes_prior_cache_and_non_reused_ids() -> void:
	var data := _v2()
	data.current_wave = 20
	data.shop_offer_wave = 19
	data.shop_offer_ids = [String(RANGED), "", String(ValidationContentFactory.MELEE_ID), ""]
	data.locked_shop_offer_ids = [String(RANGED)]
	data.shop_offer_initialized = true
	data.shop_offer_initialization_id = 7
	data.players[0].weapons = [{"instance_id": 12, "content_id": String(RANGED), "quality": 2}]
	data.players[0].next_weapon_instance_id = 27
	var result := _parse(JSON.parse_string(JSON.stringify(data)))
	assert_int(result.error).is_equal(OK)
	if result.state == null: return
	var state := result.state as GogoRunState
	var fallback := RandomNumberGenerator.new()
	fallback.seed = data.run_seed
	assert_int(state.schema_version).is_equal(3)
	assert_int(state.rng_state).is_equal(fallback.state)
	for key in data:
		if key != "schema_version":
			assert_that(state.to_dictionary()[key]).is_equal(data[key])
	var session := GameSession.new()
	session.content_snapshot = _content()
	session.run_state = state
	var shop := ShopRuntimeService.new()
	shop.offers = [session.content_snapshot.definition(RANGED, &"weapon")]
	assert_int(shop.buy(session, 0)).is_equal(OK)
	var saved: Dictionary = state.to_dictionary().players[0]
	assert_int(saved.next_weapon_instance_id).is_equal(28)
	assert_array(saved.weapons).is_equal([
		{"instance_id": 12, "content_id": String(RANGED), "quality": 2},
		{"instance_id": 27, "content_id": String(RANGED), "quality": 1}])


func test_schema_two_requires_every_field_and_rejects_unknown_keys() -> void:
	var valid := _v2()
	for key in valid:
		var data := valid.duplicate(true)
		data.erase(key)
		_reject(data, key)
	for key in valid.players[0]:
		var data := valid.duplicate(true)
		data.players[0].erase(key)
		_reject(data, "players[0]." + key)
	for key in valid.players[0].weapons[0]:
		var data := valid.duplicate(true)
		data.players[0].weapons[0].erase(key)
		_reject(data, "players[0].weapons[0]")
	for location in ["run", "player", "weapon"]:
		var data := valid.duplicate(true)
		if location == "run": data.extra = 1
		elif location == "player": data.players[0].extra = 1
		else: data.players[0].weapons[0].extra = 1
		_reject(data, "extra" if location == "run" else ("players[0].extra" if location == "player" else "players[0].weapons[0]"))


func test_schema_three_requires_exact_rng_state_and_older_schemas_reject_future_field() -> void:
	var missing := _v3()
	missing.erase("rng_state")
	_reject(missing, "rng_state")
	for bad in [true, "1", 1.25, INF, NAN, 9223372036854775808.0, -9223372036854777856.0]:
		var data := _v3()
		data.rng_state = bad
		_reject(data, "rng_state")
	for exact in [-9223372036854775808, 0, 9007199254740993, 9223372036854775807]:
		var data := _v3()
		data.rng_state = exact
		var parsed := _parse(data)
		assert_int(parsed.error).is_equal(OK)
		if parsed.error == OK:
			assert_int(parsed.state.rng_state).is_equal(exact)
	for version in [1, 2]:
		var older := _v1() if version == 1 else _v2()
		older.rng_state = 1
		_reject(older, "rng_state")


func test_schema_two_rejects_wrong_containers_elements_and_references() -> void:
	for raw in [null, [], 7, true, "checkpoint"]: _reject(raw, "$")
	for pair in [["players", {}], ["players", []], ["players", [null]], ["locked_shop_offer_ids", {}], ["shop_offer_ids", {}],
		["locked_shop_offer_ids", [String(RANGED), String(RANGED)]], ["locked_shop_offer_ids", [""]],
		["shop_offer_ids", [true]], ["shop_offer_ids", [String(ValidationContentFactory.CHARACTER_ID)]],
		["zone_id", ""], ["zone_id", String(RANGED)], ["difficulty_id", 1], ["phase", "bogus"],
		["schema_version", 4], ["won", 1], ["ended", "false"], ["endless", 0], ["shop_offer_initialized", []]]:
		var data := _v2()
		data[pair[0]] = pair[1]
		_reject(data, pair[0])
	for pair in [["base_stats", []], ["base_stats", {1: 2}], ["final_stats", {"damage": true}],
		["final_stats", {"damage": INF}], ["item_ids", {}], ["item_ids", [String(RANGED)]],
		["upgrade_ids", [null]], ["character_id", String(RANGED)], ["weapons", {}], ["weapons", [null]]]:
		var data := _v2()
		data.players[0][pair[0]] = pair[1]
		_reject(data, "players[0]." + pair[0])
	for key in ["shop_offer_ids", "locked_shop_offer_ids"]:
		var data := _v2()
		data[key] = [String(RANGED), String(RANGED), String(RANGED), String(RANGED), String(RANGED)]
		_reject(data, key)


func test_initialized_current_wave_shop_cache_requires_exact_four_slots_and_safe_phase() -> void:
	var current := _v3()
	current.shop_offer_wave = current.current_wave
	current.shop_offer_initialized = true
	for partial_slots in [[], [""], ["", "", ""]]:
		var partial := current.duplicate(true)
		partial.shop_offer_ids = partial_slots
		_reject(partial, "shop_offer_ids")

	current.shop_offer_ids = ["", "", "", ""]
	var parsed := _parse(current)
	assert_int(parsed.error).is_equal(OK)
	if parsed.error == OK:
		assert_array((parsed.state as GogoRunState).shop_offer_ids).is_equal([&"", &"", &"", &""])
	for unsafe_phase in ["selection", "combat", "upgrade", "settlement"]:
		var unsafe := current.duplicate(true)
		unsafe.phase = unsafe_phase
		_reject(unsafe, "phase")

	var ended_settlement := current.duplicate(true)
	ended_settlement.phase = "settlement"
	ended_settlement.ended = true
	assert_int(_parse(ended_settlement).error).is_equal(OK)
	var uninitialized_same_wave := current.duplicate(true)
	uninitialized_same_wave.shop_offer_initialized = false
	uninitialized_same_wave.shop_offer_ids = []
	uninitialized_same_wave.phase = "combat"
	var uninitialized_result := _parse(uninitialized_same_wave)
	assert_int(uninitialized_result.error).is_equal(OK)
	if uninitialized_result.error == OK:
		assert_array((uninitialized_result.state as GogoRunState).shop_offer_ids).is_empty()


func test_previous_wave_shop_cache_keeps_bounded_partial_slots_in_later_combat() -> void:
	var previous := _v3()
	previous.current_wave = 2
	previous.phase = "combat"
	previous.shop_offer_wave = 1
	previous.shop_offer_ids = [String(RANGED), ""]
	previous.shop_offer_initialized = true
	var parsed := _parse(previous)
	assert_int(parsed.error).is_equal(OK)
	if parsed.error == OK:
		var state := parsed.state as GogoRunState
		assert_int(state.shop_offer_wave).is_equal(1)
		assert_array(state.shop_offer_ids).is_equal([RANGED, &""])
		assert_str(String(state.phase)).is_equal("combat")


func test_integer_validation_precedes_conversion_for_all_counter_fields() -> void:
	for key in ["schema_version", "run_seed", "rng_state", "current_wave", "total_waves", "shop_offer_wave", "shop_offer_initialization_id", "reroll_count", "upgrade_reroll_count", "pending_upgrade_count"]:
		for bad in [true, "1", 1.25, INF, NAN, 9223372036854775808.0, -9223372036854777856.0]:
			var data := _v3()
			data[key] = bad
			_reject(data, key)
	for key in ["player_index", "xp", "materials", "level", "xp_to_next_level", "next_weapon_instance_id"]:
		for bad in [false, "1", 1.5, INF, NAN, 9223372036854775808.0]:
			var data := _v3()
			data.players[0][key] = bad
			_reject(data, "players[0]." + key)
	for key in ["instance_id", "quality"]:
		for bad in [true, "1", 1.5, INF, NAN, 9223372036854775808.0, 0, -1]:
			var data := _v3()
			data.players[0].weapons[0][key] = bad
			_reject(data, "players[0].weapons[0]." + key)


func test_inventory_boundaries_and_later_player_failure_never_publish_partial_state() -> void:
	for pair in [["instance_id", MAX_ID], ["quality", 5], ["content_id", "missing"], ["content_id", 1]]:
		var data := _v3()
		data.players[0].weapons[0][pair[0]] = pair[1]
		_reject(data, "players[0].weapons[0]." + pair[0])
	for next_id in [0, -1, 1, MAX_ID + 1]:
		var data := _v3()
		data.players[0].next_weapon_instance_id = next_id
		_reject(data, "players[0].")
	var duplicate := _v3()
	duplicate.players[0].weapons.append(duplicate.players[0].weapons[0].duplicate())
	_reject(duplicate, "players[0].weapons[1].instance_id")
	var overfull := _v3()
	overfull.players[0].weapons = []
	overfull.players[0].next_weapon_instance_id = 8
	for id in range(1, 8): overfull.players[0].weapons.append({"instance_id": id, "content_id": String(RANGED), "quality": 1})
	_reject(overfull, "players[0].weapons")
	for duplicate_index in [false, true]:
		var data := _v3()
		data.players.append(data.players[0].duplicate(true))
		data.players[1].player_index = 0 if duplicate_index else 1
		if not duplicate_index: data.players[1].current_health = -1
		_reject(data, "players[1].player_index" if duplicate_index else "players[1].current_health")


func test_numeric_and_state_relations_are_checked_without_clamping() -> void:
	for pair in [["current_wave", 0], ["total_waves", 0], ["shop_offer_wave", -1], ["reroll_count", -1],
		["elapsed_seconds", -0.1], ["elapsed_seconds", INF], ["elapsed_seconds", true],
		["won", true], ["ended", true], ["endless", true], ["current_wave", 21], ["shop_offer_wave", 2]]:
		var data := _v3()
		data[pair[0]] = pair[1]
		_reject(data, "")
	for pair in [["player_index", -1], ["materials", -1], ["level", 0], ["xp_to_next_level", 0], ["xp", 20],
		["current_health", -1], ["current_health", 21], ["max_health", 0], ["max_health", INF],
		["economy_material_remainder", -0.1], ["economy_material_remainder", 1], ["economy_material_remainder", true],
		["current_health", "10"], ["current_health", NAN]]:
		var data := _v3()
		data.players[0][pair[0]] = pair[1]
		_reject(data, "players[0].")


func test_valid_integral_floats_zero_weapons_and_int64_endless_are_accepted() -> void:
	var data := _v3()
	data.rng_state = 8
	for key in ["schema_version", "run_seed", "rng_state", "current_wave", "total_waves", "shop_offer_wave", "shop_offer_initialization_id", "reroll_count", "upgrade_reroll_count", "pending_upgrade_count"]:
		data[key] = float(data[key])
	for key in ["player_index", "xp", "materials", "level", "xp_to_next_level", "next_weapon_instance_id"]:
		data.players[0][key] = float(data.players[0][key])
	data.players[0].weapons[0].instance_id = 1.0
	data.players[0].weapons[0].quality = 1.0
	assert_int(_parse(data).error).is_equal(OK)
	for wave in [21, MAX_ID + 1, 9223372036854775807]:
		data = _v3()
		data.current_wave = wave
		data.endless = true
		data.run_seed = -9223372036854775808
		data.players[0].weapons = []
		data.players[0].next_weapon_instance_id = MAX_ID
		assert_int(_parse(data).error).is_equal(OK)
	data = _v3()
	data.players[0].weapons[0].instance_id = MAX_ID - 1
	data.players[0].next_weapon_instance_id = MAX_ID
	assert_int(_parse(data).error).is_equal(OK)


func test_v1_only_declared_defaults_and_owned_quality_one_migrate() -> void:
	for rank_mode in ["absent", "empty", "owned"]:
		var data := _v1()
		data.total_waves = 5
		data.players[0].weapon_ids.append(String(RANGED))
		if rank_mode != "absent": data.players[0].weapon_levels = {} if rank_mode == "empty" else {String(RANGED): 1.0}
		var result := _parse(data)
		assert_int(result.error).is_equal(OK)
		if result.state == null: continue
		var saved: Dictionary = result.state.to_dictionary()
		assert_int(saved.schema_version).is_equal(3)
		var fallback := RandomNumberGenerator.new()
		fallback.seed = data.run_seed
		assert_int(saved.rng_state).is_equal(fallback.state)
		assert_int(saved.total_waves).is_equal(5)
		assert_bool(saved.endless).is_false()
		assert_array(saved.shop_offer_ids).is_empty()
		assert_int(saved.players[0].get("next_weapon_instance_id", 0)).is_equal(3)
		assert_array(saved.players[0].get("weapons", [])).is_equal([
			{"instance_id": 1, "content_id": String(RANGED), "quality": 1},
			{"instance_id": 2, "content_id": String(RANGED), "quality": 1}])
	for key in _v1():
		var data := _v1()
		data.erase(key)
		_reject(data, key)
	for key in _v1().players[0]:
		var data := _v1()
		data.players[0].erase(key)
		_reject(data, "players[0]." + key)
	for rank in [null, [], 1, {String(RANGED): 0}, {String(RANGED): 4}, {String(RANGED): true}, {String(RANGED): "1"}, {String(RANGED): 1.5}, {String(RANGED): INF}]:
		var data := _v1()
		data.players[0].weapon_levels = rank
		_reject(data, "players[0].weapon_levels")
	var mixed := _v1()
	mixed.players[0].weapons = []
	_reject(mixed, "players[0].weapons")


func _parse(data: Variant) -> Dictionary:
	var before := var_to_bytes(data)
	var result := GogoRunState.parse_dictionary(data, _content())
	assert_array(var_to_bytes(data)).is_equal(before)
	return result


func _reject(data: Variant, path_prefix: String) -> void:
	var result := _parse(data)
	assert_int(result.error).is_not_equal(OK)
	assert_object(result.state).is_null()
	assert_bool(String(result.path).begins_with(path_prefix)).is_true()
	assert_str(String(result.path)).is_not_empty()


func _v2() -> Dictionary:
	var data := _v1()
	data.schema_version = 2
	data.merge({"endless": false, "locked_shop_offer_ids": [], "shop_offer_wave": 0, "shop_offer_ids": [],
		"shop_offer_initialized": false, "shop_offer_initialization_id": 0, "reroll_count": 0,
		"upgrade_reroll_count": 0, "pending_upgrade_count": 0, "elapsed_seconds": 0.0})
	data.players[0].erase("weapon_ids")
	data.players[0].weapons = [{"instance_id": 1, "content_id": String(RANGED), "quality": 1}]
	data.players[0].next_weapon_instance_id = 2
	data.players[0].economy_material_remainder = 0.0
	return data


func _v3() -> Dictionary:
	var data := _v2()
	data.schema_version = 3
	var seeded := RandomNumberGenerator.new()
	seeded.seed = data.run_seed
	data.rng_state = seeded.state
	return data


# These are valid complete legacy checkpoints except for the named defect.
# They fail if aggregate upgrades are silently interpreted as per-copy I.
func test_v1_any_aggregate_upgrade_is_rejected_without_touching_input() -> void:
	for ids in [[String(RANGED)], [String(RANGED), String(RANGED)]]:
		var data := _v1()
		data.players[0].weapon_ids = ids
		data.players[0].weapon_levels = {String(RANGED): 2}
		var before := data.duplicate(true)
		assert_object(GogoRunState.from_dictionary(data, _content())).is_null()
		assert_dict(data).is_equal(before)


func test_v1_fractional_counter_and_orphan_rank_are_rejected() -> void:
	for defect in ["fraction", "orphan"]:
		var data := _v1()
		if defect == "fraction":
			data.current_wave = 1.5
		else:
			data.players[0].weapon_levels = {String(ValidationContentFactory.MELEE_ID): 1}
		var before := data.duplicate(true)
		assert_object(GogoRunState.from_dictionary(data, _content())).is_null()
		assert_dict(data).is_equal(before)


func _content() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _v1() -> Dictionary:
	return {
		"schema_version": 1, "run_seed": 15, "current_wave": 1, "total_waves": 20,
		"phase": "shop", "zone_id": String(ValidationContentFactory.ZONE_ID),
		"difficulty_id": String(ValidationContentFactory.DIFFICULTY_ID), "won": false, "ended": false,
		"players": [{"player_index": 0, "character_id": String(ValidationContentFactory.CHARACTER_ID),
			"level": 1, "xp": 0, "xp_to_next_level": 20, "materials": 100,
			"current_health": 20.0, "max_health": 20.0, "base_stats": {}, "final_stats": {},
			"weapon_ids": [String(RANGED)], "item_ids": [], "upgrade_ids": []}],
	}
