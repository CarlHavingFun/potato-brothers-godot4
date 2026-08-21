class_name RewardService
extends RefCounted


const STREAM_OFFSET := 0x52455744
const DROP_NONE := DropTableDef.DropKind.NONE
const DROP_MATERIAL := DropTableDef.DropKind.MATERIAL
const DROP_HEAL := DropTableDef.DropKind.HEAL
const DROP_CHEST := DropTableDef.DropKind.CHEST
const DROP_LEGENDARY_CHEST := DropTableDef.DropKind.LEGENDARY_CHEST

var rng := RandomNumberGenerator.new()
var drop_table := DropTableDef.new()


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
	if run_state.queued_rewards <= 0:
		run_state.queued_reward_floors.clear()
	run_state.queued_rewards += amount
	for _reward_index in amount:
		run_state.queued_reward_floors.append(Global.UpgradeTier.COMMON)
	return true


func queue_enemy_drop(run_state: RunState, enemy_tags: Array[StringName]) -> int:
	return 1 if is_chest_drop(resolve_enemy_drop(run_state, enemy_tags)) else 0


func resolve_enemy_drop(run_state: RunState, enemy_tags: Array[StringName]) -> int:
	if run_state == null:
		return DROP_NONE
	var luck: float = run_state.player_stats.get_stat(StatId.LUCK)
	var drop_kind: int = roll_drop(enemy_tags, luck, run_state.wave)
	if not is_chest_drop(drop_kind):
		return drop_kind
	var reward_floor: int = Global.UpgradeTier.COMMON
	if drop_kind == DROP_LEGENDARY_CHEST:
		reward_floor = Global.UpgradeTier.LEGENDARY
	elif &"elite" in enemy_tags:
		reward_floor = Global.UpgradeTier.EPIC
	elif luck >= 100.0:
		reward_floor = Global.UpgradeTier.RARE
	_queue_reward_floor(run_state, reward_floor)
	return drop_kind


func roll_drop(
	source_tags: Array[StringName],
	luck: float,
	current_wave: int,
	unit_roll: float = -1.0
) -> int:
	var resolved_roll: float = rng.randf() if unit_roll < 0.0 else unit_roll
	return drop_table.roll(drop_table.weights_for(source_tags, luck, current_wave), resolved_roll)


func is_chest_drop(drop_kind: int) -> bool:
	return drop_kind in [DROP_CHEST, DROP_LEGENDARY_CHEST]


func collect_world_drop(run_state: RunState, drop_kind: int, amount: int = 1) -> int:
	if run_state == null or amount <= 0:
		return 0
	match drop_kind:
		DROP_MATERIAL:
			return collect_material_pickup(run_state, amount)
		DROP_CHEST:
			_queue_reward_floor(run_state, Global.UpgradeTier.COMMON)
			return 1
		DROP_LEGENDARY_CHEST:
			_queue_reward_floor(run_state, Global.UpgradeTier.LEGENDARY)
			return 1
	return 0


func bank_materials(run_state: RunState, amount: int) -> int:
	if run_state == null or amount <= 0:
		return 0
	run_state.material_bag += amount
	return amount


func collect_material_pickup(run_state: RunState, amount: int) -> int:
	if run_state == null or amount <= 0:
		return 0
	var bag_bonus: int = mini(amount, run_state.material_bag)
	run_state.material_bag -= bag_bonus
	var collected_total := amount + bag_bonus
	run_state.materials += collected_total
	add_experience(run_state, collected_total)
	return collected_total


func experience_required_for_level(level: int) -> int:
	return 10 + maxi(0, level - 1) * 5


func add_experience(run_state: RunState, amount: int) -> int:
	if run_state == null or amount <= 0:
		return 0
	var scaled_experience := (
		float(amount) * run_state.experience_gain_multiplier
		+ run_state.experience_gain_remainder
	)
	var whole_experience := maxi(0, floori(scaled_experience))
	run_state.experience_gain_remainder = clampf(
		scaled_experience - whole_experience, 0.0, 0.999999
	)
	run_state.experience += whole_experience
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
	run_state.upgrade_refresh_count = 0
	return true


