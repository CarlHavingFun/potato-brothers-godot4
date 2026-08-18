class_name ProductSettings
extends RefCounted


const DEFAULT_RESOLUTION := Vector2i(1920, 1080)
const MIN_RESOLUTION := Vector2i(640, 360)
const MAX_RESOLUTION := Vector2i(16384, 8640)
const VALID_FPS_CAPS: Array[int] = [0, 60, 120, 144, 240]
const SUPPORTED_LOCALES: Array[String] = ["zh_CN", "en"]

var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 0.8
var mute_on_focus_lost: bool = false

var display_mode: int = DisplayMode.BORDERLESS_FULLSCREEN
var resolution: Vector2i = DEFAULT_RESOLUTION
var vsync_enabled: bool = true
var fps_cap: int = 0

var aim_mode: int = AimMode.AUTO_TARGET
var pause_on_focus_lost: bool = true
var show_damage_numbers: bool = true
var show_player_health_bar: bool = true
var show_boss_health_bar: bool = true

var enemy_health_scale: float = 1.0
var enemy_damage_scale: float = 1.0
var enemy_speed_scale: float = 1.0
var ui_scale: float = 1.0
var screen_shake_intensity: float = 1.0
var gamepad_rumble_intensity: float = 1.0
var reduce_flashes: bool = false
var high_contrast_projectiles: bool = false

var locale: String = "zh_CN"
var input_bindings: Dictionary = {}
var gamepad_deadzone: float = 0.25


