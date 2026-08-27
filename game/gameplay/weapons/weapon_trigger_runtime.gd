class_name GogoWeaponTriggerRuntime
extends RefCounted


const SKYLINE_GRENADE_ID: StringName = &"gogobro.preview:item/skyline_grenade"
const SKYLINE_ATTACK_INTERVAL := 7

var _ranged_attack_counts: Dictionary = {}


func note_ranged_attack(
	weapon_instance_id: int,
	item_ids: Array[StringName]
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if weapon_instance_id <= 0 or not item_ids.has(SKYLINE_GRENADE_ID):
		return events
	var next_count := int(_ranged_attack_counts.get(weapon_instance_id, 0)) + 1
	if next_count < SKYLINE_ATTACK_INTERVAL:
		_ranged_attack_counts[weapon_instance_id] = next_count
		return events
	_ranged_attack_counts[weapon_instance_id] = 0
	events.append({
		"impact_kind": &"explosion",
		"damage_scale": 1.0,
		"source_item_id": SKYLINE_GRENADE_ID,
	})
	return events


func reset() -> void:
	_ranged_attack_counts.clear()
