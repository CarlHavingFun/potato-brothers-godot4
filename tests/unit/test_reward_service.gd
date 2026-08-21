extends GdUnitTestSuite


const REWARD_SERVICE_PATH := "res://core/services/reward_service.gd"


func test_reward_queues_are_owned_by_run_state_and_cannot_underflow() -> void:
	assert_bool(ResourceLoader.exists(REWARD_SERVICE_PATH)).is_true()
	if not ResourceLoader.exists(REWARD_SERVICE_PATH):
		return
	var run := RunState.new(22)
	var service: RefCounted = load(REWARD_SERVICE_PATH).new(22)

	service.call("queue_level_ups", run, 2)
	service.call("queue_rewards", run, 1)

	assert_bool(service.call("claim_level_up", run)).is_true()
	assert_bool(service.call("claim_level_up", run)).is_true()
	assert_bool(service.call("claim_level_up", run)).is_false()
	assert_bool(service.call("claim_reward", run)).is_true()
	assert_bool(service.call("claim_reward", run)).is_false()
	assert_int(run.queued_level_ups).is_zero()
	assert_int(run.queued_rewards).is_zero()


func test_reward_offers_are_reproducible_for_the_same_run_seed() -> void:
	assert_bool(ResourceLoader.exists(REWARD_SERVICE_PATH)).is_true()
	if not ResourceLoader.exists(REWARD_SERVICE_PATH):
		return
	var script: Script = load(REWARD_SERVICE_PATH)
	var pool: Array[ItemUpgrade] = Content.catalog.get_upgrade_items()
	var first: RefCounted = script.new(98)
	var second: RefCounted = script.new(98)

	assert_array(first.call("select_unique", pool, 4)).is_equal(
		second.call("select_unique", pool, 4)
	)


func test_level_up_offers_follow_level_luck_and_reference_milestones() -> void:
	var service := RewardService.new(981)
	assert_bool(service.has_method("select_level_up_offers")).is_true()
	if not service.has_method("select_level_up_offers"):
		return
	var pool: Array[ItemUpgrade] = Content.catalog.get_upgrade_items()
	var run := RunState.new(981)
	run.player_stats.set_stat(StatId.LUCK, 10000.0)
	for expected in [
		{"level": 1, "tier": Global.UpgradeTier.COMMON},
		{"level": 5, "tier": Global.UpgradeTier.RARE},
		{"level": 10, "tier": Global.UpgradeTier.EPIC},
		{"level": 15, "tier": Global.UpgradeTier.EPIC},
		{"level": 20, "tier": Global.UpgradeTier.EPIC},
		{"level": 25, "tier": Global.UpgradeTier.LEGENDARY},
	]:
		run.level = int(expected.level)
		run.queued_level_ups = 1
		var offers: Array = service.call(
			"select_level_up_offers", pool, run, 4, Content.catalog
		)
		assert_int(offers.size()).is_equal(4)
		for offer: ItemUpgrade in offers:
			assert_int(_upgrade_tier(offer)).is_equal(int(expected.tier))
		assert_int(_upgrade_stat_ids(offers).size()).is_equal(offers.size())


func test_level_up_offer_sequence_uses_each_pending_level_and_is_reproducible() -> void:
	var first := RewardService.new(982)
	var second := RewardService.new(982)
	assert_bool(first.has_method("pending_level_up_level")).is_true()
	assert_bool(first.has_method("select_level_up_offers")).is_true()
	if not first.has_method("pending_level_up_level") \
		or not first.has_method("select_level_up_offers"):
		return
	var first_run := RunState.new(982)
	first_run.level = 5
	first_run.queued_level_ups = 2
	var second_run := RunState.from_dict(first_run.to_dict())

	assert_int(int(first.call("pending_level_up_level", first_run))).is_equal(4)
	var first_offers: Array = first.call(
		"select_level_up_offers", Content.catalog.get_upgrade_items(), first_run, 4, Content.catalog
	)
	var second_offers: Array = second.call(
		"select_level_up_offers", Content.catalog.get_upgrade_items(), second_run, 4, Content.catalog
	)
	assert_array(first_offers).is_equal(second_offers)
	assert_bool(first.claim_level_up(first_run)).is_true()
	assert_int(int(first.call("pending_level_up_level", first_run))).is_equal(5)


func test_experience_can_queue_multiple_level_ups_without_losing_remainder() -> void:
	var run := RunState.new(12)
	var service := RewardService.new(12)

	var levels_gained: int = service.add_experience(run, 36)

	assert_int(levels_gained).is_equal(2)
	assert_int(run.level).is_equal(3)
	assert_int(run.experience).is_equal(11)
	assert_int(run.queued_level_ups).is_equal(2)


