class_name SelectionFlow
extends RefCounted


signal step_changed(step: int)
signal draft_changed(draft: SelectionDraft)
signal run_requested(request: RunLaunchRequest)

var current_step: int = SelectionStep.Value.TITLE
var draft := SelectionDraft.new()
var _history: Array[int] = []


func begin_new_run(
	profile_id: int,
	random_seed: int,
	aim_mode: int,
	run_mode: int = RunMode.STANDARD
) -> bool:
	if profile_id not in range(1, 4) or not AimMode.is_valid(aim_mode) or not RunMode.is_valid(run_mode):
		return false
	draft = SelectionDraft.new()
	draft.profile_id = profile_id
	draft.random_seed = random_seed
	draft.aim_mode = aim_mode
	draft.run_mode = run_mode
	_history.clear()
	_transition_to(SelectionStep.Value.CHARACTER)
	draft_changed.emit(draft)
	return true


func set_run_mode(run_mode: int) -> bool:
	if current_step != SelectionStep.Value.CHARACTER or not RunMode.is_valid(run_mode):
		return false
	draft.run_mode = run_mode
	draft_changed.emit(draft)
	return true


func open_profiles() -> void:
	_transition_to(SelectionStep.Value.PROFILE)


func choose_character(character_id: StringName) -> bool:
	if current_step != SelectionStep.Value.CHARACTER or character_id.is_empty():
		return false
	if draft.character_id != character_id:
		draft.weapon_id = &""
	draft.character_id = character_id
	draft_changed.emit(draft)
	_transition_to(SelectionStep.Value.WEAPON)
	return true


func choose_weapon(weapon_id: StringName) -> bool:
	if (
		current_step != SelectionStep.Value.WEAPON
		or draft.character_id.is_empty()
		or weapon_id.is_empty()
	):
		return false
	draft.weapon_id = weapon_id
	draft_changed.emit(draft)
	_transition_to(SelectionStep.Value.DIFFICULTY)
	return true


func choose_difficulty(level: int, highest_unlocked: int) -> RunLaunchRequest:
	if (
		current_step != SelectionStep.Value.DIFFICULTY
		or draft.character_id.is_empty()
		or draft.weapon_id.is_empty()
		or level < 1
		or level > mini(5, highest_unlocked)
	):
		return null
	draft.difficulty = level
	draft_changed.emit(draft)
	var request := RunLaunchRequest.from_draft(draft)
	run_requested.emit(request)
	return request


func go_back() -> bool:
	if _history.is_empty():
		return false
	current_step = _history.pop_back()
	step_changed.emit(current_step)
	return true


func reset_to_title() -> void:
	_history.clear()
	current_step = SelectionStep.Value.TITLE
	draft = SelectionDraft.new()
	step_changed.emit(current_step)
	draft_changed.emit(draft)


func _transition_to(next_step: int) -> void:
	if current_step != next_step:
		_history.append(current_step)
		current_step = next_step
		step_changed.emit(current_step)
