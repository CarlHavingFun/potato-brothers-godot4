extends GdUnitTestSuite


const PRESENTER_PATH := "res://game/gameplay/feedback/combat_audio_presenter.gd"
const COMBAT_SCREEN := preload("res://game/ui/combat_screen.gd")


func test_maps_four_shot_profiles_and_keeps_same_tick_voices_separate() -> void:
	assert_bool(ResourceLoader.exists(PRESENTER_PATH)).is_true()
	if not ResourceLoader.exists(PRESENTER_PATH):
		return
	var audio := await _ready_audio_service(0.5)
	var presenter := _new_presenter(audio)
	var profiles: Array[StringName] = [&"rapid", &"rifle", &"heavy", &"suppressed"]
	for index in profiles.size():
		assert_bool(bool(presenter.call(
			&"present_weapon_fired",
			index + 1,
			profiles[index],
			Vector2i(100 + index, 200),
			Vector2.RIGHT,
			1,
			1
		))).is_true()

	var ledger: Array = presenter.call(&"debug_ledger")
	assert_int(ledger.size()).is_equal(4)
	assert_array(ledger.map(func(event: Dictionary) -> StringName: return event.variant)).is_equal(profiles)
	assert_array(ledger.map(func(event: Dictionary) -> String: return event.stream_path)).is_equal([
		"res://game/assets/audio/combat/rapid_shot.wav",
		"res://game/assets/audio/combat/rifle_shot.wav",
		"res://game/assets/audio/combat/heavy_shot.wav",
		"res://game/assets/audio/combat/suppressed_shot.wav",
	])
	assert_array(ledger.map(func(event: Dictionary) -> int: return int(event.voice_index))).is_equal([0, 1, 2, 3])
	var rifle_voice := audio.sfx_players[int(ledger[1].voice_index)]
	var suppressed_voice := audio.sfx_players[int(ledger[3].voice_index)]
	assert_float(rifle_voice.volume_db).is_equal_approx(linear_to_db(0.5), 0.001)
	assert_float(suppressed_voice.volume_db).is_equal_approx(rifle_voice.volume_db, 0.001)
	for index in 4:
		assert_bool(audio.sfx_players[index].playing).is_true()
	var relative_rms_db := _relative_output_rms_db(rifle_voice, suppressed_voice)
	assert_float(relative_rms_db).is_less_equal(-8.0)
	assert_float(relative_rms_db).is_greater_equal(-14.0)


