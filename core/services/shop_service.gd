class_name ShopService
extends RefCounted


const STREAM_OFFSET := 0x53484F50

var rng := RandomNumberGenerator.new()


func _init(run_seed: int = 0) -> void:
	rng.seed = run_seed ^ STREAM_OFFSET


func calculate_tier_probabilities(current_wave: int, luck: float, config: Dictionary) -> Array[float]:
	var luck_factor := maxf(0.0, 1.0 + luck / 100.0)
	var rare := _tier_chance(current_wave, config.get("rare", {}), luck_factor)
	var epic := _tier_chance(current_wave, config.get("epic", {}), luck_factor)
	var legendary := _tier_chance(
		current_wave, config.get("legendary", {}), luck_factor
	)
	# The reference curves are cumulative: the Tier-2 threshold includes every
	# Tier-3/4 result, and the Tier-3 threshold includes Tier-4 results.
	epic = minf(epic, rare)
	legendary = minf(legendary, epic)
	return [
		maxf(0.0, 1.0 - rare),
		maxf(0.0, rare - epic),
		maxf(0.0, epic - legendary),
		maxf(0.0, legendary),
	]


func select_offers(
	item_pool: Array,
	current_wave: int,
	luck: float,
	config: Dictionary,
	requested_count: int = 4,
	content_catalog: ContentCatalog = null,
	owned_tags: Array[StringName] = [],
	run_state: RunState = null
) -> Array:
	var result: Array = []
	var probabilities: Array[float] = calculate_tier_probabilities(current_wave, luck, config)
	var available_pool: Array = item_pool.filter(
		func(item: Variant):
			return (
				item is ItemBase
				and (int((item as ItemBase).item_tier) == Global.UpgradeTier.COMMON
					or probabilities[int((item as ItemBase).item_tier)] > 0.0)
				and (not item is ItemWeapon or _weapon_allowed_for_run(
					run_state, item as ItemWeapon, content_catalog
				))
			)
	)
	if requested_count <= 0 or available_pool.is_empty():
		return result
	var target_count: int = mini(requested_count, available_pool.size())
	var weapon_quota: int = mini(_minimum_weapon_offers(current_wave), target_count)
	while result.size() < weapon_quota:
		var weapon: Variant = _draw_offer(
			available_pool, probabilities, result, content_catalog, owned_tags, true
		)
		if weapon == null:
			break
		result.append(weapon)
	var attempts: int = 0
	var max_attempts: int = maxi(16, available_pool.size() * 16)
	while result.size() < target_count and attempts < max_attempts:
		attempts += 1
		var candidate: Variant = _draw_offer(
			available_pool, probabilities, result, content_catalog, owned_tags, false
		)
		if candidate == null:
			continue
		result.append(candidate)
	if result.size() < target_count:
		var remaining: Array = available_pool.filter(
			func(item: Variant): return item is ItemBase and not _contains_offer_family(
				result, item as ItemBase, content_catalog
			)
		)
		while result.size() < target_count and not remaining.is_empty():
			var selected: Variant = _select_weighted_candidate(
				remaining, content_catalog, owned_tags
			)
			result.append(selected)
			remaining = remaining.filter(
				func(item: Variant): return not _same_offer_family(
					item as ItemBase, selected as ItemBase, content_catalog
				)
			)
	# Small or third-party pools may expose fewer unique families than slots. In that
	# case keep the old object-level uniqueness fallback rather than returning holes.
	if result.size() < target_count:
		var remaining_items: Array = available_pool.filter(
			func(item: Variant): return not result.has(item)
		)
		while result.size() < target_count and not remaining_items.is_empty():
			var index := rng.randi_range(0, remaining_items.size() - 1)
			result.append(remaining_items.pop_at(index))
	return result


