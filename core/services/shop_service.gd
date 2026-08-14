class_name ShopService
extends RefCounted


const STREAM_OFFSET := 0x53484F50

var rng := RandomNumberGenerator.new()


func _init(run_seed: int = 0) -> void:
	rng.seed = run_seed ^ STREAM_OFFSET


func calculate_tier_probabilities(current_wave: int, luck: float, config: Dictionary) -> Array[float]:
	var rare := _tier_chance(current_wave, config.get("rare", {}), 1)
	var epic := _tier_chance(current_wave, config.get("epic", {}), 3)
	var legendary := _tier_chance(current_wave, config.get("legendary", {}), 6)
	var luck_factor := maxf(0.0, 1.0 + luck / 100.0)
	rare *= luck_factor
	epic *= luck_factor
	legendary *= luck_factor
	var non_common := rare + epic + legendary
	if non_common > 1.0:
		var normalization := 1.0 / non_common
		rare *= normalization
		epic *= normalization
		legendary *= normalization
		non_common = 1.0
	return [maxf(0.0, 1.0 - non_common), rare, epic, legendary]


func select_offers(
	item_pool: Array,
	current_wave: int,
	luck: float,
	config: Dictionary,
	requested_count: int = 4
) -> Array:
	var result: Array = []
	if requested_count <= 0 or item_pool.is_empty():
		return result
	var target_count := mini(requested_count, item_pool.size())
	var probabilities := calculate_tier_probabilities(current_wave, luck, config)
	var attempts := 0
	var max_attempts := maxi(16, item_pool.size() * 16)
	while result.size() < target_count and attempts < max_attempts:
		attempts += 1
		var tier := _roll_tier(probabilities)
		var candidates := _items_at_or_below_tier(item_pool, tier, result)
		if candidates.is_empty():
			continue
		result.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	if result.size() < target_count:
		var remaining := item_pool.filter(func(item: Variant): return not result.has(item))
		while result.size() < target_count and not remaining.is_empty():
			var index := rng.randi_range(0, remaining.size() - 1)
			result.append(remaining.pop_at(index))
	return result


func try_purchase(run_state: RunState, item: ItemBase, content_catalog: ContentCatalog) -> int:
	if run_state == null or item == null or content_catalog == null:
		return InventoryService.INVALID_REQUEST
	if item is ItemWeapon:
		return InventoryService.try_purchase_weapon(
			run_state,
			content_catalog.get_item_stable_id(item),
			int(item.item_tier) + 1,
			item.item_cost
		)
	if item is ItemPassive:
		var definition := content_catalog.get_passive_definition_for_item(item)
		return InventoryService.try_purchase_passive(
			run_state,
			content_catalog.get_item_stable_id(item),
			item.item_cost,
			definition.max_stack if definition != null else item.max_stack
		)
	return InventoryService.INVALID_REQUEST


func refresh_price(current_wave: int, refresh_count: int) -> int:
	return maxi(1, current_wave) + 2 + maxi(0, refresh_count) * 2


func try_refresh(run_state: RunState, current_wave: int) -> int:
	if run_state == null:
		return InventoryService.INVALID_REQUEST
	var price := refresh_price(current_wave, run_state.shop_refresh_count)
	if run_state.materials < price:
		return InventoryService.INSUFFICIENT_MATERIALS
	run_state.materials -= price
	run_state.shop_refresh_count += 1
	run_state.shop_locked = false
	run_state.shop_offer_ids.clear()
	return InventoryService.OK


func set_locked(run_state: RunState, locked: bool) -> bool:
	if run_state == null:
		return false
	run_state.shop_locked = locked
	return true


func store_offers(run_state: RunState, offers: Array, content_catalog: ContentCatalog) -> bool:
	if run_state == null or content_catalog == null:
		return false
	run_state.shop_offer_ids.clear()
	for item: Variant in offers:
		if not item is ItemBase:
			continue
		var typed_item := item as ItemBase
		run_state.shop_offer_ids.append({
			"id": String(content_catalog.get_item_stable_id(typed_item)),
			"tier": int(typed_item.item_tier) + 1,
			"type": int(typed_item.item_type),
		})
	return true


func resolve_offers(run_state: RunState, content_catalog: ContentCatalog) -> Array[ItemBase]:
	var result: Array[ItemBase] = []
	if run_state == null or content_catalog == null:
		return result
	for entry: Dictionary in run_state.shop_offer_ids:
		var item: ItemBase
		var content_id := StringName(str(entry.get("id", "")))
		if int(entry.get("type", -1)) == ItemBase.ItemType.WEAPON:
			item = content_catalog.get_weapon_tier(content_id, int(entry.get("tier", 1)))
		elif int(entry.get("type", -1)) == ItemBase.ItemType.PASSIVE:
			var passive := content_catalog.get_passive(content_id)
			item = passive.item if passive != null else null
		if item != null:
			result.append(item)
	return result


func consume_offer(run_state: RunState, item: ItemBase, content_catalog: ContentCatalog) -> bool:
	if run_state == null or item == null or content_catalog == null:
		return false
	var stable_id := String(content_catalog.get_item_stable_id(item))
	var tier := int(item.item_tier) + 1
	for index in run_state.shop_offer_ids.size():
		var entry := run_state.shop_offer_ids[index]
		if str(entry.get("id", "")) == stable_id and int(entry.get("tier", 0)) == tier:
			run_state.shop_offer_ids.remove_at(index)
			return true
	return false


func try_combine_item(
	run_state: RunState,
	weapon: ItemWeapon,
	content_catalog: ContentCatalog
) -> int:
	if run_state == null or weapon == null or content_catalog == null:
		return InventoryService.INVALID_REQUEST
	var slots := run_state.inventory.find_weapon_slots(
		content_catalog.get_item_stable_id(weapon), int(weapon.item_tier) + 1
	)
	if slots.size() < 2:
		return InventoryService.WEAPONS_NOT_COMBINABLE
	return InventoryService.try_combine_weapons(run_state, slots[0], slots[1])


func try_sell_item(
	run_state: RunState,
	weapon: ItemWeapon,
	content_catalog: ContentCatalog
) -> int:
	if run_state == null or weapon == null or content_catalog == null:
		return InventoryService.INVALID_REQUEST
	var slots := run_state.inventory.find_weapon_slots(
		content_catalog.get_item_stable_id(weapon), int(weapon.item_tier) + 1
	)
	if slots.is_empty():
		return InventoryService.INVALID_WEAPON_SLOT
	return InventoryService.try_sell_weapon(run_state, slots[0])


func roll_chance(chance: float) -> bool:
	return rng.randf() < clampf(chance, 0.0, 1.0)


func _tier_chance(current_wave: int, tier_config: Dictionary, wave_offset: int) -> float:
	var start_wave := int(tier_config.get("start_wave", 999))
	if current_wave < start_wave:
		return 0.0
	return minf(1.0, maxi(0, current_wave - wave_offset) * float(tier_config.get("base_multi", 0.0)))


func _roll_tier(probabilities: Array[float]) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for tier in probabilities.size():
		cumulative += probabilities[tier]
		if roll <= cumulative:
			return tier
	return 0


func _items_at_or_below_tier(item_pool: Array, desired_tier: int, excluded: Array) -> Array:
	for tier in range(desired_tier, -1, -1):
		var candidates := item_pool.filter(
			func(item: Variant):
				return item is ItemBase and int(item.item_tier) == tier and not excluded.has(item)
		)
		if not candidates.is_empty():
			return candidates
	return []
