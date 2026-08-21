class_name WindowModePolicy
extends RefCounted


const WINDOW_FRAME_MARGIN := Vector2i(32, 64)
const WINDOWED_PRESETS: Array[Vector2i] = [
	Vector2i(1024, 576),
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]


## Returns the native window contract for a persisted product display mode.
## Keeping this mapping pure makes the Windows decoration semantics testable in
## headless CI; Global is responsible only for applying the returned contract.
static func native_contract(display_mode: int) -> Dictionary:
	match display_mode:
		DisplayMode.WINDOWED:
			return {
				"mode": DisplayServer.WINDOW_MODE_WINDOWED,
				"borderless": false,
				"resize_disabled": false,
				"extend_to_title": false,
			}
		DisplayMode.EXCLUSIVE_FULLSCREEN:
			return {
				"mode": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
				"borderless": false,
				"resize_disabled": false,
				"extend_to_title": false,
			}
		_:
			return {
				"mode": DisplayServer.WINDOW_MODE_FULLSCREEN,
				"borderless": true,
				"resize_disabled": false,
				"extend_to_title": false,
			}


## A windowed client area must leave room for the Windows caption, resize frame,
## and taskbar. Otherwise a nominal 1920x1080 window on a 1080p monitor looks
## indistinguishable from borderless fullscreen even though its native flags are
## correct. Keep a requested size when it visibly fits; otherwise choose the
## largest standard 16:9 size whose whole decorated window remains on-screen.
static func resolved_windowed_size(
	requested: Vector2i,
	usable_size: Vector2i,
	minimum_size: Vector2i = Vector2i(640, 360)
) -> Vector2i:
	var maximum_client := Vector2i(
		maxi(minimum_size.x, usable_size.x - WINDOW_FRAME_MARGIN.x),
		maxi(minimum_size.y, usable_size.y - WINDOW_FRAME_MARGIN.y),
	)
	if requested.x <= maximum_client.x and requested.y <= maximum_client.y:
		return Vector2i(
			maxi(minimum_size.x, requested.x),
			maxi(minimum_size.y, requested.y),
		)
	var best := minimum_size
	for candidate: Vector2i in WINDOWED_PRESETS:
		if candidate.x <= maximum_client.x and candidate.y <= maximum_client.y:
			best = candidate
	return best
