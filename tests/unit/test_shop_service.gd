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
