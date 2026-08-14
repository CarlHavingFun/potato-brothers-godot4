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
