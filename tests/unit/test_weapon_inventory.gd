extends GdUnitTestSuite


const WEAPON_A: StringName = &"fixture:weapon/a"
const WEAPON_B: StringName = &"fixture:weapon/b"
const INVENTORY := preload("res://game/session/weapon_inventory.gd")
const QUALITY_RULES := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")


func test_add_uses_real_weapon_content_and_detached_copies() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	var result := inventory.add_weapon(WEAPON_A, content)
	assert_int(result.error).is_equal(OK)
	assert_int(result.instance_id).is_equal(1)
	if result.error != OK:
		return
	var returned_records := inventory.records()
	returned_records[0]["quality"] = 4
	assert_int(inventory.record(1).quality).is_equal(1)
	var clone := inventory.duplicate(true)
	assert_int(clone.remove_weapon(1)).is_equal(OK)
	assert_int(inventory.size()).is_equal(1)
	assert_int(clone.size()).is_equal(0)


func test_ids_are_monotonic_after_every_weapon_is_sold() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	assert_int(inventory.add_weapon(WEAPON_A, content).instance_id).is_equal(1)
	assert_int(inventory.add_weapon(WEAPON_B, content).instance_id).is_equal(2)
	assert_int(inventory.remove_weapon(1)).is_equal(OK)
	assert_int(inventory.remove_weapon(2)).is_equal(OK)
	assert_int(inventory.next_id()).is_equal(3)
	assert_int(inventory.add_weapon(WEAPON_A, content).instance_id).is_equal(3)


func test_record_and_content_ids_are_detached_projections() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	assert_int(inventory.add_weapon(WEAPON_A, content).error).is_equal(OK)
	assert_int(inventory.add_weapon(WEAPON_B, content).error).is_equal(OK)
	var returned_record := inventory.record(1)
	returned_record["quality"] = 4
	assert_int(inventory.record(1).quality).is_equal(1)
	var returned_ids := inventory.content_ids()
	returned_ids[0] = WEAPON_B
	assert_array(inventory.content_ids()).is_equal([WEAPON_A, WEAPON_B])


func test_capacity_and_allocator_exhaustion_reject_without_mutation() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	for ignored in INVENTORY.CAPACITY:
		assert_int(inventory.add_weapon(WEAPON_A, content).error).is_equal(OK)
	var full_records := inventory.records()
	var full_next := inventory.next_id()
	assert_int(inventory.add_weapon(WEAPON_B, content).error).is_not_equal(OK)
	assert_array(inventory.records()).is_equal(full_records)
	assert_int(inventory.next_id()).is_equal(full_next)

	var exhausted := INVENTORY.new()
	exhausted._next_id = INVENTORY.MAX_ID - 1
	assert_int(exhausted.add_weapon(WEAPON_A, content).instance_id).is_equal(INVENTORY.MAX_ID - 1)
	assert_int(exhausted.next_id()).is_equal(INVENTORY.MAX_ID)
	var before := exhausted.records()
	assert_int(exhausted.add_weapon(WEAPON_A, content).error).is_not_equal(OK)
	assert_array(exhausted.records()).is_equal(before)
	assert_int(exhausted.next_id()).is_equal(INVENTORY.MAX_ID)


func test_combine_keeps_selected_id_and_uses_first_legal_partner_in_stable_order() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	for ignored in 3:
		assert_int(inventory.add_weapon(WEAPON_A, content).error).is_equal(OK)
	assert_int(inventory.combination_partner(2)).is_equal(1)
	assert_int(inventory.combine_weapon(2)).is_equal(OK)
	assert_array(inventory.records()).is_equal([
		{"instance_id": 2, "content_id": WEAPON_A, "quality": 2},
		{"instance_id": 3, "content_id": WEAPON_A, "quality": 1},
	])
	assert_int(inventory.next_id()).is_equal(4)
	var before := inventory.records()
	assert_int(inventory.combine_weapon(999)).is_not_equal(OK)
	assert_array(inventory.records()).is_equal(before)


func test_combine_rejects_missing_iv_mixed_and_same_name_different_content() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	assert_int(inventory.add_weapon(WEAPON_A, content, 4).error).is_equal(OK)
	assert_int(inventory.add_weapon(WEAPON_A, content, 4).error).is_equal(OK)
	assert_int(inventory.add_weapon(WEAPON_A, content, 1).error).is_equal(OK)
	assert_int(inventory.add_weapon(WEAPON_B, content, 1).error).is_equal(OK)
	var before := inventory.records()
	assert_int(inventory.combination_partner(1)).is_equal(0)
	assert_int(inventory.combine_weapon(1)).is_not_equal(OK)
	assert_int(inventory.combination_partner(3)).is_equal(0)
	assert_int(inventory.combine_weapon(3)).is_not_equal(OK)
	assert_array(inventory.records()).is_equal(before)


func test_interleaved_four_copies_preserve_unrelated_order_and_selected_survivor() -> void:
	var content := _content()
	var inventory := INVENTORY.new()
	for spec in [[WEAPON_A, 1], [WEAPON_B, 1], [WEAPON_A, 1], [WEAPON_A, 1], [WEAPON_A, 1]]:
		assert_int(inventory.add_weapon(spec[0], content, spec[1]).error).is_equal(OK)
	assert_int(inventory.combination_partner(4)).is_equal(1)
	assert_int(inventory.combine_weapon(4)).is_equal(OK)
	assert_array(inventory.records()).is_equal([
		{"instance_id": 2, "content_id": WEAPON_B, "quality": 1},
		{"instance_id": 3, "content_id": WEAPON_A, "quality": 1},
		{"instance_id": 4, "content_id": WEAPON_A, "quality": 2},
		{"instance_id": 5, "content_id": WEAPON_A, "quality": 1},
	])