func test_maps_all_contacts_and_terminal_events_to_original_wavs() -> void:
	assert_bool(ResourceLoader.exists(PRESENTER_PATH)).is_true()
	if not ResourceLoader.exists(PRESENTER_PATH):
		return
	var audio := await _ready_audio_service(1.0)
	var presenter := _new_presenter(audio)
	var impacts: Array[StringName] = [&"normal", &"critical", &"pierce_exit", &"explosion"]
	for index in impacts.size():
		assert_bool(bool(presenter.call(
			&"present_projectile_contact",
			index + 1,
			100 + index,
			&"rifle",
			Vector2i(10 + index, 20),
			Vector2.LEFT,
			&"ballistic",
			impacts[index],
			1
		))).is_true()
	assert_bool(bool(presenter.call(
		&"present_melee_contact", 20, 120, &"heavy", Vector2i(30, 40),
		Vector2.RIGHT, &"melee", &"normal", 1
	))).is_true()
	assert_bool(bool(presenter.call(
		&"present_enemy_defeated", 40, Vector2i(50, 60), 4, 2, 1
	))).is_true()
	assert_bool(bool(presenter.call(
		&"present_player_damage_taken", Vector2i(70, 80), 3.0, 17.0, false, 1
	))).is_true()
	assert_bool(bool(presenter.call(
		&"present_pickup_collected", 50, GameSession.REWARD_EXPERIENCE, 4,
		Vector2i(90, 100), 1
	))).is_true()
	assert_bool(bool(presenter.call(
		&"present_pickup_collected", 51, GameSession.REWARD_SUPPLY, 2,
		Vector2i(91, 101), 2
	))).is_true()

	var ledger: Array = presenter.call(&"debug_ledger")
	assert_array(ledger.map(func(event: Dictionary) -> StringName: return event.event_class)).is_equal([
		&"projectile_contact", &"projectile_contact", &"projectile_contact",
		&"projectile_contact", &"melee_contact", &"enemy_defeated",
		&"player_damage_taken", &"pickup_collected", &"pickup_collected",
	])
	assert_array(ledger.map(func(event: Dictionary) -> StringName: return event.variant)).is_equal([
		&"normal", &"critical", &"pierce_exit", &"explosion", &"normal",
		&"enemy_down", &"player_hit", GameSession.REWARD_EXPERIENCE,
		GameSession.REWARD_SUPPLY,
	])
	assert_array(ledger.map(func(event: Dictionary) -> String: return event.stream_path)).is_equal([
		"res://game/assets/audio/combat/impact_normal.wav",
		"res://game/assets/audio/combat/impact_critical.wav",
		"res://game/assets/audio/combat/impact_normal.wav",
		"res://game/assets/audio/combat/impact_explosion.wav",
		"res://game/assets/audio/combat/impact_normal.wav",
		"res://game/assets/audio/combat/enemy_down.wav",
		"res://game/assets/audio/combat/player_hit.wav",
		"res://game/assets/audio/combat/pickup.wav",
		"res://game/assets/audio/combat/pickup.wav",
	])
	assert_int(int(ledger[0].get("source_instance_id", -1))).is_equal(1)
	assert_int(int(ledger[0].get("target_instance_id", -1))).is_equal(100)
	assert_int(int(ledger[0].get("sequence", -1))).is_equal(1)
	assert_int(int(ledger[6].get("sequence", -1))).is_equal(1)
	assert_float(float(ledger[6].get("remaining_health", -1.0))).is_equal(17.0)


func test_invalid_payloads_never_play_or_enter_debug_ledger() -> void:
	assert_bool(ResourceLoader.exists(PRESENTER_PATH)).is_true()
	if not ResourceLoader.exists(PRESENTER_PATH):
		return
	var audio := await _ready_audio_service(1.0)
	var presenter := _new_presenter(audio)
	assert_bool(bool(presenter.call(
		&"present_weapon_fired", 1, &"unknown", Vector2i.ZERO, Vector2.RIGHT, 1, 1
	))).is_false()
	assert_bool(bool(presenter.call(
		&"present_projectile_contact", 1, 2, &"rifle", Vector2i.ZERO,
		Vector2.LEFT, &"ballistic", &"unknown", 1
	))).is_false()
	assert_bool(bool(presenter.call(
		&"present_enemy_defeated", 0, Vector2i.ZERO, 1, 1, 1
	))).is_false()
	assert_bool(bool(presenter.call(
		&"present_pickup_collected", 1, &"unknown", 1, Vector2i.ZERO, 1
	))).is_false()
	assert_array(presenter.call(&"debug_ledger")).is_empty()
	for voice in audio.sfx_players:
		assert_bool(voice.playing).is_false()


