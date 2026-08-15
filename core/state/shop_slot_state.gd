class_name ShopSlotState
extends RefCounted


var offer_id: StringName = &""
var tier: int = 1
var item_type: int = -1
var locked := false
var purchased := false


func is_empty() -> bool:
	return offer_id.is_empty() or purchased


func needs_offer() -> bool:
	return offer_id.is_empty() and not purchased


func set_offer(content_id: StringName, offer_tier: int, offer_type: int) -> void:
	offer_id = content_id
	tier = maxi(1, offer_tier)
	item_type = offer_type
	purchased = false


func mark_purchased() -> void:
	purchased = true
	locked = false


func clear_offer(preserve_lock := true) -> void:
	offer_id = &""
	tier = 1
	item_type = -1
	purchased = false
	if not preserve_lock:
		locked = false


func to_dict() -> Dictionary:
	return {
		"offer_id": String(offer_id),
		"tier": tier,
		"item_type": item_type,
		"locked": locked,
		"purchased": purchased,
	}


static func from_dict(data: Dictionary) -> ShopSlotState:
	var result := ShopSlotState.new()
	result.offer_id = StringName(str(data.get("offer_id", data.get("id", ""))))
	result.tier = maxi(1, int(data.get("tier", 1)))
	result.item_type = int(data.get("item_type", data.get("type", -1)))
	result.locked = bool(data.get("locked", false))
	result.purchased = bool(data.get("purchased", false))
	return result
