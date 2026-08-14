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


func test_experience_can_queue_multiple_level_ups_without_losing_remainder() -> void:
	var run := RunState.new(12)
	var service := RewardService.new(12)

	var levels_gained: int = service.add_experience(run, 36)

	assert_int(levels_gained).is_equal(2)
	assert_int(run.level).is_equal(3)
	assert_int(run.experience).is_equal(11)
	assert_int(run.queued_level_ups).is_equal(2)


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
