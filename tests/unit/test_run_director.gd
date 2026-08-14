extends GdUnitTestSuite


const RUN_DIRECTOR_PATH := "res://core/directors/run_director.gd"


func test_run_director_enforces_the_complete_between_wave_sequence() -> void:
	assert_bool(ResourceLoader.exists(RUN_DIRECTOR_PATH)).is_true()
	if not ResourceLoader.exists(RUN_DIRECTOR_PATH):
		return
	var director: RefCounted = load(RUN_DIRECTOR_PATH).new(RunState.new(11))

	assert_bool(director.call("transition_to", RunPhase.COMBAT)).is_true()
	assert_bool(director.call("transition_to", RunPhase.UPGRADE)).is_true()
	assert_bool(director.call("transition_to", RunPhase.CHEST)).is_true()
	assert_bool(director.call("transition_to", RunPhase.SHOP)).is_true()
	assert_bool(director.call("transition_to", RunPhase.COMBAT)).is_true()
	assert_int(director.get("run_state").phase).is_equal(RunPhase.COMBAT)


func test_run_director_rejects_transitions_after_a_terminal_phase() -> void:
	assert_bool(ResourceLoader.exists(RUN_DIRECTOR_PATH)).is_true()
	if not ResourceLoader.exists(RUN_DIRECTOR_PATH):
		return
	var director: RefCounted = load(RUN_DIRECTOR_PATH).new(RunState.new(12))
	director.call("transition_to", RunPhase.COMBAT)
	director.call("transition_to", RunPhase.VICTORY)

	assert_bool(director.call("transition_to", RunPhase.COMBAT)).is_false()
	assert_int(director.get("run_state").phase).is_equal(RunPhase.VICTORY)