func sanitize() -> ProductSettings:
	master_volume = clampf(master_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	display_mode = display_mode if DisplayMode.is_valid(display_mode) \
		else DisplayMode.BORDERLESS_FULLSCREEN
	resolution = Vector2i(
		clampi(resolution.x, MIN_RESOLUTION.x, MAX_RESOLUTION.x),
		clampi(resolution.y, MIN_RESOLUTION.y, MAX_RESOLUTION.y),
	)
	fps_cap = _nearest_fps_cap(fps_cap)
	aim_mode = aim_mode if AimMode.is_valid(aim_mode) else AimMode.AUTO_TARGET
	enemy_health_scale = clampf(enemy_health_scale, 0.25, 2.0)
	enemy_damage_scale = clampf(enemy_damage_scale, 0.25, 2.0)
	enemy_speed_scale = clampf(enemy_speed_scale, 0.25, 2.0)
	ui_scale = clampf(ui_scale, 0.75, 1.5)
	screen_shake_intensity = clampf(screen_shake_intensity, 0.0, 1.0)
	gamepad_rumble_intensity = clampf(gamepad_rumble_intensity, 0.0, 1.0)
	gamepad_deadzone = clampf(gamepad_deadzone, 0.0, 1.0)
	locale = locale if locale in SUPPORTED_LOCALES else "zh_CN"
	input_bindings = input_bindings.duplicate(true)
	return self


func reset_to_defaults() -> ProductSettings:
	var defaults := ProductSettings.new()
	_copy_from(defaults)
	return self


func copy() -> ProductSettings:
	return ProductSettings.from_dict(to_dict())


func duplicate_settings() -> ProductSettings:
	return copy()


func is_equal_to(other: ProductSettings) -> bool:
	return other != null and to_dict() == other.to_dict()


func is_dirty_from(baseline: ProductSettings) -> bool:
	return not is_equal_to(baseline)


func to_dict() -> Dictionary:
	sanitize()
	return {
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"mute_on_focus_lost": mute_on_focus_lost,
		"display_mode": display_mode,
		"resolution": {
			"width": resolution.x,
			"height": resolution.y,
		},
		"vsync_enabled": vsync_enabled,
		"fps_cap": fps_cap,
		"aim_mode": aim_mode,
		"pause_on_focus_lost": pause_on_focus_lost,
		"show_damage_numbers": show_damage_numbers,
		"show_player_health_bar": show_player_health_bar,
		"show_boss_health_bar": show_boss_health_bar,
		"enemy_health_scale": enemy_health_scale,
		"enemy_damage_scale": enemy_damage_scale,
		"enemy_speed_scale": enemy_speed_scale,
		"ui_scale": ui_scale,
		"screen_shake_intensity": screen_shake_intensity,
		"gamepad_rumble_intensity": gamepad_rumble_intensity,
		"reduce_flashes": reduce_flashes,
		"high_contrast_projectiles": high_contrast_projectiles,
		"locale": locale,
		"input_bindings": input_bindings.duplicate(true),
		"gamepad_deadzone": gamepad_deadzone,
	}


static func from_dict(data: Dictionary) -> ProductSettings:
	var result := ProductSettings.new()
	result.master_volume = _read_float(data, "master_volume", result.master_volume)
	result.music_volume = _read_float(data, "music_volume", result.music_volume)
	result.sfx_volume = _read_float(data, "sfx_volume", result.sfx_volume)
	result.mute_on_focus_lost = _read_bool(
		data, "mute_on_focus_lost", result.mute_on_focus_lost
	)
	if data.has("display_mode"):
		result.display_mode = _read_int(data, "display_mode", result.display_mode)
	elif data.has("fullscreen"):
		result.display_mode = DisplayMode.BORDERLESS_FULLSCREEN \
			if _read_bool(data, "fullscreen", false) else DisplayMode.WINDOWED
	result.resolution = _parse_resolution(data.get("resolution", result.resolution))
	result.vsync_enabled = _read_bool(data, "vsync_enabled", result.vsync_enabled)
	result.fps_cap = _read_int(data, "fps_cap", result.fps_cap)
	result.aim_mode = _read_int(data, "aim_mode", result.aim_mode)
	result.pause_on_focus_lost = _read_bool(
		data, "pause_on_focus_lost", result.pause_on_focus_lost
	)
	result.show_damage_numbers = _read_bool(
		data, "show_damage_numbers", result.show_damage_numbers
	)
	result.show_player_health_bar = _read_bool(
		data, "show_player_health_bar", result.show_player_health_bar
	)
	result.show_boss_health_bar = _read_bool(
		data, "show_boss_health_bar", result.show_boss_health_bar
	)
	result.enemy_health_scale = _read_float(
		data, "enemy_health_scale", result.enemy_health_scale
	)
	result.enemy_damage_scale = _read_float(
		data, "enemy_damage_scale", result.enemy_damage_scale
	)
	result.enemy_speed_scale = _read_float(
		data, "enemy_speed_scale", result.enemy_speed_scale
	)
	result.ui_scale = _read_float(data, "ui_scale", result.ui_scale)
	result.screen_shake_intensity = _read_float(
		data, "screen_shake_intensity", result.screen_shake_intensity
	)
	result.gamepad_rumble_intensity = _read_float(
		data, "gamepad_rumble_intensity", result.gamepad_rumble_intensity
	)
	result.reduce_flashes = _read_bool(data, "reduce_flashes", result.reduce_flashes)
	result.high_contrast_projectiles = _read_bool(
		data, "high_contrast_projectiles", result.high_contrast_projectiles
	)
	result.locale = _read_string(data, "locale", result.locale)
	var raw_bindings: Variant = data.get("input_bindings", {})
	result.input_bindings = raw_bindings.duplicate(true) if raw_bindings is Dictionary else {}
	result.gamepad_deadzone = _read_float(data, "gamepad_deadzone", result.gamepad_deadzone)
	return result.sanitize()


func _copy_from(other: ProductSettings) -> void:
	master_volume = other.master_volume
	music_volume = other.music_volume
	sfx_volume = other.sfx_volume
	mute_on_focus_lost = other.mute_on_focus_lost
	display_mode = other.display_mode
	resolution = other.resolution
	vsync_enabled = other.vsync_enabled
	fps_cap = other.fps_cap
	aim_mode = other.aim_mode
	pause_on_focus_lost = other.pause_on_focus_lost
	show_damage_numbers = other.show_damage_numbers
	show_player_health_bar = other.show_player_health_bar
	show_boss_health_bar = other.show_boss_health_bar
	enemy_health_scale = other.enemy_health_scale
	enemy_damage_scale = other.enemy_damage_scale
	enemy_speed_scale = other.enemy_speed_scale
	ui_scale = other.ui_scale
	screen_shake_intensity = other.screen_shake_intensity
	gamepad_rumble_intensity = other.gamepad_rumble_intensity
	reduce_flashes = other.reduce_flashes
	high_contrast_projectiles = other.high_contrast_projectiles
	locale = other.locale
	input_bindings = other.input_bindings.duplicate(true)
	gamepad_deadzone = other.gamepad_deadzone


static func _parse_resolution(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Dictionary:
		var width: Variant = _resolution_component(value.get("width", null))
		var height: Variant = _resolution_component(value.get("height", null))
		if width == null or height == null:
			return DEFAULT_RESOLUTION
		return Vector2i(
			int(width),
			int(height),
		)
	if value is Array and value.size() >= 2:
		var width: Variant = _resolution_component(value[0])
		var height: Variant = _resolution_component(value[1])
		return Vector2i(int(width), int(height)) \
			if width != null and height != null else DEFAULT_RESOLUTION
	if value is String:
		var parts := (value as String).to_lower().split("x", false, 1)
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(int(parts[0]), int(parts[1]))
	return DEFAULT_RESOLUTION


static func _resolution_component(value: Variant) -> Variant:
	if value is int or value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return int(value)
	return null


static func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	return float(value) if value is int or value is float else fallback


static func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key, fallback)
	return int(value) if value is int or value is float else fallback


static func _read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key, fallback)
	return value as bool if value is bool else fallback


static func _read_string(data: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = data.get(key, fallback)
	return value as String if value is String else fallback


static func _nearest_fps_cap(value: int) -> int:
	var nearest := VALID_FPS_CAPS[0]
	var nearest_distance := absi(value - nearest)
	for candidate: int in VALID_FPS_CAPS:
		var distance := absi(value - candidate)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest
