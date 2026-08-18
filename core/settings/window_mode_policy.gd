class_name WindowModePolicy
extends RefCounted


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
