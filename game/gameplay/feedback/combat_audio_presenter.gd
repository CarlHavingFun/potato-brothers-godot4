class_name GogoCombatAudioPresenter
extends Node

const VALID_PROFILES: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
const VALID_IMPACTS: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
const SHOT_SETTINGS := {
	&"rapid": {
		"stream": preload("res://game/assets/audio/combat/rapid_shot.wav"),
		"volume_db": -1.0,
		"pitch_scale": 1.03,
	},
	&"rifle": {
		"stream": preload("res://game/assets/audio/combat/rifle_shot.wav"),
		"volume_db": 0.0,
		"pitch_scale": 1.0,
	},
	&"heavy": {
		"stream": preload("res://game/assets/audio/combat/heavy_shot.wav"),
		"volume_db": -1.0,
		"pitch_scale": 0.96,
	},
	&"suppressed": {
		"stream": preload("res://game/assets/audio/combat/suppressed_shot.wav"),
		"volume_db": 0.0,
		"pitch_scale": 1.0,
	},
}
const IMPACT_SETTINGS := {
	&"normal": {
		"stream": preload("res://game/assets/audio/combat/impact_normal.wav"),
		"volume_db": -2.0,
		"pitch_scale": 1.0,
	},
	&"critical": {
		"stream": preload("res://game/assets/audio/combat/impact_critical.wav"),
		"volume_db": -1.0,
		"pitch_scale": 1.04,
	},
	&"pierce_exit": {
		"stream": preload("res://game/assets/audio/combat/impact_normal.wav"),
		"volume_db": -3.0,
		"pitch_scale": 1.18,
	},
	&"explosion": {
		"stream": preload("res://game/assets/audio/combat/impact_explosion.wav"),
		"volume_db": -2.0,
		"pitch_scale": 0.94,
	},
}
const ENEMY_DOWN := preload("res://game/assets/audio/combat/enemy_down.wav")
const PLAYER_HIT := preload("res://game/assets/audio/combat/player_hit.wav")
const PICKUP := preload("res://game/assets/audio/combat/pickup.wav")
const PICKUP_SOUND_DEDUPE_WINDOW_MSEC := 80

var audio_service: GogoAudioService
var _ledger: Array[Dictionary] = []
var _serial := 0
var _recent_pickup_sound_msec: Dictionary = {}


func configure(next_audio_service: GogoAudioService) -> void:
	audio_service = next_audio_service
	_ledger.clear()
	_serial = 0
	_recent_pickup_sound_msec.clear()


func present_weapon_fired(
	weapon_instance_id: int,
	feedback_profile_id: StringName,
	_integer_muzzle_global_position: Vector2i,
	shot_direction: Vector2,
	projectile_count: int,
	shot_sequence: int
) -> bool:
	if (
		weapon_instance_id <= 0
		or projectile_count <= 0
		or shot_sequence <= 0
		or not VALID_PROFILES.has(feedback_profile_id)
		or not shot_direction.is_finite()
		or shot_direction.is_zero_approx()
	):
		return false
	return _play_settings(&"weapon_fired", feedback_profile_id, SHOT_SETTINGS[feedback_profile_id])


func present_melee_contact(
	weapon_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	melee_sequence: int
) -> bool:
	return _present_contact(
		&"melee_contact",
		weapon_instance_id,
		target_instance_id,
		feedback_profile_id,
		contact_normal,
		damage_kind,
		impact_kind,
		melee_sequence
	)


func present_projectile_contact(
	projectile_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	_integer_contact_global_position: Vector2i,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	contact_sequence: int
) -> bool:
	return _present_contact(
		&"projectile_contact",
		projectile_instance_id,
		target_instance_id,
		feedback_profile_id,
		contact_normal,
		damage_kind,
		impact_kind,
		contact_sequence
	)


func present_enemy_defeated(
	enemy_instance_id: int,
	_integer_death_global_position: Vector2i,
	xp: int,
	materials: int,
	death_sequence: int
) -> bool:
	if enemy_instance_id <= 0 or xp < 0 or materials < 0 or death_sequence <= 0:
		return false
	return _play(&"enemy_defeated", &"enemy_down", ENEMY_DOWN, -2.0, 0.95)


