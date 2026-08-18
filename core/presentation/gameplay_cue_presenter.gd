class_name GameplayCuePresenter
extends Node


signal cue_presented(cue_id: StringName, resolved: Dictionary)

var _last_feedback_usec: Dictionary = {}
var _active_hit_stops: Dictionary = {}
var _next_hit_stop_id := 0
var _restore_time_scale := 1.0


func _ready() -> void:
	if not GameplayCues.cue_emitted.is_connected(handle_cue):
		GameplayCues.cue_emitted.connect(handle_cue)


func handle_cue(cue_id: StringName, context: Dictionary) -> void:
	var resolved := Presentation.resolve_cue(cue_id)
	var profile := feedback_profile_for_cue(cue_id, resolved)
	resolved["feedback"] = profile.to_dict()
	var shake := scaled_shake_definition(
		_shake_definition(resolved, profile), screen_shake_multiplier()
	)
	var rumble := scaled_rumble_definition(
		_rumble_definition(resolved, profile), controller_vibration_multiplier()
	)
	resolved["screen_shake"] = shake
	resolved["rumble"] = rumble
	cue_presented.emit(cue_id, resolved.duplicate(true))
	if DisplayServer.get_name() == "headless":
		return
	if not can_present_feedback(cue_id, profile, Time.get_ticks_usec()):
		return
	_play_audio(str(resolved.get("audio", "")), profile)
	_spawn_particles(str(resolved.get("particle", "")), context)
	_apply_screen_shake(shake)
	_apply_rumble(rumble)
	if profile.hit_stop_seconds > 0.0:
		_request_hit_stop(profile.hit_stop_seconds, profile.hit_stop_scale, profile.priority)


func feedback_profile_for_cue(cue_id: StringName, resolved: Dictionary) -> CombatFeedbackProfile:
	return CombatFeedbackProfile.for_cue(cue_id, resolved.get("feedback", {}))


func can_present_feedback(
	cue_id: StringName,
	profile: CombatFeedbackProfile,
	now_usec: int
) -> bool:
	var previous := int(_last_feedback_usec.get(cue_id, -1))
	var minimum_usec := roundi(profile.minimum_interval_seconds * 1_000_000.0)
	if previous >= 0 and now_usec - previous < minimum_usec:
		return false
	_last_feedback_usec[cue_id] = now_usec
	return true


static func setting_from_sources(
	primary: Variant,
	fallback: Variant,
	setting_name: StringName,
	default_value: Variant,
	aliases: Array[StringName] = []
) -> Variant:
	var names: Array[StringName] = [setting_name]
	for alias: StringName in aliases:
		if alias not in names:
			names.append(alias)
	for source: Variant in [primary, fallback]:
		for candidate: StringName in names:
			var lookup := _setting_from_source(source, candidate)
			if bool(lookup.get("found", false)):
				return lookup.get("value", default_value)
	return default_value


static func runtime_setting(
	setting_name: StringName,
	default_value: Variant,
	aliases: Array[StringName] = []
) -> Variant:
	var product_settings: Variant = null
	if _object_has_property(Global, &"product_settings"):
		product_settings = Global.get("product_settings")
	var legacy_settings: Variant = (
		Global.get("meta_progress")
		if _object_has_property(Global, &"meta_progress")
		else null
	)
	return setting_from_sources(
		product_settings, legacy_settings, setting_name, default_value, aliases
	)


static func runtime_bool(setting_name: StringName, default_value: bool = false) -> bool:
	return bool(runtime_setting(setting_name, default_value))


static func screen_shake_multiplier() -> float:
	var aliases: Array[StringName] = [
		&"screen_shake_scale", &"screen_shake_strength", &"shake_intensity",
	]
	return clampf(float(runtime_setting(
		&"screen_shake_intensity", 1.0, aliases
	)), 0.0, 2.0)


static func controller_vibration_multiplier() -> float:
	var aliases: Array[StringName] = [
		&"controller_vibration_intensity",
		&"controller_vibration_scale", &"controller_vibration_strength",
		&"rumble_intensity", &"vibration_intensity",
	]
	return clampf(float(runtime_setting(
		&"gamepad_rumble_intensity", 1.0, aliases
	)), 0.0, 2.0)


static func scaled_shake_definition(definition: Dictionary, multiplier: float) -> Dictionary:
	var result := definition.duplicate(true)
	if result.has("strength"):
		result["strength"] = maxf(0.0, float(result.get("strength", 0.0)) * maxf(0.0, multiplier))
	return result


