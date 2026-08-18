class_name InventoryService
extends RefCounted


enum {
	OK,
	INVALID_REQUEST,
	INSUFFICIENT_MATERIALS,
	NO_WEAPON_SLOT,
	MAX_PASSIVE_STACK,
	INVALID_WEAPON_SLOT,
	WEAPONS_NOT_COMBINABLE,
	MAX_WEAPON_TIER,
}


static func try_purchase_weapon(
	run_state: RunState,
	weapon_id: StringName,
	tier: int,
	price: int
) -> int:
	if run_state == null or weapon_id.is_empty() or tier < 1 or tier > InventoryState.MAX_WEAPON_TIER or price < 0:
		return INVALID_REQUEST
	if run_state.materials < price:
		return INSUFFICIENT_MATERIALS
	if not run_state.inventory.has_weapon_slot():
		return NO_WEAPON_SLOT
	if run_state.inventory.add_weapon(weapon_id, tier, price) < 0:
		return NO_WEAPON_SLOT
	run_state.materials -= price
	return OK


static func try_purchase_passive(
	run_state: RunState,
	item_id: StringName,
	price: int,
	max_stack: int
) -> int:
	if run_state == null or item_id.is_empty() or price < 0 or max_stack < 1:
		return INVALID_REQUEST
	if run_state.materials < price:
		return INSUFFICIENT_MATERIALS
	if run_state.inventory.passive_count(item_id) >= max_stack:
		return MAX_PASSIVE_STACK
	if not run_state.inventory.add_passive(item_id):
		return INVALID_REQUEST
	run_state.materials -= price
	return OK


static func try_combine_weapons(run_state: RunState, first_slot: int, second_slot: int) -> int:
	if run_state == null or first_slot == second_slot:
		return INVALID_WEAPON_SLOT
	var first := run_state.inventory.weapon_at(first_slot)
	var second := run_state.inventory.weapon_at(second_slot)
	if first.is_empty() or second.is_empty():
		return INVALID_WEAPON_SLOT
	if first.get("weapon_id") != second.get("weapon_id") or first.get("tier") != second.get("tier"):
		return WEAPONS_NOT_COMBINABLE
	var tier := int(first.get("tier", 0))
	if tier >= InventoryState.MAX_WEAPON_TIER:
		return MAX_WEAPON_TIER
	var weapon_id := StringName(str(first.get("weapon_id", "")))
	var paid_price := int(first.get("paid_price", 0)) + int(second.get("paid_price", 0))
	run_state.inventory.remove_weapon(maxi(first_slot, second_slot))
	run_state.inventory.remove_weapon(mini(first_slot, second_slot))
	run_state.inventory.add_weapon(weapon_id, tier + 1, paid_price)
	return OK


static func try_sell_weapon(run_state: RunState, slot: int) -> int:
	if run_state == null:
		return INVALID_WEAPON_SLOT
	var weapon := run_state.inventory.weapon_at(slot)
	if weapon.is_empty():
		return INVALID_WEAPON_SLOT
	var refund := floori(
		int(weapon.get("paid_price", 0))
		* 0.75
		* run_state.recycle_value_multiplier
	)
	run_state.inventory.remove_weapon(slot)
	run_state.materials += refund
	return OK
