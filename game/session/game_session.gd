class_name GameSession
extends RefCounted

signal phase_changed(previous: StringName, current: StringName)
signal state_changed
signal run_ended(victory: bool)
signal reward_committed(token: StringName, kind: StringName, amount: int, player_index: int)

const REWARD_APPLIED: StringName = &"APPLIED"
const REWARD_DUPLICATE: StringName = &"DUPLICATE"
const REWARD_INVALID: StringName = &"INVALID"
const REWARD_TOKEN_COLLISION: StringName = &"TOKEN_COLLISION"
const REWARD_RESERVED: StringName = &"RESERVED"
const REWARD_EXPERIENCE: StringName = &"experience"
const REWARD_SUPPLY: StringName = &"supply"
const REWARD_ENTRY_RESERVED: StringName = &"reserved"
const REWARD_ENTRY_APPLIED: StringName = &"applied"
const WAVE_COMPLETION_XP_BASE := 8
const WAVE_COMPLETION_XP_PER_WAVE := 2
const WAVE_COMPLETION_MATERIAL_BASE := 6
const WAVE_COMPLETION_MATERIAL_PER_WAVE := 2
const MAX_REWARD_WAVE := 220
const RUNTIME_INSTANCE_KINDS: Array[StringName] = [
	&"weapon",
	&"projectile",
	&"enemy",
	&"pickup",
]

var run_state: GogoRunState
var content_snapshot: ContentSnapshot
var static_asset_snapshot: GogoStaticAssetSnapshot
var rng := RandomNumberGenerator.new()
var _started_once := false
var _next_runtime_instance_id := 1
var _next_reward_reservation_id := 1
var _reward_fingerprints: Dictionary = {}
var _transition_busy := false