func try_purchase_detailed(
	run_state: RunState,
	item: ItemBase,
	content_catalog: ContentCatalog
) -> Dictionary:
	if run_state == null or item == null or content_catalog == null:
		return _purchase_result(InventoryService.INVALID_REQUEST)
	if item is ItemWeapon:
		if not _weapon_allowed_for_run(run_state, item as ItemWeapon, content_catalog):
			return _purchase_result(InventoryService.INVALID_REQUEST)
		return InventoryService.try_purchase_weapon_detailed(
			run_state,
			content_catalog.get_item_stable_id(item),
			int(item.item_tier) + 1,
			purchase_price(run_state, item)
		)
	if item is ItemPassive:
		var definition := content_catalog.get_passive_definition_for_item(item)
		return _purchase_result(InventoryService.try_purchase_passive(
			run_state,
			content_catalog.get_item_stable_id(item),
			purchase_price(run_state, item),
			definition.max_stack if definition != null else item.max_stack
		))
	return _purchase_result(InventoryService.INVALID_REQUEST)


func try_purchase(run_state: RunState, item: ItemBase, content_catalog: ContentCatalog) -> int:
	return int(try_purchase_detailed(run_state, item, content_catalog).get(
		"code", InventoryService.INVALID_REQUEST
	))


func _purchase_result(code: int) -> Dictionary:
	return {
		"code": code,
		"mode": InventoryService.PURCHASE_MODE_NONE,
		"target_slot": -1,
		"resulting_tier": 0,
	}


func purchase_price(run_state: RunState, item: ItemBase) -> int:
	if item == null:
		return 0
	var difficulty := Content.catalog.get_difficulty(run_state.difficulty) if run_state != null else null
	var base_price := (
		difficulty.scale_shop_price(item.item_cost) if difficulty != null else item.item_cost
	)
	return maxi(0, ceili(base_price * (
		run_state.shop_price_multiplier if run_state != null else 1.0
	)))


func refresh_price(current_wave: int, refresh_count: int) -> int:
	return maxi(1, current_wave) + 2 + maxi(0, refresh_count) * 2


func refresh_price_for_slots(current_wave: int, refresh_count: int, unlocked_slots: int) -> int:
	if unlocked_slots <= 0:
		return 0
	return ceili(refresh_price(current_wave, refresh_count) * minf(4.0, unlocked_slots) / 4.0)


func try_refresh(run_state: RunState, current_wave: int) -> int:
	if run_state == null:
		return InventoryService.INVALID_REQUEST
	_ensure_slots(run_state)
	var unlocked_count := 0
	for slot: ShopSlotState in run_state.shop_slots:
		if not slot.locked:
			unlocked_count += 1
	if unlocked_count == 0:
		return InventoryService.INVALID_REQUEST
	var price := refresh_price_for_run(run_state, current_wave, unlocked_count)
	if run_state.materials < price:
		return InventoryService.INSUFFICIENT_MATERIALS
	run_state.materials -= price
	run_state.shop_refresh_count += 1
	for slot: ShopSlotState in run_state.shop_slots:
		if not slot.locked:
			slot.clear_offer()
	_sync_legacy_fields(run_state)
	return InventoryService.OK


func refresh_price_for_run(run_state: RunState, current_wave: int, unlocked_slots: int = 4) -> int:
	if run_state == null:
		return 0
	if free_refresh_count(run_state) > 0:
		return 0
	var base_price := refresh_price_for_slots(current_wave, run_state.shop_refresh_count, unlocked_slots)
	var difficulty := Content.catalog.get_difficulty(run_state.difficulty)
	var result := difficulty.scale_shop_price(base_price) if difficulty != null else base_price
	result = ceili(result * run_state.shop_price_multiplier)
	if run_state.run_mode == RunMode.ENDLESS and current_wave > 20:
		result = ceili(result * EndlessScalingDef.new().shop_price_multiplier(current_wave))
	return result


func free_refresh_count(run_state: RunState) -> int:
	if run_state == null:
		return 0
	_ensure_slots(run_state)
	# The entitlement is represented by the serialized slot state itself. Clearing
	# the slots consumes it, so it survives checkpoints without another save field.
	for slot: ShopSlotState in run_state.shop_slots:
		if not slot.purchased:
			return 0
	return 1


func set_locked(run_state: RunState, locked: bool) -> bool:
	if run_state == null:
		return false
	_ensure_slots(run_state)
	for slot: ShopSlotState in run_state.shop_slots:
		slot.locked = locked
	_sync_legacy_fields(run_state)
	return true