func present_player_damage_taken(
	_integer_global_position: Vector2i,
	final_damage: float,
	remaining_health: float,
	_lethal: bool,
	sequence: int
) -> bool:
	if (
		sequence <= 0
		or not is_finite(final_damage)
		or final_damage <= 0.0
		or not is_finite(remaining_health)
		or remaining_health < 0.0
	):
		return false
	return _play(
		&"player_damage_taken",
		&"player_hit",
		PLAYER_HIT,
		0.0,
		1.0,
		{
			"final_damage": final_damage,
			"remaining_health": remaining_health,
			"lethal": _lethal,
			"sequence": sequence,
		}
	)


func present_pickup_collected(
	pickup_instance_id: int,
	reward_kind: StringName,
	amount: int,
	_integer_global_position: Vector2i,
	collection_sequence: int
) -> bool:
	if (
		pickup_instance_id <= 0
		or amount <= 0
		or collection_sequence <= 0
		or not [GameSession.REWARD_EXPERIENCE, GameSession.REWARD_SUPPLY].has(reward_kind)
	):
		return false
	var now_msec := Time.get_ticks_msec()
	_prune_recent_pickup_sounds(now_msec)
	if _recent_pickup_sound_msec.has(pickup_instance_id):
		return false
	var played := _play(&"pickup_collected", reward_kind, PICKUP, -4.0, 1.08)
	if played:
		_recent_pickup_sound_msec[pickup_instance_id] = now_msec
	return played


func _prune_recent_pickup_sounds(now_msec: int) -> void:
	for pickup_id: int in _recent_pickup_sound_msec.keys():
		var played_at_msec := int(_recent_pickup_sound_msec[pickup_id])
		if now_msec - played_at_msec > PICKUP_SOUND_DEDUPE_WINDOW_MSEC:
			_recent_pickup_sound_msec.erase(pickup_id)


func debug_ledger() -> Array[Dictionary]:
	return _ledger.duplicate(true)


func _present_contact(
	event_class: StringName,
	source_instance_id: int,
	target_instance_id: int,
	feedback_profile_id: StringName,
	contact_normal: Vector2,
	damage_kind: StringName,
	impact_kind: StringName,
	sequence: int
) -> bool:
	if (
		source_instance_id <= 0
		or target_instance_id <= 0
		or sequence <= 0
		or not VALID_PROFILES.has(feedback_profile_id)
		or damage_kind.is_empty()
		or not VALID_IMPACTS.has(impact_kind)
		or not contact_normal.is_finite()
		or contact_normal.is_zero_approx()
	):
		return false
	return _play_settings(
		event_class,
		impact_kind,
		IMPACT_SETTINGS[impact_kind],
		{
			"source_instance_id": source_instance_id,
			"target_instance_id": target_instance_id,
			"feedback_profile_id": feedback_profile_id,
			"damage_kind": damage_kind,
			"sequence": sequence,
		}
	)


func _play_settings(
	event_class: StringName,
	variant: StringName,
	settings: Dictionary,
	metadata: Dictionary = {}
) -> bool:
	return _play(
		event_class,
		variant,
		settings.stream as AudioStream,
		float(settings.volume_db),
		float(settings.pitch_scale),
		metadata
	)


func _play(
	event_class: StringName,
	variant: StringName,
	stream: AudioStream,
	volume_db: float,
	pitch_scale: float,
	metadata: Dictionary = {}
) -> bool:
	if audio_service == null:
		return false
	var voice := audio_service.play_effect(stream, volume_db, pitch_scale)
	if voice == null:
		return false
	_serial += 1
	var entry := {
		"serial": _serial,
		"event_class": event_class,
		"variant": variant,
		"stream_path": stream.resource_path,
		"volume_db": voice.volume_db,
		"pitch_scale": voice.pitch_scale,
		"voice_index": audio_service.sfx_players.find(voice),
	}
	entry.merge(metadata, true)
	_ledger.append(entry)
	return true