func test_parse_records_accepts_json_integral_floats_and_publishes_only_valid_candidate() -> void:
	var content := _content()
	var raw := JSON.parse_string('{"weapons":[{"instance_id":1.0,"content_id":"fixture:weapon/a","quality":1.0}]}') as Dictionary
	assert_int(typeof((raw.weapons[0] as Dictionary).instance_id)).is_equal(TYPE_FLOAT)
	var parsed := INVENTORY.parse_records(raw.weapons, 2.0, content)
	assert_int(parsed.error).is_equal(OK)
	assert_str(parsed.path).is_empty()
	if parsed.error != OK:
		return
	var inventory: Variant = parsed.inventory
	assert_object(inventory).is_not_null()
	assert_array(inventory.records()).is_equal([
		{"instance_id": 1, "content_id": WEAPON_A, "quality": 1},
	])
	assert_int(inventory.next_id()).is_equal(2)


func test_parse_records_rejects_malformed_integer_values_and_reports_schema_paths() -> void:
	var content := _content()
	for case_data in [
		[[{"instance_id": true, "content_id": WEAPON_A, "quality": 1}], 2, "weapons[0].instance_id"],
		[[{"instance_id": "1", "content_id": WEAPON_A, "quality": 1}], 2, "weapons[0].instance_id"],
		[[{"instance_id": 1.5, "content_id": WEAPON_A, "quality": 1}], 2, "weapons[0].instance_id"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": true}], 2, "weapons[0].quality"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 5}], 2, "weapons[0].quality"],
		[[{"instance_id": 1, "content_id": &"fixture:weapon/missing", "quality": 1}], 2, "weapons[0].content_id"],
		[[{"instance_id": INVENTORY.MAX_ID, "content_id": WEAPON_A, "quality": 1}], INVENTORY.MAX_ID, "weapons[0].instance_id"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1}], true, "next_weapon_instance_id"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1}], 1.5, "next_weapon_instance_id"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1}], INVENTORY.MAX_ID + 1, "next_weapon_instance_id"],
		[[{"instance_id": 1.0e20, "content_id": WEAPON_A, "quality": 1}], 2, "weapons[0].instance_id"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1}], 1.0e20, "next_weapon_instance_id"],
	]:
		var parsed := INVENTORY.parse_records(case_data[0], case_data[1], content)
		assert_object(parsed.inventory).is_null()
		assert_int(parsed.error).is_not_equal(OK)
		assert_str(parsed.path).is_equal(case_data[2])


func test_parse_records_rejects_malformed_record_shapes_duplicates_and_capacity_without_touching_raw() -> void:
	var content := _content()
	var over_capacity: Array = []
	for index in 7:
		over_capacity.append({"instance_id": index + 1, "content_id": WEAPON_A, "quality": 1})
	for case_data in [
		[true, 2, "weapons"],
		[[true], 2, "weapons[0]"],
		[[{"instance_id": 1, "content_id": WEAPON_A}], 2, "weapons[0]"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1, "extra": 0}], 2, "weapons[0]"],
		[[{"instance_id": 1, "content_id": WEAPON_A, "quality": 1}, {"instance_id": 1, "content_id": WEAPON_B, "quality": 1}], 3, "weapons[1].instance_id"],
		[over_capacity, 8, "weapons"],
	]:
		var raw: Variant = case_data[0]
		var raw_before: Variant = raw.duplicate(true) if raw is Array or raw is Dictionary else raw
		var parsed := INVENTORY.parse_records(raw, case_data[1], content)
		assert_object(parsed.inventory).is_null()
		assert_int(parsed.error).is_not_equal(OK)
		assert_str(parsed.path).is_equal(case_data[2])
		assert_bool(raw == raw_before).is_true()


func test_quality_rules_expose_exact_factors_sale_values_labels_and_colours() -> void:
	var factors := [1.0, 1.5, 2.0, 2.5]
	var sales := [4, 5, 7, 9]
	var labels := ["I", "II", "III", "IV"]
	var colours := [Color("e8e6dc"), Color("4c88df"), Color("c65ce2"), Color("ef6a67")]
	for index in 4:
		var quality := index + 1
		assert_bool(QUALITY_RULES.is_valid(quality)).is_true()
		assert_float(QUALITY_RULES.factor(quality)).is_equal(factors[index])
		assert_int(QUALITY_RULES.sale_price(10, quality)).is_equal(sales[index])
		assert_str(QUALITY_RULES.label(quality)).is_equal(labels[index])
		assert_bool(QUALITY_RULES.color(quality) == colours[index]).is_true()


func _content() -> ContentSnapshot:
	var pack := GogoContentPackDefinition.new()
	pack.pack_id = &"fixture.inventory"
	pack.pack_kind = &"weapon"
	for content_id in [WEAPON_A, WEAPON_B]:
		var weapon := GogoWeaponDefinition.new()
		weapon.content_id = content_id
		weapon.display_name = "Same Display Name"
		pack.definitions.append(weapon)
	var snapshot := ContentSnapshot.new()
	assert_int(snapshot.install_pack(pack)).is_equal(OK)
	snapshot.seal()
	return snapshot
