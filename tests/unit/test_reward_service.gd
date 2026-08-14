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
