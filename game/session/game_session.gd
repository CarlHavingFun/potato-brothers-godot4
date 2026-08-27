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


func start(config: SessionConfig, snapshot: ContentSnapshot) -> Error:
	if _started_once or run_state != null:
		return ERR_ALREADY_IN_USE
	if config == null or not config.is_valid() or snapshot == null:
		return ERR_INVALID_PARAMETER
	if not snapshot.has_definition(config.character_id, &"character"):
		return ERR_DOES_NOT_EXIST
	if not snapshot.has_definition(config.starting_weapon_id, &"weapon"):
		return ERR_DOES_NOT_EXIST
	if not snapshot.has_definition(config.difficulty_id, &"difficulty"):
		return ERR_DOES_NOT_EXIST
	if not snapshot.has_definition(config.zone_id, &"zone"):
		return ERR_DOES_NOT_EXIST
	run_state = GogoRunState.new()
	run_state.run_seed = config.seed
	run_state.zone_id = config.zone_id
	run_state.difficulty_id = config.difficulty_id
	run_state.phase = &"combat"
	var player := SessionPlayerState.new()
	player.player_index = 0
	player.character_id = config.character_id
	player.weapon_ids.append(config.starting_weapon_id)
	var character: CharacterDefinition = snapshot.definition(config.character_id, &"character")
	player.base_stats = character.base_stats.duplicate(true)
	player.final_stats = player.base_stats.duplicate(true)
	player.max_health = float(player.final_stats.get(&"max_health", 10.0))
	player.current_health = player.max_health
	run_state.players.append(player)
	content_snapshot = snapshot
	rng.seed = config.seed
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
		player.add_materials(amount)


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
	if run_state == null or run_state.ended:
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
	phase_changed.emit(previous, next_phase)
	state_changed.emit()
	return OK


func finish_wave() -> void:
	if run_state == null or run_state.phase != &"combat":
		return
	var player := run_state.player()
	if player != null:
		run_state.pending_upgrade_count += player.add_xp(20 + run_state.current_wave * 3)
		player.add_materials(12 + run_state.current_wave * 4)
	transition(&"upgrade" if run_state.pending_upgrade_count > 0 else &"shop")


func continue_after_shop() -> bool:
	if run_state == null:
		return false
	var previous := run_state.phase
	var continues := run_state.advance_wave()
	phase_changed.emit(previous, run_state.phase)
	state_changed.emit()
	if not continues:
		run_ended.emit(true)
	return continues


func fail_run() -> void:
	if run_state == null:
		return
	run_state.ended = true
	run_state.won = false
	run_state.phase = &"settlement"
	state_changed.emit()
	run_ended.emit(false)
