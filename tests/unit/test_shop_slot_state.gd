extends GdUnitTestSuite


func test_each_shop_slot_locks_and_serializes_independently() -> void:
	var service := ShopService.new(17)
	var run := RunState.new(17)
	var offers := Content.catalog.get_shop_items().slice(0, 4)
	service.store_offers(run, offers, Content.catalog)

	assert_bool(service.set_slot_locked(run, 1, true)).is_true()
	var locked_id: StringName = run.shop_slots[1].offer_id
	var restored := RunState.from_dict(run.to_dict())

	assert_int(restored.shop_slots.size()).is_equal(4)
	assert_bool(restored.shop_slots[0].locked).is_false()
	assert_bool(restored.shop_slots[1].locked).is_true()
	assert_str(str(restored.shop_slots[1].offer_id)).is_equal(str(locked_id))


func test_storing_new_offers_replaces_only_unlocked_slots() -> void:
	var service := ShopService.new(19)
	var run := RunState.new(19)
	run.materials = 100
	var pool := Content.catalog.get_shop_items()
	service.store_offers(run, pool.slice(0, 4), Content.catalog)
	service.set_slot_locked(run, 2, true)
	var locked: Dictionary = run.shop_slots[2].to_dict()

	assert_int(service.try_refresh(run, 1)).is_equal(InventoryService.OK)
	service.store_offers(run, pool.slice(4, 7), Content.catalog)

	assert_dict(run.shop_slots[2].to_dict()).is_equal(locked)
	assert_str(str(run.shop_slots[0].offer_id)).is_equal(str(Content.catalog.get_item_stable_id(pool[4])))
	assert_str(str(run.shop_slots[1].offer_id)).is_equal(str(Content.catalog.get_item_stable_id(pool[5])))
	assert_str(str(run.shop_slots[3].offer_id)).is_equal(str(Content.catalog.get_item_stable_id(pool[6])))


func test_refresh_cost_scales_with_the_number_of_unlocked_slots() -> void:
	var service := ShopService.new(29)
	var run := RunState.new(29)
	run.materials = 20
	service.set_slot_locked(run, 0, true)
	service.set_slot_locked(run, 3, true)

	assert_int(service.refresh_price_for_slots(5, 0, 2)).is_equal(4)
	assert_int(service.try_refresh(run, 5)).is_equal(InventoryService.OK)
	assert_int(run.materials).is_equal(16)
	assert_bool(run.shop_slots[0].locked).is_true()
	assert_bool(run.shop_slots[3].locked).is_true()


func test_tag_affinity_is_limited_and_does_not_remove_randomness() -> void:
	var service := ShopService.new(37)

	assert_float(service.tag_affinity_weight([&"weapon/ranged"], [])).is_equal(1.0)
	assert_float(service.tag_affinity_weight(
		[&"weapon/ranged", &"mechanic/rapid"],
		[&"weapon/ranged", &"mechanic/rapid"]
	)).is_equal(1.75)
	assert_float(service.tag_affinity_weight(
		[&"weapon/ranged", &"mechanic/rapid", &"element/fire"],
		[&"weapon/ranged", &"mechanic/rapid", &"element/fire"]
	)).is_equal(1.75)
