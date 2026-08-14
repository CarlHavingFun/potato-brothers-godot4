class_name RunPhase
extends RefCounted


enum {
	SELECTION,
	COMBAT,
	UPGRADE,
	CHEST,
	SHOP,
	VICTORY,
	DEATH,
}

const _TRANSITIONS: Dictionary = {
	SELECTION: [COMBAT],
	COMBAT: [UPGRADE, VICTORY, DEATH],
	UPGRADE: [CHEST, SHOP],
	CHEST: [SHOP],
	SHOP: [COMBAT],
	VICTORY: [],
	DEATH: [],
}


static func is_valid(value: int) -> bool:
	return value >= SELECTION and value <= DEATH


static func can_transition(current: int, next: int) -> bool:
	if not is_valid(current) or not is_valid(next):
		return false
	var allowed: Array = _TRANSITIONS.get(current, [])
	return allowed.has(next)
