class_name RewardService
extends RefCounted


const STREAM_OFFSET := 0x52455744

var rng := RandomNumberGenerator.new()


func _init(run_seed: int = 0) -> void:
	rng.seed = run_seed ^ STREAM_OFFSET


func queue_level_ups(run_state: RunState, amount: int = 1) -> bool:
	if run_state == null or amount <= 0:
		return false
	run_state.queued_level_ups += amount
	return true


func queue_rewards(run_state: RunState, amount: int = 1) -> bool:
	if run_state == null or amount <= 0:
		return false
	run_state.queued_rewards += amount
	return true


func claim_level_up(run_state: RunState) -> bool:
	if run_state == null or run_state.queued_level_ups <= 0:
		return false
	run_state.queued_level_ups -= 1
	return true


func claim_reward(run_state: RunState) -> bool:
	if run_state == null or run_state.queued_rewards <= 0:
		return false
	run_state.queued_rewards -= 1
	return true


func select_unique(pool: Array, requested_count: int) -> Array:
	var available := pool.duplicate()
	var result: Array = []
	var target_count := mini(maxi(0, requested_count), available.size())
	while result.size() < target_count:
		result.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
	return result
