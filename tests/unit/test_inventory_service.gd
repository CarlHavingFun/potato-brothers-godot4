extends GdUnitTestSuite


func test_weapon_purchase_is_atomic_when_inventory_is_full() -> void:
	var run_state := RunState.new(1)
	run_state.materials = 100
	for index in InventoryState.MAX_WEAPON_SLOTS:
		assert_int(run_state.inventory.add_weapon(StringName("weapon_%d" % index), 1, 5)).is_not_equal(-1)

	var result := InventoryService.try_purchase_weapon(run_state, &"axe", 1, 40)

	assert_int(result).is_equal(InventoryService.NO_WEAPON_SLOT)
	assert_int(run_state.materials).is_equal(100)
	assert_int(run_state.inventory.weapon_count()).is_equal(6)


func test_full_inventory_purchase_auto_merges_lowest_matching_slot_with_detailed_result() -> void:
	var run_state := RunState.new(11)
	run_state.materials = 100
	assert_int(run_state.inventory.add_weapon(&"pistol", 1, 15)).is_equal(0)
	run_state.inventory.add_weapon(&"axe", 1, 5)
	run_state.inventory.add_weapon(&"wand", 1, 5)
	run_state.inventory.add_weapon(&"pistol", 1, 35)
	run_state.inventory.add_weapon(&"spear", 1, 5)
	run_state.inventory.add_weapon(&"smg", 1, 5)

	var detailed: Variant = InventoryService.new().call(
		"try_purchase_weapon_detailed", run_state, &"pistol", 1, 40
	)

	assert_bool(detailed is Dictionary).is_true()
	if detailed is Dictionary:
		assert_int(int(detailed.get("code", -1))).is_equal(InventoryService.OK)
		assert_str(str(detailed.get("mode", ""))).is_equal("auto_merge")
		assert_int(int(detailed.get("target_slot", -1))).is_equal(0)
		assert_int(int(detailed.get("resulting_tier", 0))).is_equal(2)
	assert_int(run_state.materials).is_equal(60)
	assert_int(run_state.inventory.weapon_count()).is_equal(InventoryState.MAX_WEAPON_SLOTS)
	assert_int(int(run_state.inventory.weapon_at(0).get("tier", 0))).is_equal(2)
	assert_int(int(run_state.inventory.weapon_at(0).get("paid_price", 0))).is_equal(55)
	assert_int(int(run_state.inventory.weapon_at(3).get("tier", 0))).is_equal(1)


func test_full_inventory_purchase_does_not_mutate_when_only_matching_weapon_is_tier_four() -> void:
	var run_state := RunState.new(12)
	run_state.materials = 100
	run_state.inventory.add_weapon(&"pistol", InventoryState.MAX_WEAPON_TIER, 80)
	for weapon_id in [&"axe", &"wand", &"spear", &"smg", &"punch"]:
		run_state.inventory.add_weapon(weapon_id, 1, 5)
	var before := run_state.inventory.to_dict()

	var result := InventoryService.try_purchase_weapon(run_state, &"pistol", InventoryState.MAX_WEAPON_TIER, 40)

	assert_int(result).is_equal(InventoryService.NO_WEAPON_SLOT)
	assert_int(run_state.materials).is_equal(100)
	assert_dict(run_state.inventory.to_dict()).is_equal(before)


func test_weapon_purchase_deducts_only_after_validation() -> void:
	var run_state := RunState.new(2)
	run_state.materials = 50

	var result := InventoryService.try_purchase_weapon(run_state, &"axe", 1, 40)

	assert_int(result).is_equal(InventoryService.OK)
	assert_int(run_state.materials).is_equal(10)
	assert_int(run_state.inventory.weapon_count()).is_equal(1)
	assert_str(run_state.inventory.weapon_at(0).get("weapon_id", "")).is_equal("axe")


func test_two_matching_weapons_combine_and_preserve_paid_value() -> void:
	var run_state := RunState.new(3)
	run_state.inventory.add_weapon(&"pistol", 2, 24)
	run_state.inventory.add_weapon(&"pistol", 2, 36)

	var result := InventoryService.try_combine_weapons(run_state, 0, 1)

	assert_int(result).is_equal(InventoryService.OK)
	assert_int(run_state.inventory.weapon_count()).is_equal(1)
	var weapon := run_state.inventory.weapon_at(0)
	assert_int(weapon.get("tier", 0)).is_equal(3)
	assert_int(weapon.get("paid_price", 0)).is_equal(60)


func test_tier_four_weapon_cannot_combine() -> void:
	var run_state := RunState.new(4)
	run_state.inventory.add_weapon(&"smg", 4, 100)
	run_state.inventory.add_weapon(&"smg", 4, 100)

	var result := InventoryService.try_combine_weapons(run_state, 0, 1)

	assert_int(result).is_equal(InventoryService.MAX_WEAPON_TIER)
	assert_int(run_state.inventory.weapon_count()).is_equal(2)


func test_selling_weapon_returns_seventy_five_percent() -> void:
	var run_state := RunState.new(5)
	run_state.inventory.add_weapon(&"wand", 1, 41)

	var result := InventoryService.try_sell_weapon(run_state, 0)

	assert_int(result).is_equal(InventoryService.OK)
	assert_int(run_state.materials).is_equal(30)
	assert_int(run_state.inventory.weapon_count()).is_zero()


func test_passive_purchase_honors_max_stack_without_charging() -> void:
	var run_state := RunState.new(6)
	run_state.materials = 80
	run_state.inventory.add_passive(&"unique_badge", 1)

	var result := InventoryService.try_purchase_passive(run_state, &"unique_badge", 25, 1)

	assert_int(result).is_equal(InventoryService.MAX_PASSIVE_STACK)
	assert_int(run_state.materials).is_equal(80)
	assert_int(run_state.inventory.passive_count(&"unique_badge")).is_equal(1)


func test_inventory_finds_only_matching_weapon_family_and_tier() -> void:
	var inventory := InventoryState.new()
	inventory.add_weapon(&"punch", 1, 10)
	inventory.add_weapon(&"punch", 2, 20)
	inventory.add_weapon(&"punch", 1, 30)
	inventory.add_weapon(&"pistol", 1, 40)

	var slots := inventory.find_weapon_slots(&"punch", 1)

	assert_array(slots).contains_exactly([0, 2])
