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