func test_combat_screen_routes_each_canonical_signal_once_when_wired_twice() -> void:
	assert_bool(ResourceLoader.exists(PRESENTER_PATH)).is_true()
	if not ResourceLoader.exists(PRESENTER_PATH):
		return
	var screen := auto_free(COMBAT_SCREEN.new()) as Node2D
	assert_bool(screen.has_method(&"_route_combat_audio_events_once")).is_true()
	if not screen.has_method(&"_route_combat_audio_events_once"):
		return
	var audio := await _ready_audio_service(1.0)
	var presenter := _new_presenter(audio)
	var world := auto_free(CombatWorld.new()) as CombatWorld
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	world.player_actor = player

	screen.call(&"_route_combat_audio_events_once", world, presenter)
	screen.call(&"_route_combat_audio_events_once", world, presenter)
	world.weapon_fired.emit(1, &"rapid", Vector2i.ZERO, Vector2.RIGHT, 1, 1)
	world.projectile_contact.emit(
		2, 3, &"rifle", Vector2i.ZERO, Vector2.LEFT, &"ballistic", &"normal", 1
	)
	world.melee_contact.emit(
		4, 5, &"heavy", Vector2i.ZERO, Vector2.RIGHT, &"melee", &"critical", 1
	)
	world.enemy_defeated.emit(6, Vector2i.ZERO, 4, 2, 1)
	world.pickup_collected.emit(
		7, GameSession.REWARD_EXPERIENCE, 4, Vector2i.ZERO, 1
	)
	player.damage_taken.emit(Vector2i.ZERO, 1.0, 19.0, false, 1)

	var ledger: Array = presenter.call(&"debug_ledger")
	assert_array(ledger.map(func(event: Dictionary) -> StringName: return event.event_class)).is_equal([
		&"weapon_fired", &"projectile_contact", &"melee_contact",
		&"enemy_defeated", &"pickup_collected", &"player_damage_taken",
	])
	assert_array(ledger.map(func(event: Dictionary) -> int: return int(event.serial))).is_equal([
		1, 2, 3, 4, 5, 6,
	])
	assert_int(int(ledger[2].get("source_instance_id", -1))).is_equal(4)
	assert_int(int(ledger[2].get("target_instance_id", -1))).is_equal(5)
	assert_int(int(ledger[2].get("sequence", -1))).is_equal(1)
	assert_int(int(ledger[5].get("sequence", -1))).is_equal(1)
	assert_float(float(ledger[5].get("remaining_health", -1.0))).is_equal(19.0)


func test_scene_teardown_automatically_disconnects_audio_receivers() -> void:
	var audio := await _ready_audio_service(1.0)
	var screen := COMBAT_SCREEN.new() as Node2D
	add_child(screen)
	var presenter_script := load(PRESENTER_PATH) as Script
	var presenter := presenter_script.new() as Node
	presenter.call(&"configure", audio)
	screen.add_child(presenter)
	var world := auto_free(CombatWorld.new()) as CombatWorld
	var player := auto_free(GogoPlayerActor.new()) as GogoPlayerActor
	world.player_actor = player

	screen.call(&"_route_combat_audio_events_once", world, presenter)
	assert_int(world.weapon_fired.get_connections().size()).is_equal(1)
	assert_int(player.damage_taken.get_connections().size()).is_equal(1)

	screen.free()
	assert_array(world.weapon_fired.get_connections()).is_empty()
	assert_array(player.damage_taken.get_connections()).is_empty()


func _ready_audio_service(effects_volume: float) -> GogoAudioService:
	var audio := auto_free(GogoAudioService.new()) as GogoAudioService
	add_child(audio)
	await get_tree().process_frame
	var settings := GogoSettingsService.new()
	settings.values["effects_volume"] = effects_volume
	audio.apply_settings(settings)
	return audio


func _new_presenter(audio: GogoAudioService) -> Node:
	var script := load(PRESENTER_PATH) as Script
	var presenter := auto_free(script.new()) as Node
	presenter.call(&"configure", audio)
	return presenter


func _relative_output_rms_db(
	rifle_voice: AudioStreamPlayer,
	suppressed_voice: AudioStreamPlayer
) -> float:
	var rifle_rms := _source_wav_rms(rifle_voice.stream.resource_path)
	var suppressed_rms := _source_wav_rms(suppressed_voice.stream.resource_path)
	return linear_to_db(
		(suppressed_rms * db_to_linear(suppressed_voice.volume_db))
		/ (rifle_rms * db_to_linear(rifle_voice.volume_db))
	)


func _source_wav_rms(path: String) -> float:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_object(file).is_not_null()
	if file == null:
		return 0.0
	file.big_endian = false
	file.seek(44)
	var sum_squares := 0.0
	var sample_count := 0
	while file.get_position() + 1 < file.get_length():
		var raw_sample := file.get_16()
		var signed_sample := raw_sample - 65536 if raw_sample >= 32768 else raw_sample
		var sample := float(signed_sample) / 32768.0
		sum_squares += sample * sample
		sample_count += 1
	return sqrt(sum_squares / float(sample_count)) if sample_count > 0 else 0.0
