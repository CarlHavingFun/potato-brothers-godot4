class_name RunDirector
extends RefCounted


signal phase_changed(previous_phase: int, next_phase: int)

var run_state: RunState


func _init(state: RunState = null) -> void:
	run_state = state if state != null else RunState.new()


func transition_to(next_phase: int) -> bool:
	if run_state == null or not RunPhase.is_valid(next_phase):
		return false
	if run_state.phase == next_phase:
		return true
	var previous_phase := run_state.phase
	if not run_state.try_transition(next_phase):
		return false
	phase_changed.emit(previous_phase, next_phase)
	return true
