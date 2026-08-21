extends GdUnitTestSuite


const SHOP_SERVICE_PATH := "res://core/services/shop_service.gd"


func test_shop_offers_are_reproducible_for_the_same_run_seed() -> void:
	assert_bool(ResourceLoader.exists(SHOP_SERVICE_PATH)).is_true()
	if not ResourceLoader.exists(SHOP_SERVICE_PATH):
		return
	var script: Script = load(SHOP_SERVICE_PATH)
	var first: RefCounted = script.new(77)
	var second: RefCounted = script.new(77)
	var pool: Array[ItemBase] = Content.catalog.get_shop_items()

	var first_offer: Array = first.call(
		"select_offers", pool, 5, 12.0, Global.SHOP_PROBABILITY_CONFIG, 4
	)
	var second_offer: Array = second.call(
		"select_offers", pool, 5, 12.0, Global.SHOP_PROBABILITY_CONFIG, 4
	)

	assert_array(first_offer).is_equal(second_offer)
	assert_int(first_offer.size()).is_equal(4)


func test_reference_rarity_curve_uses_cumulative_tier_thresholds() -> void:
	var service := ShopService.new(701)

	assert_array(service.calculate_tier_probabilities(
		1, 0.0, Global.SHOP_PROBABILITY_CONFIG
	)).contains_exactly([1.0, 0.0, 0.0, 0.0])
	_assert_probabilities_close(
		service.calculate_tier_probabilities(2, 0.0, Global.SHOP_PROBABILITY_CONFIG),
		[0.94, 0.06, 0.0, 0.0]
	)
	_assert_probabilities_close(
		service.calculate_tier_probabilities(4, 0.0, Global.SHOP_PROBABILITY_CONFIG),
		[0.82, 0.16, 0.02, 0.0]
	)
	_assert_probabilities_close(
		service.calculate_tier_probabilities(8, 0.0, Global.SHOP_PROBABILITY_CONFIG),
		[0.58, 0.32, 0.0977, 0.0023]
	)


func test_luck_changes_only_tiers_already_unlocked() -> void:
	var service := ShopService.new(702)

	assert_array(service.calculate_tier_probabilities(
		1, 10000.0, Global.SHOP_PROBABILITY_CONFIG
	)).contains_exactly([1.0, 0.0, 0.0, 0.0])
	_assert_probabilities_close(
		service.calculate_tier_probabilities(4, -100.0, Global.SHOP_PROBABILITY_CONFIG),
		[1.0, 0.0, 0.0, 0.0]
	)
	var neutral := service.calculate_tier_probabilities(4, 0.0, Global.SHOP_PROBABILITY_CONFIG)
	var lucky := service.calculate_tier_probabilities(4, 100.0, Global.SHOP_PROBABILITY_CONFIG)
	assert_bool(float(lucky[0]) < float(neutral[0])).is_true()
	assert_float(float(lucky[2])).is_greater(float(neutral[2]))
	assert_float(float(lucky[3])).is_zero()


func test_shop_purchase_delegates_to_atomic_inventory_transaction() -> void:
	assert_bool(ResourceLoader.exists(SHOP_SERVICE_PATH)).is_true()
	if not ResourceLoader.exists(SHOP_SERVICE_PATH):
		return
	var service: RefCounted = load(SHOP_SERVICE_PATH).new(1)
	var run := RunState.new(1)
	run.materials = 0
	var pistol: ItemWeapon = Content.catalog.get_weapon(&"weapon/pistol").tiers[0]

	var result: int = service.call("try_purchase", run, pistol, Content.catalog)

	assert_int(result).is_equal(InventoryService.INSUFFICIENT_MATERIALS)
	assert_int(run.materials).is_zero()
	assert_int(run.inventory.weapon_count()).is_zero()


func test_shop_slot_purchase_exposes_auto_merge_detail_without_changing_legacy_result() -> void:
	var service := ShopService.new(13)
	var run := RunState.new(13)
	run.materials = 100
	var pistol: ItemWeapon = Content.catalog.get_weapon(&"weapon/pistol").tiers[0]
	var pistol_id := Content.catalog.get_item_stable_id(pistol)
	run.inventory.add_weapon(pistol_id, 1, 20)
	for weapon_id in [&"axe", &"wand", &"spear", &"smg", &"punch"]:
		run.inventory.add_weapon(weapon_id, 1, 5)
	service.store_offers(run, [pistol], Content.catalog)

	var detailed: Variant = service.call("try_purchase_offer_detailed", run, 0, Content.catalog)

	assert_bool(detailed is Dictionary).is_true()
	if detailed is Dictionary:
		assert_int(int(detailed.get("code", -1))).is_equal(InventoryService.OK)
		assert_str(str(detailed.get("mode", ""))).is_equal("auto_merge")
		assert_int(int(detailed.get("target_slot", -1))).is_equal(0)
	assert_int(run.materials).is_equal(100 - service.purchase_price(run, pistol))
	assert_bool(run.shop_slots[0].purchased).is_true()
	assert_int(int(run.inventory.weapon_at(0).get("tier", 0))).is_equal(2)