func upgrade_refresh_price(run_state: RunState, current_wave: int) -> int:
	if run_state == null:
		return 0
	return maxi(1, 1 + floori(float(maxi(1, current_wave)) / 5.0)) + run_state.upgrade_refresh_count * 2


func try_refresh_upgrades(run_state: RunState, current_wave: int) -> int:
	if run_state == null or run_state.queued_level_ups <= 0:
		return InventoryService.INVALID_REQUEST
	var price := upgrade_refresh_price(run_state, current_wave)
	if run_state.materials < price:
		return InventoryService.INSUFFICIENT_MATERIALS
	run_state.materials -= price
	run_state.upgrade_refresh_count += 1
	return InventoryService.OK


func claim_reward(run_state: RunState) -> bool:
	if run_state == null or run_state.queued_rewards <= 0:
		return false
	_consume_reward(run_state)
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
		if not _weapon_allowed_for_run(run_state, item as ItemWeapon, content_catalog):
			return InventoryService.INVALID_REQUEST
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
		_consume_reward(run_state)
	return result


func recycle_item(run_state: RunState, item: ItemBase) -> int:
	if run_state == null or item == null or run_state.queued_rewards <= 0:
		return 0
	var materials := maxi(1, floori(
		item.item_cost * 0.5 * run_state.recycle_value_multiplier
	))
	run_state.materials += materials
	_consume_reward(run_state)
	return materials


func select_unique(pool: Array, requested_count: int) -> Array:
	var available := pool.duplicate()
	var result: Array = []
	var target_count := mini(maxi(0, requested_count), available.size())
	while result.size() < target_count:
		result.append(available.pop_at(rng.randi_range(0, available.size() - 1)))
	return result


func pending_level_up_level(run_state: RunState) -> int:
	if run_state == null:
		return 1
	if run_state.queued_level_ups <= 0:
		return maxi(1, run_state.level)
	return maxi(1, run_state.level - run_state.queued_level_ups + 1)


func select_level_up_offers(
	pool: Array[ItemUpgrade],
	run_state: RunState,
	requested_count: int = 4,
	content_catalog: ContentCatalog = null
) -> Array[ItemUpgrade]:
	var result: Array[ItemUpgrade] = []
	if run_state == null or requested_count <= 0 or pool.is_empty():
		return result
	var catalog := content_catalog if content_catalog != null else Content.catalog
	var level := pending_level_up_level(run_state)
	var forced_tier := _forced_level_up_tier(level)
	var probabilities: Array[float]
	if forced_tier >= 0:
		probabilities = [0.0, 0.0, 0.0, 0.0]
		probabilities[forced_tier] = 1.0
	else:
		probabilities = ShopService.new(0).calculate_tier_probabilities(
			level,
			run_state.player_stats.get_stat(StatId.LUCK),
			Global.UPGRADE_PROBABILITY_CONFIG
		)
	var target_count := mini(requested_count, pool.size())
	var attempts := 0
	while result.size() < target_count and attempts < maxi(32, pool.size() * 8):
		attempts += 1
		var desired_tier := _roll_upgrade_tier(probabilities)
		var candidates := pool.filter(
			func(item: ItemUpgrade):
				return (
					_upgrade_quality(item, catalog) == desired_tier
					and not _contains_upgrade_stat(result, item, catalog)
				)
		)
		if candidates.is_empty():
			continue
		result.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return result


func _forced_level_up_tier(level: int) -> int:
	if level == 1:
		return Global.UpgradeTier.COMMON
	if level == 5:
		return Global.UpgradeTier.RARE
	if level in [10, 15, 20]:
		return Global.UpgradeTier.EPIC
	if level >= 25 and level % 5 == 0:
		return Global.UpgradeTier.LEGENDARY
	return -1


