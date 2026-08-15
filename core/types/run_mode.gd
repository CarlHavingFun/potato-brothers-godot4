class_name RunMode
extends RefCounted


enum {
	STANDARD,
	ENDLESS,
}


static func is_valid(value: int) -> bool:
	return value in [STANDARD, ENDLESS]
