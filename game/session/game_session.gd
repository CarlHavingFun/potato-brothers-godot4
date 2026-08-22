class_name GameSession
extends RefCounted

signal phase_changed(previous: StringName, current: StringName)
signal state_changed
signal run_ended(victory: bool)

var run_state: GogoRunState
var content_snapshot: ContentSnapshot
var rng := RandomNumberGenerator.new()


func start(config: SessionConfig, snapshot: ContentSnapshot) -> Error:
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
	state_changed.emit()
	return OK


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
	if run_state == null:
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