func _roll_upgrade_tier(probabilities: Array[float]) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for tier in probabilities.size():
		cumulative += probabilities[tier]
		if roll <= cumulative:
			return tier
	return Global.UpgradeTier.COMMON


func _upgrade_quality(item: ItemUpgrade, content_catalog: ContentCatalog) -> int:
	var definition := content_catalog.get_upgrade_definition_for_item(item)
	return definition.quality if definition != null else int(item.item_tier)


func _contains_upgrade_stat(
	offers: Array[ItemUpgrade],
	candidate: ItemUpgrade,
	content_catalog: ContentCatalog
) -> bool:
	var candidate_definition := content_catalog.get_upgrade_definition_for_item(candidate)
	if candidate_definition == null:
		return candidate in offers
	for offer: ItemUpgrade in offers:
		var definition := content_catalog.get_upgrade_definition_for_item(offer)
		if definition != null and definition.stat_id == candidate_definition.stat_id:
			return true
	return false


func select_reward(
	pool: Array[ItemBase],
	current_wave: int,
	run_state: RunState = null
) -> ItemBase:
	var maximum_tier := Global.UpgradeTier.COMMON
	if current_wave >= 7:
		maximum_tier = Global.UpgradeTier.LEGENDARY
	elif current_wave >= 4:
		maximum_tier = Global.UpgradeTier.EPIC
	elif current_wave >= 2:
		maximum_tier = Global.UpgradeTier.RARE
	var active_run: RunState = run_state if run_state != null else Global.current_run
	var minimum_tier: int = _next_reward_floor(active_run)
	maximum_tier = maxi(maximum_tier, minimum_tier)
	var available: Array[ItemBase] = []
	for item: ItemBase in pool:
		if (
			item != null
			and (not item is ItemWeapon or _weapon_allowed_for_run(
				active_run, item as ItemWeapon, Content.catalog
			))
			and int(item.item_tier) >= minimum_tier
			and int(item.item_tier) <= maximum_tier
		):
			available.append(item)
	if available.is_empty() and minimum_tier > Global.UpgradeTier.COMMON:
		for item: ItemBase in pool:
			if (
				item != null
				and (not item is ItemWeapon or _weapon_allowed_for_run(
					active_run, item as ItemWeapon, Content.catalog
				))
				and int(item.item_tier) <= maximum_tier
			):
				available.append(item)
	if available.is_empty():
		return null
	return available[rng.randi_range(0, available.size() - 1)]


func _queue_reward_floor(run_state: RunState, floor_tier: int) -> void:
	if run_state.queued_rewards <= 0:
		run_state.queued_reward_floors.clear()
	run_state.queued_rewards += 1
	run_state.queued_reward_floors.append(clampi(
		floor_tier, Global.UpgradeTier.COMMON, Global.UpgradeTier.LEGENDARY
	))


func _next_reward_floor(run_state: RunState) -> int:
	if (
		run_state == null
		or run_state.queued_rewards <= 0
		or run_state.queued_reward_floors.is_empty()
	):
		return Global.UpgradeTier.COMMON
	return int(run_state.queued_reward_floors.max())


func _consume_reward(run_state: RunState) -> void:
	run_state.queued_rewards = maxi(0, run_state.queued_rewards - 1)
	if run_state.queued_rewards <= 0:
		run_state.queued_reward_floors.clear()
		return
	if run_state.queued_reward_floors.is_empty():
		return
	var next_floor: int = _next_reward_floor(run_state)
	run_state.queued_reward_floors.erase(next_floor)


func _weapon_allowed_for_run(
	run_state: RunState,
	item: ItemWeapon,
	content_catalog: ContentCatalog
) -> bool:
	if run_state == null or item == null:
		return true
	if run_state.allowed_weapon_tags.is_empty() and run_state.forbidden_weapon_tags.is_empty():
		return true
	if content_catalog == null:
		return false
	return run_state.allows_weapon_tags(content_catalog.get_tags_for_item(item))
