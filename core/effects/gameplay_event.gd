class_name GameplayEvent
extends RefCounted


enum Type {
	RUN_STARTED,
	WAVE_STARTED,
	WAVE_ENDED,
	ATTACKED,
	HIT,
	CRITICAL_HIT,
	KILLED,
	DAMAGED,
	DODGED,
	PICKED_UP,
	PURCHASED,
	SHOP_REFRESHED,
	DASHED,
}


static func is_valid(value: int) -> bool:
	return value >= Type.RUN_STARTED and value <= Type.DASHED