static func scaled_rumble_definition(definition: Dictionary, multiplier: float) -> Dictionary:
	var result := definition.duplicate(true)
	var safe_multiplier := maxf(0.0, multiplier)
	if result.has("weak"):
		result["weak"] = clampf(float(result.get("weak", 0.0)) * safe_multiplier, 0.0, 1.0)
	if result.has("strong"):
		result["strong"] = clampf(float(result.get("strong", 0.0)) * safe_multiplier, 0.0, 1.0)
	if safe_multiplier <= 0.0 and result.has("duration"):
		result["duration"] = 0.0
	return result


static func _setting_from_source(source: Variant, setting_name: StringName) -> Dictionary:
	if source == null:
		return {"found": false}
	if source is Dictionary:
		var values := source as Dictionary
		if values.has(setting_name):
			return {"found": true, "value": values[setting_name]}
		var string_name := String(setting_name)
		if values.has(string_name):
			return {"found": true, "value": values[string_name]}
		return {"found": false}
	if source is Object and _object_has_property(source as Object, setting_name):
		return {"found": true, "value": (source as Object).get(setting_name)}
	return {"found": false}


static func _object_has_property(source: Object, property_name: StringName) -> bool:
	if source == null:
		return false
	for property: Dictionary in source.get_property_list():
		if StringName(str(property.get("name", ""))) == property_name:
			return true
	return false


func _play_audio(path: String, profile: CombatFeedbackProfile) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.pitch_scale = randf_range(profile.audio_pitch_min, profile.audio_pitch_max)
	add_child(player)
	player.finished.connect(func() -> void: player.queue_free())
	player.play()


func _spawn_particles(path: String, context: Dictionary) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var instance := scene.instantiate()
	get_tree().current_scene.add_child(instance)
	if instance is Node2D:
		var world_position: Variant = context.get("world_position", Vector2.ZERO)
		(instance as Node2D).global_position = world_position if world_position is Vector2 else Vector2.ZERO


func _apply_screen_shake(definition: Dictionary) -> void:
	var strength := float(definition.get("strength", 0.0))
	if strength <= 0.0 or get_tree() == null:
		return
	for camera: Node in get_tree().get_nodes_in_group(&"presentation_camera"):
		if camera.has_method("add_trauma"):
			camera.call("add_trauma", strength / 20.0)


func _apply_rumble(definition: Dictionary) -> void:
	var duration := float(definition.get("duration", 0.0))
	if duration <= 0.0:
		return
	for device_id: int in Input.get_connected_joypads():
		Input.start_joy_vibration(
			device_id,
			clampf(float(definition.get("weak", 0.0)), 0.0, 1.0),
			clampf(float(definition.get("strong", 0.0)), 0.0, 1.0),
			duration
		)


func _shake_definition(resolved: Dictionary, profile: CombatFeedbackProfile) -> Dictionary:
	var definition := (resolved.get("screen_shake", {}) as Dictionary).duplicate(true)
	if not definition.has("strength") and profile.shake_strength > 0.0:
		definition["strength"] = profile.shake_strength
	return definition


func _rumble_definition(resolved: Dictionary, profile: CombatFeedbackProfile) -> Dictionary:
	var definition := (resolved.get("rumble", {}) as Dictionary).duplicate(true)
	if definition.is_empty() and profile.rumble_duration > 0.0:
		definition = {
			"weak": profile.rumble_weak,
			"strong": profile.rumble_strong,
			"duration": profile.rumble_duration,
		}
	return definition


func _request_hit_stop(duration: float, scale: float, priority: int) -> void:
	if get_tree() == null or duration <= 0.0:
		return
	if _active_hit_stops.is_empty():
		_restore_time_scale = Engine.time_scale
	_next_hit_stop_id += 1
	var request_id := _next_hit_stop_id
	_active_hit_stops[request_id] = {
		"scale": clampf(scale, 0.01, 1.0),
		"priority": priority,
	}
	_recompute_hit_stop_scale()
	await get_tree().create_timer(duration, true, false, true).timeout
	_active_hit_stops.erase(request_id)
	_recompute_hit_stop_scale()


func _recompute_hit_stop_scale() -> void:
	if _active_hit_stops.is_empty():
		Engine.time_scale = _restore_time_scale
		return
	var strongest_scale := 1.0
	var strongest_priority := -1
	for request: Dictionary in _active_hit_stops.values():
		var request_priority := int(request.get("priority", 0))
		var request_scale := float(request.get("scale", 1.0))
		if request_priority > strongest_priority:
			strongest_priority = request_priority
			strongest_scale = request_scale
		elif request_priority == strongest_priority:
			strongest_scale = minf(strongest_scale, request_scale)
	Engine.time_scale = minf(_restore_time_scale, strongest_scale)