func _upgrade_tier(item: ItemUpgrade) -> int:
	var definition := Content.catalog.get_upgrade_definition_for_item(item)
	return definition.quality if definition != null else -1


func _upgrade_stat_ids(items: Array) -> Dictionary:
	var result := {}
	for item: ItemUpgrade in items:
		var definition := Content.catalog.get_upgrade_definition_for_item(item)
		if definition != null:
			result[definition.stat_id] = true
	return result


func test_post_upgrade_phase_drains_upgrades_before_chest_and_shop() -> void:
	var run := RunState.new(12)
	var service := RewardService.new(12)
	run.queued_level_ups = 2
	run.queued_rewards = 1

	assert_int(service.claim_level_up_and_get_next_phase(run)).is_equal(RunPhase.UPGRADE)
	assert_int(service.claim_level_up_and_get_next_phase(run)).is_equal(RunPhase.CHEST)
	assert_int(service.finish_reward_and_get_next_phase(run)).is_equal(RunPhase.SHOP)


func test_reward_claim_is_atomic_and_recycle_consumes_exactly_one_chest() -> void:
	var run := RunState.new(4)
	var service := RewardService.new(4)
	var pistol: ItemWeapon = Content.catalog.get_weapon(&"weapon/pistol").tiers[0]
	run.queued_rewards = 2

	assert_int(service.try_claim_item(run, pistol, Content.catalog)).is_equal(InventoryService.OK)
	assert_int(run.inventory.weapon_count()).is_equal(1)
	assert_int(run.queued_rewards).is_equal(1)
	var before_recycle := run.materials
	var recycled: int = service.recycle_item(run, pistol)
	assert_int(recycled).is_equal(maxi(1, floori(pistol.item_cost * 0.5)))
	assert_int(run.materials).is_equal(before_recycle + recycled)
	assert_int(run.queued_rewards).is_zero()


func test_early_reward_chests_cannot_roll_late_weapon_tiers() -> void:
	var service := RewardService.new(99)
	var pool: Array[ItemBase] = Content.catalog.get_shop_items()

	for draw in 20:
		var reward: ItemBase = service.select_reward(pool, 1)
		assert_object(reward).is_not_null()
		assert_int(int(reward.item_tier)).is_equal(Global.UpgradeTier.COMMON)


func test_chests_are_driven_by_elite_and_boss_drops_not_normal_enemies() -> void:
	var run := RunState.new(77)
	var service := RewardService.new(77)

	assert_int(service.queue_enemy_drop(run, [&"normal"])).is_zero()
	assert_int(run.queued_rewards).is_zero()
	assert_int(service.queue_enemy_drop(run, [&"elite"])).is_equal(1)
	assert_int(service.queue_enemy_drop(run, [&"boss"])).is_equal(1)
	assert_int(run.queued_rewards).is_equal(2)


func test_resolving_an_enemy_drop_rolls_once_and_keeps_queue_api_compatible() -> void:
	var direct_run := RunState.new(78)
	var compatibility_run := RunState.new(78)
	var direct := RewardService.new(78)
	var compatibility := RewardService.new(78)

	var kind := direct.resolve_enemy_drop(direct_run, [&"elite"])
	var queued := compatibility.queue_enemy_drop(compatibility_run, [&"elite"])

	assert_bool(direct.is_chest_drop(kind)).is_true()
	assert_int(queued).is_equal(1)
	assert_int(direct.rng.state).is_equal(compatibility.rng.state)
	assert_int(direct_run.queued_rewards).is_equal(compatibility_run.queued_rewards)


func test_upgrade_refresh_spends_materials_increases_price_and_rolls_back() -> void:
	var run := RunState.new(606)
	var service := RewardService.new(606)
	run.materials = 20
	run.queued_level_ups = 1
	var first_price: int = service.upgrade_refresh_price(run, 8)

	assert_int(service.try_refresh_upgrades(run, 8)).is_equal(InventoryService.OK)
	assert_int(run.materials).is_equal(20 - first_price)
	assert_int(run.upgrade_refresh_count).is_equal(1)
	assert_bool(service.upgrade_refresh_price(run, 8) > first_price).is_true()
	run.materials = 0
	assert_int(service.try_refresh_upgrades(run, 8)).is_equal(InventoryService.INSUFFICIENT_MATERIALS)
	assert_int(run.upgrade_refresh_count).is_equal(1)


