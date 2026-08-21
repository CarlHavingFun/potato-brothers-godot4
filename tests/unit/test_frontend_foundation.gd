extends GdUnitTestSuite


func test_selection_draft_round_trip_preserves_launch_choices() -> void:
	var draft := SelectionDraft.new()
	draft.profile_id = 2
	draft.character_id = &"core:character/brawler"
	draft.weapon_id = &"core:weapon/punch"
	draft.difficulty = 4
	draft.aim_mode = AimMode.MANUAL_MOUSE
	draft.random_seed = 982451653

	var restored := SelectionDraft.from_dict(draft.to_dict())

	assert_int(restored.profile_id).is_equal(2)
	assert_str(restored.character_id).is_equal("core:character/brawler")
	assert_str(restored.weapon_id).is_equal("core:weapon/punch")
	assert_int(restored.difficulty).is_equal(4)
	assert_int(restored.aim_mode).is_equal(AimMode.MANUAL_MOUSE)
	assert_int(restored.random_seed).is_equal(982451653)


func test_selection_flow_advances_one_decision_at_a_time_and_builds_request() -> void:
	var flow := SelectionFlow.new()

	assert_int(flow.current_step).is_equal(SelectionStep.Value.TITLE)
	assert_bool(flow.begin_new_run(2, 12345, AimMode.AUTO_TARGET)).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.CHARACTER)
	assert_bool(flow.choose_character(&"character.one")).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.WEAPON)
	assert_bool(flow.choose_weapon(&"weapon.one")).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.DIFFICULTY)

	var request := flow.choose_difficulty(3, 4)

	assert_object(request).is_not_null()
	assert_bool(request.is_valid()).is_true()
	assert_int(request.profile_id).is_equal(2)
	assert_str(request.character_id).is_equal("character.one")
	assert_str(request.weapon_id).is_equal("weapon.one")
	assert_int(request.difficulty).is_equal(3)
	assert_int(request.random_seed).is_equal(12345)


func test_selection_flow_back_stack_keeps_completed_choices() -> void:
	var flow := SelectionFlow.new()
	flow.begin_new_run(1, 77, AimMode.AUTO_TARGET)
	flow.choose_character(&"character.one")
	flow.choose_weapon(&"weapon.one")

	assert_bool(flow.go_back()).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.WEAPON)
	assert_str(flow.draft.character_id).is_equal("character.one")
	assert_str(flow.draft.weapon_id).is_equal("weapon.one")
	assert_bool(flow.go_back()).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.CHARACTER)
	assert_str(flow.draft.character_id).is_equal("character.one")


func test_profile_page_has_an_explicit_return_to_title() -> void:
	var flow := SelectionFlow.new()
	flow.open_profiles()

	assert_int(flow.current_step).is_equal(SelectionStep.Value.PROFILE)
	assert_bool(flow.go_back()).is_true()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.TITLE)
	assert_bool(flow.go_back()).is_false()


func test_selection_flow_rejects_missing_choices_and_locked_difficulty() -> void:
	var flow := SelectionFlow.new()
	flow.begin_new_run(1, 1, AimMode.AUTO_TARGET)

	assert_bool(flow.choose_character(&"")).is_false()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.CHARACTER)
	assert_bool(flow.choose_weapon(&"weapon.one")).is_false()
	flow.choose_character(&"character.one")
	assert_bool(flow.choose_weapon(&"")).is_false()
	flow.choose_weapon(&"weapon.one")
	assert_object(flow.choose_difficulty(5, 3)).is_null()
	assert_int(flow.current_step).is_equal(SelectionStep.Value.DIFFICULTY)
