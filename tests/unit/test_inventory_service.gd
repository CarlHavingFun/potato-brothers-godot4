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
