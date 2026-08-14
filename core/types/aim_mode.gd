class_name AimMode
extends RefCounted


enum {
	AUTO_TARGET,
	MANUAL_MOUSE,
}


static func is_valid(value: int) -> bool:
	return value == AUTO_TARGET or value == MANUAL_MOUSE