func test_claiming_an_upgrade_resets_refresh_price_for_the_next_choice() -> void:
	var run := RunState.new(607)
	var service := RewardService.new(607)
	run.queued_level_ups = 2
	run.upgrade_refresh_count = 3

	assert_int(service.claim_level_up_and_get_next_phase(run)).is_equal(RunPhase.UPGRADE)
	assert_int(run.upgrade_refresh_count).is_zero()


func test_drop_rolls_are_reproducible_and_luck_increases_normal_chest_frequency() -> void:
	var first := RewardService.new(901)
	var second := RewardService.new(901)
	var first_rolls: Array[int] = []
	var second_rolls: Array[int] = []
	for draw in 128:
		first_rolls.append(first.roll_drop([&"normal"], 250.0, 12))
		second_rolls.append(second.roll_drop([&"normal"], 250.0, 12))

	assert_array(first_rolls).is_equal(second_rolls)
	assert_bool(first_rolls.any(func(kind: int): return first.is_chest_drop(kind))).is_true()


func test_elite_and_boss_drops_have_guaranteed_distinct_reward_floors() -> void:
	var run := RunState.new(902)
	var service := RewardService.new(902)
	assert_int(service.queue_enemy_drop(run, [&"elite"])).is_equal(1)
	assert_int(service.queue_enemy_drop(run, [&"boss"])).is_equal(1)

	var first_reward := service.select_reward(Content.catalog.get_shop_items(), 20, run)
	assert_object(first_reward).is_not_null()
	assert_int(int(first_reward.item_tier)).is_equal(Global.UpgradeTier.LEGENDARY)
	assert_bool(service.claim_reward(run)).is_true()
	var second_reward := service.select_reward(Content.catalog.get_shop_items(), 20, run)
	assert_object(second_reward).is_not_null()
	assert_bool(int(second_reward.item_tier) >= Global.UpgradeTier.EPIC).is_true()


func test_tree_drop_table_can_produce_material_healing_and_chests() -> void:
	var service := RewardService.new(903)
	var kinds := {}
	for draw in 256:
		kinds[service.roll_drop([&"source/tree"], 75.0, 8)] = true

	assert_bool(kinds.has(service.DROP_MATERIAL)).is_true()
	assert_bool(kinds.has(service.DROP_HEAL)).is_true()
	assert_bool(kinds.has(service.DROP_CHEST)).is_true()


func test_reward_quality_queue_survives_run_state_round_trip() -> void:
	var run := RunState.new(904)
	var service := RewardService.new(904)
	service.queue_enemy_drop(run, [&"elite"])
	service.queue_enemy_drop(run, [&"boss"])

	var restored := RunState.from_dict(run.to_dict())

	assert_int(restored.queued_rewards).is_equal(2)
	assert_array(restored.queued_reward_floors).contains_exactly_in_any_order([
		Global.UpgradeTier.EPIC,
		Global.UpgradeTier.LEGENDARY,
	])


func test_uncollected_materials_are_banked_and_double_future_pickups_once() -> void:
	var run := RunState.new(905)
	var service := RewardService.new(905)

	assert_int(service.bank_materials(run, 7)).is_equal(7)
	assert_int(run.material_bag).is_equal(7)
	assert_int(service.collect_material_pickup(run, 4)).is_equal(8)
	assert_int(run.materials).is_equal(8)
	assert_int(run.experience).is_equal(8)
	assert_int(run.material_bag).is_equal(3)
	assert_int(service.collect_material_pickup(run, 5)).is_equal(8)
	assert_int(run.materials).is_equal(16)
	assert_int(run.material_bag).is_zero()


func test_material_bag_survives_checkpoint_and_old_saves_default_to_empty() -> void:
	var run := RunState.new(906)
	run.material_bag = 13

	var restored := RunState.from_dict(run.to_dict())
	var legacy := RunState.from_dict({"random_seed": 906, "materials": 4})

	assert_int(restored.material_bag).is_equal(13)
	assert_int(legacy.material_bag).is_zero()


func test_abandoned_reward_floor_cannot_leak_into_a_later_chest() -> void:
	var run := RunState.new(907)
	var service := RewardService.new(907)
	run.queued_rewards = 0
	run.queued_reward_floors = [Global.UpgradeTier.LEGENDARY]

	service.queue_rewards(run, 1)
	var reward := service.select_reward(Content.catalog.get_shop_items(), 1, run)

	assert_array(run.queued_reward_floors).contains_exactly([Global.UpgradeTier.COMMON])
	assert_object(reward).is_not_null()
	assert_int(int(reward.item_tier)).is_equal(Global.UpgradeTier.COMMON)
