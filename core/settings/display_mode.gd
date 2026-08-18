class_name DisplayMode
extends RefCounted


enum {
	WINDOWED = 0,
	BORDERLESS_FULLSCREEN = 1,
	EXCLUSIVE_FULLSCREEN = 2,
}


static func is_valid(value: int) -> bool:
	return value in [WINDOWED, BORDERLESS_FULLSCREEN, EXCLUSIVE_FULLSCREEN]