func set_slot_locked(run_state: RunState, slot_index: int, locked: bool) -> bool:
	if run_state == null:
		return false
	_ensure_slots(run_state)
	if slot_index < 0 or slot_index >= run_state.shop_slots.size():
		return false
	run_state.shop_slots[slot_index].locked = locked
	_sync_legacy_fields(run_state)
	return true


func store_offers(run_state: RunState, offers: Array, content_catalog: ContentCatalog) -> bool:
	if run_state == null or content_catalog == null:
		return false
	_ensure_slots(run_state)
	var offer_index := 0
	for slot: ShopSlotState in run_state.shop_slots:
		if not slot.needs_offer():
			continue
		if offer_index >= offers.size():
			slot.clear_offer()
			continue
		var item: Variant = offers[offer_index]
		offer_index += 1
		if not item is ItemBase:
			slot.clear_offer()
			continue
		var typed_item := item as ItemBase
		slot.set_offer(
			content_catalog.get_item_stable_id(typed_item),
			int(typed_item.item_tier) + 1,
			int(typed_item.item_type)
		)
	_sync_legacy_fields(run_state)
	return true


func _sync_legacy_fields(run_state: RunState) -> void:
	run_state.shop_offer_ids.clear()
	var occupied := 0
	var locked := 0
	for slot: ShopSlotState in run_state.shop_slots:
		if slot.is_empty():
			continue
		occupied += 1
		if slot.locked:
			locked += 1
		run_state.shop_offer_ids.append({
			"id": String(slot.offer_id),
			"tier": slot.tier,
			"type": slot.item_type,
		})
	run_state.shop_locked = occupied > 0 and locked == occupied


func resolve_offers(run_state: RunState, content_catalog: ContentCatalog) -> Array[ItemBase]:
	var result: Array[ItemBase] = []
	if run_state == null or content_catalog == null:
		return result
	_ensure_slots(run_state)
	for slot: ShopSlotState in run_state.shop_slots:
		if slot.is_empty():
			continue
		var item: ItemBase
		var content_id := slot.offer_id
		if slot.item_type == ItemBase.ItemType.WEAPON:
			item = content_catalog.get_weapon_tier(content_id, slot.tier)
		elif slot.item_type == ItemBase.ItemType.PASSIVE:
			var passive := content_catalog.get_passive(content_id)
			item = passive.item if passive != null else null
		if item != null:
			result.append(item)
	return result


func resolve_slot_offer(
	run_state: RunState,
	slot_index: int,
	content_catalog: ContentCatalog
) -> ItemBase:
	if run_state == null or content_catalog == null:
		return null
	_ensure_slots(run_state)
	if slot_index < 0 or slot_index >= run_state.shop_slots.size():
		return null
	var slot: ShopSlotState = run_state.shop_slots[slot_index]
	if slot.is_empty():
		return null
	if slot.item_type == ItemBase.ItemType.WEAPON:
		return content_catalog.get_weapon_tier(slot.offer_id, slot.tier)
	if slot.item_type == ItemBase.ItemType.PASSIVE:
		var passive := content_catalog.get_passive(slot.offer_id)
		return passive.item if passive != null else null
	return null


func try_purchase_offer_detailed(
	run_state: RunState,
	slot_index: int,
	content_catalog: ContentCatalog
) -> Dictionary:
	var item := resolve_slot_offer(run_state, slot_index, content_catalog)
	if item == null:
		return _purchase_result(InventoryService.INVALID_REQUEST)
	var result := try_purchase_detailed(run_state, item, content_catalog)
	if int(result.get("code", InventoryService.INVALID_REQUEST)) != InventoryService.OK:
		return result
	run_state.shop_slots[slot_index].mark_purchased()
	_sync_legacy_fields(run_state)
	return result


func try_purchase_offer(
	run_state: RunState,
	slot_index: int,
	content_catalog: ContentCatalog
) -> int:
	return int(try_purchase_offer_detailed(run_state, slot_index, content_catalog).get(
		"code", InventoryService.INVALID_REQUEST
	))


func prepare_next_wave(run_state: RunState) -> void:
	if run_state == null:
		return
	_ensure_slots(run_state)
	run_state.shop_refresh_count = 0
	for slot: ShopSlotState in run_state.shop_slots:
		if not slot.locked:
			slot.clear_offer()
	_sync_legacy_fields(run_state)