func start(config: SessionConfig, snapshot: ContentSnapshot) -> Error:
	if _started_once or run_state != null:
		return ERR_ALREADY_IN_USE
	if config == null or not config.is_valid() or snapshot == null:
		return ERR_INVALID_PARAMETER
	var character := snapshot.definition(
		config.character_id, &"character"
	) as CharacterDefinition
	if character == null:
		return ERR_DOES_NOT_EXIST
	var starting_weapon := snapshot.definition(
		config.starting_weapon_id, &"weapon"
	) as GogoWeaponDefinition
	if starting_weapon == null:
		return ERR_DOES_NOT_EXIST
	var difficulty := snapshot.definition(config.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	if difficulty == null:
		return ERR_DOES_NOT_EXIST
	var zone := snapshot.definition(config.zone_id, &"zone") as GogoZoneDefinition
	if zone == null:
		return ERR_DOES_NOT_EXIST
	if GogoWaveResolver.validate_zone(snapshot, zone, difficulty.spawn_multiplier) != OK:
		return ERR_INVALID_DATA
	if not character.allows_weapon(starting_weapon):
		return ERR_INVALID_DATA
	var starting_items: Array[GogoItemDefinition] = []
	for item_id: StringName in character.starting_item_ids:
		var item := snapshot.definition(item_id, &"item") as GogoItemDefinition
		if item == null:
			return ERR_DOES_NOT_EXIST
		if not item.is_available_to(config.character_id):
			return ERR_INVALID_DATA
		starting_items.append(item)
	var next_run_state := GogoRunState.new()
	next_run_state.run_seed = config.seed
	next_run_state.zone_id = config.zone_id
	next_run_state.difficulty_id = config.difficulty_id
	next_run_state.phase = &"combat"
	next_run_state.total_waves = zone.wave_ids.size()
	var player := SessionPlayerState.new()
	player.player_index = 0
	player.character_id = config.character_id
	var weapon_result := player.weapon_inventory.add_weapon(config.starting_weapon_id, snapshot)
	if weapon_result.error != OK:
		return weapon_result.error
	player.base_stats = character.base_stats.duplicate(true)
	for item: GogoItemDefinition in starting_items:
		player.item_ids.append(item.content_id)
	var build_error := PlayerBuildService.new().rebuild_from_snapshot(snapshot, player)
	if build_error != OK:
		return build_error
	next_run_state.players.append(player)
	run_state = next_run_state
	content_snapshot = snapshot
	rng.seed = config.seed
	run_state.rng_state = rng.state
	_started_once = true
	state_changed.emit()
	return OK


func prepare_checkpoint() -> Error:
	if not _started_once or run_state == null or content_snapshot == null:
		return ERR_UNAVAILABLE
	run_state.schema_version = GogoRunState.SCHEMA_VERSION
	run_state.rng_state = rng.state
	var parsed := GogoRunState.parse_dictionary(run_state.to_dictionary(), content_snapshot)
	return parsed.error


func restore_from_checkpoint(state: GogoRunState, snapshot: ContentSnapshot) -> Error:
	if _started_once or run_state != null:
		return ERR_ALREADY_IN_USE
	if state == null or snapshot == null:
		return ERR_INVALID_PARAMETER
	# Reparse into a detached candidate even when the caller already parsed it.
	# This makes publication contingent on the current content snapshot and keeps
	# a caller-owned Resource from becoming live mutable session state.
	var parsed := GogoRunState.parse_dictionary(state.to_dictionary(), snapshot)
	if parsed.error != OK:
		return parsed.error
	var candidate := parsed.state as GogoRunState
	if (
		candidate == null
		or candidate.ended
		or candidate.won
		or candidate.phase not in [&"combat", &"upgrade", &"shop"]
		or candidate.players.size() != 1
	):
		return ERR_INVALID_DATA
	var player := candidate.player()
	if player == null or player.player_index != 0 or player.current_health <= 0.0:
		return ERR_INVALID_DATA
	if (
		(candidate.phase == &"upgrade" and candidate.pending_upgrade_count <= 0)
		or (candidate.phase in [&"combat", &"shop"] and candidate.pending_upgrade_count != 0)
	):
		return ERR_INVALID_DATA
	var difficulty := snapshot.definition(candidate.difficulty_id, &"difficulty") as GogoDifficultyDefinition
	var zone := snapshot.definition(candidate.zone_id, &"zone") as GogoZoneDefinition
	if (
		difficulty == null
		or zone == null
		or candidate.total_waves != zone.wave_ids.size()
		or GogoWaveResolver.validate_zone(snapshot, zone, difficulty.spawn_multiplier) != OK
	):
		return ERR_INVALID_DATA
	# Combat checkpoints restart the authored wave boundary. They never claim to
	# reconstruct entities, timers, pickups, or damage from an arbitrary mid-wave.
	if candidate.phase == &"combat":
		var probe := GameSession.new()
		probe.run_state = candidate
		probe.content_snapshot = snapshot
		if GogoWaveResolver.resolve(probe) == null:
			return ERR_INVALID_DATA
	run_state = candidate
	content_snapshot = snapshot
	rng.seed = candidate.run_seed
	rng.state = candidate.rng_state
	_started_once = true
	state_changed.emit()
	return OK


func allocate_runtime_instance_id(kind: StringName) -> int:
	if not RUNTIME_INSTANCE_KINDS.has(kind):
		return 0
	var allocated := _next_runtime_instance_id
	_next_runtime_instance_id += 1
	return allocated


func commit_reward_once(token: StringName, kind: StringName, amount: int, player_index: int) -> StringName:
	var request := _validated_reward_request(token, kind, amount, player_index)
	if request.is_empty():
		return REWARD_INVALID
	var fingerprint: Array = request.fingerprint
	if _reward_fingerprints.has(token):
		var stored: Dictionary = _reward_fingerprints[token]
		if stored.fingerprint == fingerprint:
			return REWARD_DUPLICATE
		push_warning("Reward token collision rejected: %s" % String(token))
		return REWARD_TOKEN_COLLISION
	var player := request.player as SessionPlayerState
	_apply_reward(player, kind, amount)
	# Store before publication so a synchronous reentrant submission is a duplicate.
	_reward_fingerprints[token] = {
		"fingerprint": fingerprint,
		"state": REWARD_ENTRY_APPLIED,
		"reservation_id": 0,
	}
	reward_committed.emit(token, kind, amount, player_index)
	return REWARD_APPLIED


func reserve_reward_once(token: StringName, kind: StringName, amount: int, player_index: int) -> Dictionary:
	var request := _validated_reward_request(token, kind, amount, player_index)
	if request.is_empty():
		return {"status": REWARD_INVALID, "token": token, "reservation_id": 0}
	var fingerprint: Array = request.fingerprint
	if _reward_fingerprints.has(token):
		var stored: Dictionary = _reward_fingerprints[token]
		if stored.fingerprint == fingerprint:
			return {"status": REWARD_DUPLICATE, "token": token, "reservation_id": 0}
		push_warning("Reward token collision rejected while reserving: %s" % String(token))
		return {"status": REWARD_TOKEN_COLLISION, "token": token, "reservation_id": 0}
	var reservation_id := _next_reward_reservation_id
	_next_reward_reservation_id += 1
	_reward_fingerprints[token] = {
		"fingerprint": fingerprint,
		"state": REWARD_ENTRY_RESERVED,
		"reservation_id": reservation_id,
	}
	return {"status": REWARD_RESERVED, "token": token, "reservation_id": reservation_id}


func apply_reserved_reward(token: StringName, reservation_id: int) -> StringName:
	if token.is_empty() or reservation_id <= 0 or not _reward_fingerprints.has(token):
		return REWARD_INVALID
	var entry: Dictionary = _reward_fingerprints[token]
	if int(entry.get("reservation_id", 0)) != reservation_id:
		return REWARD_INVALID
	if StringName(entry.get("state", &"")) == REWARD_ENTRY_APPLIED:
		return REWARD_DUPLICATE
	if StringName(entry.get("state", &"")) != REWARD_ENTRY_RESERVED:
		return REWARD_INVALID
	var fingerprint: Array = entry.fingerprint
	var kind := fingerprint[0] as StringName
	var amount := int(fingerprint[1])
	var player_index := int(fingerprint[2])
	var player := _reward_player_by_index(player_index)
	if player == null:
		return REWARD_INVALID
	_apply_reward(player, kind, amount)
	entry["state"] = REWARD_ENTRY_APPLIED
	_reward_fingerprints[token] = entry
	reward_committed.emit(token, kind, amount, player_index)
	return REWARD_APPLIED


func committed_reward_count() -> int:
	return _reward_fingerprints.size()


func _validated_reward_request(token: StringName, kind: StringName, amount: int, player_index: int) -> Dictionary:
	var player := _reward_player_by_index(player_index)
	if (
		run_state == null
		or token.is_empty()
		or not [REWARD_EXPERIENCE, REWARD_SUPPLY].has(kind)
		or amount <= 0
		or player == null
	):
		return {}
	return {
		"player": player,
		"fingerprint": [kind, amount, player_index],
	}


func _apply_reward(player: SessionPlayerState, kind: StringName, amount: int) -> void:
	if kind == REWARD_EXPERIENCE:
		run_state.pending_upgrade_count += player.add_xp(amount)
	else:
		player.add_reward_materials(amount)


func _reward_player_by_index(player_index: int) -> SessionPlayerState:
	if run_state == null:
		return null
	var matched: SessionPlayerState
	for candidate in run_state.players:
		if candidate != null and candidate.player_index == player_index:
			if matched != null:
				return null
			matched = candidate
	return matched


func transition(next_phase: StringName) -> Error:
	if run_state == null or run_state.ended or _transition_busy:
		return ERR_UNAVAILABLE
	var allowed: Dictionary = {
		&"combat": [&"upgrade", &"shop", &"settlement"],
		&"upgrade": [&"shop"],
		&"shop": [&"combat", &"settlement"],
	}
	var possible: Array = allowed.get(run_state.phase, [])
	if not possible.has(next_phase):
		return ERR_INVALID_DATA
	var previous := run_state.phase
	run_state.phase = next_phase
	if next_phase == &"upgrade" and previous != &"upgrade":
		run_state.upgrade_reroll_count = 0
	_publish_transition(previous)
	return OK


func finish_wave() -> void:
	if run_state == null or run_state.ended or _transition_busy or run_state.phase != &"combat":
		return
	var player := run_state.player()
	if player == null or player.current_health <= 0.0 or run_state.current_wave < 1:
		return
	_transition_busy = true
	# Both the guard and phase commit precede synchronous reward publication.
	run_state.phase = &"upgrade"
	var wave := run_state.current_wave
	commit_reward_once(StringName("wave/%d/xp" % wave), REWARD_EXPERIENCE, fixed_wave_xp_reward(wave), player.player_index)
	commit_reward_once(StringName("wave/%d/materials" % wave), REWARD_SUPPLY, fixed_wave_material_reward(wave), player.player_index)
	run_state.phase = &"upgrade" if run_state.pending_upgrade_count > 0 else &"shop"
	run_state.upgrade_reroll_count = 0
	_publish_transition(&"combat")


static func fixed_wave_xp_reward(wave: int) -> int:
	return WAVE_COMPLETION_XP_BASE + clampi(wave, 1, MAX_REWARD_WAVE) * WAVE_COMPLETION_XP_PER_WAVE


static func fixed_wave_material_reward(wave: int) -> int:
	return (
		WAVE_COMPLETION_MATERIAL_BASE
		+ clampi(wave, 1, MAX_REWARD_WAVE) * WAVE_COMPLETION_MATERIAL_PER_WAVE
	)


func continue_after_shop() -> bool:
	if run_state == null or _transition_busy or not _living_player():
		return false
	var previous := run_state.phase
	if not run_state.advance_wave():
		return false
	_publish_transition(previous)
	return true


func is_final_shop() -> bool:
	return run_state != null and not run_state.ended and not run_state.endless \
		and run_state.phase == &"shop" and run_state.pending_upgrade_count == 0 \
		and run_state.total_waves > 0 and run_state.current_wave == run_state.total_waves \
		and _living_player()


func finish_normal_run() -> bool:
	if _transition_busy or not is_final_shop():
		return false
	_end_run(true)
	return true


func continue_endless() -> bool:
	if _transition_busy or not is_final_shop() or run_state.current_wave == 9223372036854775807:
		return false
	run_state.endless = true
	return continue_after_shop()


func _living_player() -> bool:
	return run_state != null and run_state.player() != null and run_state.player().current_health > 0.0


func _publish_transition(previous: StringName, terminal: bool = false) -> void:
	_transition_busy = true
	phase_changed.emit(previous, run_state.phase)
	state_changed.emit()
	if terminal:
		run_ended.emit(run_state.won)
	_transition_busy = false


func _end_run(victory: bool) -> void:
	var previous := run_state.phase
	run_state.ended = true
	run_state.won = victory
	run_state.phase = &"settlement"
	_publish_transition(previous, true)


func fail_run() -> void:
	if run_state == null or run_state.ended or _transition_busy:
		return
	_end_run(false)