func test_refresh_price_increases_and_transaction_rolls_back_when_unaffordable() -> void:
	var service := ShopService.new(8)
	var run := RunState.new(8)
	run.materials = 20

	assert_int(service.refresh_price(5, 0)).is_equal(7)
	assert_int(service.try_refresh(run, 5)).is_equal(InventoryService.OK)
	assert_int(run.materials).is_equal(13)
	assert_int(run.shop_refresh_count).is_equal(1)
	run.materials = 0
	assert_int(service.try_refresh(run, 5)).is_equal(InventoryService.INSUFFICIENT_MATERIALS)
	assert_int(run.materials).is_zero()
	assert_int(run.shop_refresh_count).is_equal(1)


func test_shop_lock_and_offers_are_part_of_run_state() -> void:
	var service := ShopService.new(9)
	var run := RunState.new(9)
	var offers := Content.catalog.get_shop_items().slice(0, 4)

	service.store_offers(run, offers, Content.catalog)
	service.set_locked(run, true)

	assert_bool(run.shop_locked).is_true()
	assert_int(run.shop_offer_ids.size()).is_equal(4)
	assert_array(service.resolve_offers(run, Content.catalog)).has_size(4)


func test_early_shops_guarantee_weapons_without_repeating_a_weapon_family() -> void:
	var pool: Array[ItemBase] = Content.catalog.get_shop_items()
	for wave in [1, 2]:
		var offers: Array = ShopService.new(700 + wave).select_offers(
			pool, wave, 0.0, Global.SHOP_PROBABILITY_CONFIG, 4, Content.catalog, []
		)
		assert_int(offers.filter(func(item: Variant): return item is ItemWeapon).size()).is_greater_equal(2)
		assert_int(_stable_ids(offers).size()).is_equal(offers.size())
	for wave in [3, 4, 5]:
		var offers: Array = ShopService.new(700 + wave).select_offers(
			pool, wave, 0.0, Global.SHOP_PROBABILITY_CONFIG, 4, Content.catalog, []
		)
		assert_int(offers.filter(func(item: Variant): return item is ItemWeapon).size()).is_greater_equal(1)
		assert_int(_stable_ids(offers).size()).is_equal(offers.size())


func test_first_shop_never_leaks_locked_tiers_through_small_pool_fallbacks() -> void:
	var pool: Array[ItemBase] = []
	for tier in Global.UpgradeTier.size():
		var matching := Content.catalog.get_shop_items().filter(
			func(item: ItemBase): return int(item.item_tier) == tier
		)
		assert_bool(not matching.is_empty()).is_true()
		pool.append(matching[0])

	for seed in range(710, 730):
		var offers := ShopService.new(seed).select_offers(
			pool, 1, 10000.0, Global.SHOP_PROBABILITY_CONFIG, 4, Content.catalog, []
		)
		assert_bool(not offers.is_empty()).is_true()
		for offer: ItemBase in offers:
			assert_int(int(offer.item_tier)).is_equal(Global.UpgradeTier.COMMON)


func test_buying_every_shop_slot_grants_exactly_one_free_refresh() -> void:
	var service := ShopService.new(812)
	var run := RunState.new(812)
	run.materials = 10000
	var offers: Array = service.select_offers(
		Content.catalog.get_shop_items(), 1, 0.0, Global.SHOP_PROBABILITY_CONFIG,
		4, Content.catalog, []
	)
	service.store_offers(run, offers, Content.catalog)

	for slot_index in RunState.SHOP_SLOT_COUNT:
		assert_int(service.try_purchase_offer(run, slot_index, Content.catalog)).is_equal(InventoryService.OK)

	assert_int(service.free_refresh_count(run)).is_equal(1)
	var restored := RunState.from_dict(run.to_dict())
	assert_int(service.free_refresh_count(restored)).is_equal(1)
	assert_int(service.refresh_price_for_run(run, 1)).is_zero()
	var materials_before := run.materials
	assert_int(service.try_refresh(run, 1)).is_equal(InventoryService.OK)
	assert_int(run.materials).is_equal(materials_before)
	assert_int(service.free_refresh_count(run)).is_zero()
	assert_bool(service.refresh_price_for_run(run, 1) > 0).is_true()


func _stable_ids(items: Array) -> Dictionary:
	var result := {}
	for item: ItemBase in items:
		result[String(Content.catalog.get_item_stable_id(item))] = true
	return result


func _assert_probabilities_close(actual: Array[float], expected: Array[float]) -> void:
	assert_int(actual.size()).is_equal(expected.size())
	for index in expected.size():
		assert_float(actual[index]).is_equal_approx(expected[index], 0.00001)