func consume_offer(run_state: RunState, item: ItemBase, content_catalog: ContentCatalog) -> bool:
	if run_state == null or item == null or content_catalog == null:
		return false
	var stable_id := String(content_catalog.get_item_stable_id(item))
	var tier := int(item.item_tier) + 1
	_ensure_slots(run_state)
	for slot: ShopSlotState in run_state.shop_slots:
		if String(slot.offer_id) == stable_id and slot.tier == tier:
			slot.mark_purchased()
			_sync_legacy_fields(run_state)
			return true
	return false


func tag_affinity_weight(item_tags: Array[StringName], owned_tags: Array[StringName]) -> float:
	var matches := 0
	for tag: StringName in item_tags:
		if tag in owned_tags:
			matches += 1
	return minf(1.75, 1.0 + matches * 0.375)


func _minimum_weapon_offers(current_wave: int) -> int:
	if current_wave <= 2:
		return 2
	if current_wave <= 5:
		return 1
	return 0


func _draw_offer(
	item_pool: Array,
	probabilities: Array[float],
	excluded: Array,
	content_catalog: ContentCatalog,
	owned_tags: Array[StringName],
	weapons_only: bool
) -> Variant:
	for attempt in 8:
		var candidates := _items_at_or_below_tier(
			item_pool, _roll_tier(probabilities), excluded, content_catalog, weapons_only
		)
		if not candidates.is_empty():
			return _select_weighted_candidate(candidates, content_catalog, owned_tags)
	return null


func _contains_offer_family(
	offers: Array,
	candidate: ItemBase,
	content_catalog: ContentCatalog
) -> bool:
	for offer: ItemBase in offers:
		if _same_offer_family(offer, candidate, content_catalog):
			return true
	return false


func _same_offer_family(
	first: ItemBase,
	second: ItemBase,
	content_catalog: ContentCatalog
) -> bool:
	if first == null or second == null:
		return false
	var first_id := content_catalog.get_item_stable_id(first) if content_catalog != null else first.get_stable_id()
	var second_id := content_catalog.get_item_stable_id(second) if content_catalog != null else second.get_stable_id()
	return not first_id.is_empty() and first_id == second_id


func _select_weighted_candidate(
	candidates: Array,
	content_catalog: ContentCatalog,
	owned_tags: Array[StringName]
) -> Variant:
	if candidates.is_empty():
		return null
	if content_catalog == null or owned_tags.is_empty():
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var total_weight := 0.0
	var weights: Array[float] = []
	for candidate: ItemBase in candidates:
		var weight := tag_affinity_weight(content_catalog.get_tags_for_item(candidate), owned_tags)
		weights.append(weight)
		total_weight += weight
	var roll := rng.randf() * total_weight
	for index in candidates.size():
		roll -= weights[index]
		if roll <= 0.0:
			return candidates[index]
	return candidates.back()


func _ensure_slots(run_state: RunState) -> void:
	while run_state.shop_slots.size() < RunState.SHOP_SLOT_COUNT:
		run_state.shop_slots.append(ShopSlotState.new())


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


func _tier_chance(current_wave: int, tier_config: Dictionary, luck_factor: float) -> float:
	var start_wave := int(tier_config.get("start_wave", 999))
	if current_wave < start_wave:
		return 0.0
	var chance := (
		maxi(0, current_wave - start_wave + 1)
		* float(tier_config.get("base_multi", 0.0))
		* luck_factor
	)
	return minf(float(tier_config.get("max_chance", 1.0)), chance)


func _roll_tier(probabilities: Array[float]) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for tier in probabilities.size():
		cumulative += probabilities[tier]
		if roll <= cumulative:
			return tier
	return 0


func _items_at_or_below_tier(
	item_pool: Array,
	desired_tier: int,
	excluded: Array,
	content_catalog: ContentCatalog = null,
	weapons_only: bool = false
) -> Array:
	for tier in range(desired_tier, -1, -1):
		var candidates := item_pool.filter(
			func(item: Variant):
				return (
					item is ItemBase
					and (not weapons_only or item is ItemWeapon)
					and int(item.item_tier) == tier
					and not excluded.has(item)
					and not _contains_offer_family(excluded, item as ItemBase, content_catalog)
				)
		)
		if not candidates.is_empty():
			return candidates
	return []
