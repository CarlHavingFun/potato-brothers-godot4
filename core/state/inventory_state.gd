class_name InventoryState
extends RefCounted


const MAX_WEAPON_SLOTS := 6
const MAX_WEAPON_TIER := 4

var _weapons: Array[Dictionary] = []
var _passives: Dictionary = {}


func weapon_count() -> int:
	return _weapons.size()


func has_weapon_slot() -> bool:
	return weapon_count() < MAX_WEAPON_SLOTS


func add_weapon(weapon_id: StringName, tier: int, paid_price: int = 0) -> int:
	if weapon_id.is_empty() or tier < 1 or tier > MAX_WEAPON_TIER or not has_weapon_slot():
		return -1
	_weapons.append({
		"weapon_id": String(weapon_id),
		"tier": tier,
		"paid_price": maxi(0, paid_price),
	})
	return _weapons.size() - 1


func weapon_at(index: int) -> Dictionary:
	if index < 0 or index >= _weapons.size():
		return {}
	return _weapons[index].duplicate(true)


func remove_weapon(index: int) -> Dictionary:
	if index < 0 or index >= _weapons.size():
		return {}
	var removed: Dictionary = _weapons[index]
	_weapons.remove_at(index)
	return removed.duplicate(true)


func passive_count(item_id: StringName) -> int:
	return int(_passives.get(String(item_id), 0))


func add_passive(item_id: StringName, amount: int = 1) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	var key := String(item_id)
	_passives[key] = passive_count(item_id) + amount
	return true


func to_dict() -> Dictionary:
	var serialized_weapons: Array[Dictionary] = []
	for weapon: Dictionary in _weapons:
		serialized_weapons.append(weapon.duplicate(true))
	return {
		"weapons": serialized_weapons,
		"passives": _passives.duplicate(true),
	}


static func from_dict(data: Dictionary) -> InventoryState:
	var result := InventoryState.new()
	var raw_weapons: Variant = data.get("weapons", [])
	if raw_weapons is Array:
		for raw_weapon: Variant in raw_weapons:
			if raw_weapon is Dictionary:
				result.add_weapon(
					StringName(str(raw_weapon.get("weapon_id", ""))),
					int(raw_weapon.get("tier", 0)),
					int(raw_weapon.get("paid_price", 0))
				)
	var raw_passives: Variant = data.get("passives", {})
	if raw_passives is Dictionary:
		for raw_key: Variant in raw_passives:
			result.add_passive(StringName(str(raw_key)), int(raw_passives[raw_key]))
	return result
