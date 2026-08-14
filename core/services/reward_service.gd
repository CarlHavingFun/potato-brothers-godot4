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


func experience_required_for_level(level: int) -> int:
	return 10 + maxi(0, level - 1) * 5


func add_experience(run_state: RunState, amount: int) -> int:
	if run_state == null or amount <= 0:
		return 0
	run_state.experience += amount
	var levels_gained := 0
	var required := experience_required_for_level(run_state.level)
	while run_state.experience >= required:
		run_state.experience -= required
		run_state.level += 1
		run_state.queued_level_ups += 1
		levels_gained += 1
		required = experience_required_for_level(run_state.level)
	return levels_gained


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


func claim_level_up_and_get_next_phase(run_state: RunState) -> int:
	if not claim_level_up(run_state):
		return RunPhase.CHEST if run_state != null and run_state.queued_rewards > 0 else RunPhase.SHOP
	if run_state.queued_level_ups > 0:
		return RunPhase.UPGRADE
	return RunPhase.CHEST if run_state.queued_rewards > 0 else RunPhase.SHOP


func finish_reward_and_get_next_phase(run_state: RunState) -> int:
	claim_reward(run_state)
	return RunPhase.CHEST if run_state != null and run_state.queued_rewards > 0 else RunPhase.SHOP


func try_claim_item(run_state: RunState, item: ItemBase, content_catalog: ContentCatalog) -> int:
	if run_state == null or item == null or content_catalog == null or run_state.queued_rewards <= 0:
		return InventoryService.INVALID_REQUEST
	var result := InventoryService.INVALID_REQUEST
	if item is ItemWeapon:
		result = InventoryService.try_purchase_weapon(
			run_state,
			content_catalog.get_item_stable_id(item),
			int(item.item_tier) + 1,
			0
		)
	elif item is ItemPassive:
		var definition := content_catalog.get_passive_definition_for_item(item)
		result = InventoryService.try_purchase_passive(
			run_state,
			content_catalog.get_item_stable_id(item),
			0,
			definition.max_stack if definition != null else item.max_stack
		)
	if result == InventoryService.OK:
		run_state.queued_rewards -= 1
	return result


func recycle_item(run_state: RunState, item: ItemBase) -> int:
	if run_state == null or item == null or run_state.queued_rewards <= 0:
		return 0
	var materials := maxi(1, floori(item.item_cost * 0.5))
	run_state.materials += materials
	run_state.queued_rewards -= 1
	return materials


func select_unique(pool: Array, requested_count: int) -> Array:
	var available := pool.duplicate()
	var result: Array = []
	var target_count := mini(maxi(0, requested_count), available.size())
	while result.size() < target_count:
		result.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
	return result


func select_reward(pool: Array[ItemBase], current_wave: int) -> ItemBase:
	var maximum_tier := Global.UpgradeTier.COMMON
	if current_wave >= 7:
		maximum_tier = Global.UpgradeTier.LEGENDARY
	elif current_wave >= 4:
		maximum_tier = Global.UpgradeTier.EPIC
	elif current_wave >= 2:
		maximum_tier = Global.UpgradeTier.RARE
	var available: Array[ItemBase] = []
	for item: ItemBase in pool:
		if item != null and int(item.item_tier) <= maximum_tier:
			available.append(item)
	if available.is_empty():
		return null
	return available[rng.randi_range(0, available.size() - 1)]
