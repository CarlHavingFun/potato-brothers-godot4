class_name CombatFeedbackProfile
extends Resource


@export var profile_id: StringName
@export_range(0.0, 0.2, 0.001) var hit_stop_seconds := 0.0
@export_range(0.01, 1.0, 0.01) var hit_stop_scale := 1.0
@export_range(0.0, 20.0, 0.1) var shake_strength := 0.0
@export_range(0.0, 1.0, 0.01) var rumble_weak := 0.0
@export_range(0.0, 1.0, 0.01) var rumble_strong := 0.0
@export_range(0.0, 1.0, 0.01) var rumble_duration := 0.0
@export_range(0.25, 2.0, 0.01) var audio_pitch_min := 1.0
@export_range(0.25, 2.0, 0.01) var audio_pitch_max := 1.0
@export_range(0.5, 3.0, 0.05) var damage_text_scale := 1.0
@export_range(0.0, 1.0, 0.001) var minimum_interval_seconds := 0.0
@export_range(0, 100, 1) var priority := 0


func to_dict() -> Dictionary:
	return {
		"profile_id": String(profile_id),
		"hit_stop_seconds": hit_stop_seconds,
		"hit_stop_scale": hit_stop_scale,
		"shake_strength": shake_strength,
		"rumble_weak": rumble_weak,
		"rumble_strong": rumble_strong,
		"rumble_duration": rumble_duration,
		"audio_pitch_min": audio_pitch_min,
		"audio_pitch_max": audio_pitch_max,
		"damage_text_scale": damage_text_scale,
		"minimum_interval_seconds": minimum_interval_seconds,
		"priority": priority,
	}


static func for_cue(cue_id: StringName, override: Variant = null) -> CombatFeedbackProfile:
	var result := _default_for_cue(cue_id)
	if override is CombatFeedbackProfile:
		return (override as CombatFeedbackProfile).duplicate(true) as CombatFeedbackProfile
	if override is not Dictionary:
		return result
	var values := override as Dictionary
	result.profile_id = StringName(str(values.get("profile_id", result.profile_id)))
	result.hit_stop_seconds = clampf(
		float(values.get("hit_stop_seconds", result.hit_stop_seconds)), 0.0, 0.2
	)
	result.hit_stop_scale = clampf(
		float(values.get("hit_stop_scale", result.hit_stop_scale)), 0.01, 1.0
	)
	result.shake_strength = clampf(
		float(values.get("shake_strength", result.shake_strength)), 0.0, 20.0
	)
	result.rumble_weak = clampf(float(values.get("rumble_weak", result.rumble_weak)), 0.0, 1.0)
	result.rumble_strong = clampf(
		float(values.get("rumble_strong", result.rumble_strong)), 0.0, 1.0
	)
	result.rumble_duration = clampf(
		float(values.get("rumble_duration", result.rumble_duration)), 0.0, 1.0
	)
	result.audio_pitch_min = clampf(
		float(values.get("audio_pitch_min", result.audio_pitch_min)), 0.25, 2.0
	)
	result.audio_pitch_max = clampf(
		float(values.get("audio_pitch_max", result.audio_pitch_max)),
		result.audio_pitch_min,
		2.0
	)
	result.damage_text_scale = clampf(
		float(values.get("damage_text_scale", result.damage_text_scale)), 0.5, 3.0
	)
	result.minimum_interval_seconds = clampf(
		float(values.get("minimum_interval_seconds", result.minimum_interval_seconds)), 0.0, 1.0
	)
	result.priority = clampi(int(values.get("priority", result.priority)), 0, 100)
	return result


static func _default_for_cue(cue_id: StringName) -> CombatFeedbackProfile:
	var result := CombatFeedbackProfile.new()
	result.profile_id = cue_id
	match cue_id:
		&"hit.normal":
			result.hit_stop_seconds = 0.008
			result.hit_stop_scale = 0.42
			result.audio_pitch_min = 0.96
			result.audio_pitch_max = 1.04
			result.minimum_interval_seconds = 0.035
			result.priority = 10
		&"hit.critical":
			result.hit_stop_seconds = 0.032
			result.hit_stop_scale = 0.14
			result.shake_strength = 6.0
			result.rumble_weak = 0.25
			result.rumble_strong = 0.5
			result.rumble_duration = 0.1
			result.audio_pitch_min = 0.93
			result.audio_pitch_max = 1.02
			result.damage_text_scale = 1.35
			result.minimum_interval_seconds = 0.025
			result.priority = 40
		&"hit.heavy", &"hit.explosion", &"unit.killed":
			result.hit_stop_seconds = 0.024
			result.hit_stop_scale = 0.2
			result.shake_strength = 8.0
			result.rumble_weak = 0.3
			result.rumble_strong = 0.65
			result.rumble_duration = 0.12
			result.damage_text_scale = 1.2
			result.minimum_interval_seconds = 0.04
			result.priority = 50
		&"player.damaged":
			result.hit_stop_seconds = 0.026
			result.hit_stop_scale = 0.18
			result.shake_strength = 10.0
			result.rumble_weak = 0.45
			result.rumble_strong = 0.75
			result.rumble_duration = 0.16
			result.priority = 80
	return result
