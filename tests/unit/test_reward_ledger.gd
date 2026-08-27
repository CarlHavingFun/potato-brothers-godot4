extends GdUnitTestSuite


var _reward_signal_count := 0
var _state_signal_count := 0
var _reentrant_result: StringName = &""


func before_test() -> void:
	_reward_signal_count = 0
	_state_signal_count = 0
	_reentrant_result = &""


func test_invalid_reward_requests_are_side_effect_free() -> void:
	var session := GameSession.new()
	assert_str(String(session.commit_reward_once(&"token", GameSession.REWARD_EXPERIENCE, 1, 0))).is_equal(String(GameSession.REWARD_INVALID))
	session = _session_with_players(1)
	var player := session.run_state.players[0]
	session.reward_committed.connect(_on_reward_committed)
	session.state_changed.connect(_on_state_changed)

	assert_str(String(session.commit_reward_once(&"", GameSession.REWARD_EXPERIENCE, 1, 0))).is_equal(String(GameSession.REWARD_INVALID))
	assert_str(String(session.commit_reward_once(&"bad-kind", &"health", 1, 0))).is_equal(String(GameSession.REWARD_INVALID))
	assert_str(String(session.commit_reward_once(&"zero", GameSession.REWARD_EXPERIENCE, 0, 0))).is_equal(String(GameSession.REWARD_INVALID))
	assert_str(String(session.commit_reward_once(&"negative", GameSession.REWARD_SUPPLY, -1, 0))).is_equal(String(GameSession.REWARD_INVALID))
	assert_str(String(session.commit_reward_once(&"bad-player", GameSession.REWARD_SUPPLY, 1, 9))).is_equal(String(GameSession.REWARD_INVALID))
	var duplicate_index_player := SessionPlayerState.new()
	duplicate_index_player.player_index = 0
	session.run_state.players.append(duplicate_index_player)
	assert_str(String(session.commit_reward_once(&"ambiguous-player", GameSession.REWARD_SUPPLY, 1, 0))).is_equal(String(GameSession.REWARD_INVALID))

	assert_int(session.committed_reward_count()).is_equal(0)
	assert_int(player.level).is_equal(1)
	assert_int(player.xp).is_equal(0)
	assert_int(player.materials).is_equal(35)
	assert_int(session.run_state.pending_upgrade_count).is_equal(0)
	assert_int(_reward_signal_count).is_equal(0)
	assert_int(_state_signal_count).is_equal(0)


func test_experience_commit_is_exact_once_multilevel_and_reentrant_safe() -> void:
	var session := _session_with_players(1)
	var player := session.run_state.players[0]
	player.xp_to_next_level = 5
	session.reward_committed.connect(_on_reward_committed_reentrant.bind(session))
	var token: StringName = &"enemy/7/death/1/experience"

	var first := session.commit_reward_once(token, GameSession.REWARD_EXPERIENCE, 73, 0)

	assert_str(String(first)).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(_reentrant_result)).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_int(player.level).is_equal(4)
	assert_int(player.xp).is_equal(0)
	assert_int(session.run_state.pending_upgrade_count).is_equal(3)
	assert_int(session.committed_reward_count()).is_equal(1)
	assert_int(_reward_signal_count).is_equal(1)

	var replay := session.commit_reward_once(token, GameSession.REWARD_EXPERIENCE, 73, 0)
	assert_str(String(replay)).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_int(player.level).is_equal(4)
	assert_int(player.xp).is_equal(0)
	assert_int(session.run_state.pending_upgrade_count).is_equal(3)
	assert_int(_reward_signal_count).is_equal(1)


func test_token_collision_preserves_original_fingerprint_and_reward() -> void:
	var session := _session_with_players(2)
	var player_zero := session.run_state.players[0]
	var player_one := session.run_state.players[1]
	session.reward_committed.connect(_on_reward_committed)
	var token: StringName = &"enemy/8/death/1/supply"

	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_SUPPLY, 10, 0))).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_SUPPLY, 10, 0))).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_SUPPLY, 11, 0))).is_equal(String(GameSession.REWARD_TOKEN_COLLISION))
	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_EXPERIENCE, 10, 0))).is_equal(String(GameSession.REWARD_TOKEN_COLLISION))
	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_SUPPLY, 10, 1))).is_equal(String(GameSession.REWARD_TOKEN_COLLISION))
	assert_str(String(session.commit_reward_once(token, GameSession.REWARD_SUPPLY, 10, 0))).is_equal(String(GameSession.REWARD_DUPLICATE))

	assert_int(player_zero.materials).is_equal(45)
	assert_int(player_one.materials).is_equal(35)
	assert_int(session.committed_reward_count()).is_equal(1)
	assert_int(_reward_signal_count).is_equal(1)


func test_reservation_is_side_effect_free_until_apply_and_reentrant_apply_is_duplicate() -> void:
	var session := _session_with_players(1)
	var player := session.run_state.players[0]
	player.xp_to_next_level = 5
	var reservation := session.reserve_reward_once(
		&"enemy/12/death/1/experience",
		GameSession.REWARD_EXPERIENCE,
		5,
		0
	)
	assert_str(String(reservation.status)).is_equal(String(GameSession.REWARD_RESERVED))
	assert_int(player.level).is_equal(1)
	assert_int(player.xp).is_zero()
	assert_int(session.run_state.pending_upgrade_count).is_zero()
	var reentrant_apply := [GameSession.REWARD_INVALID]
	var on_reward_committed := func(
		token: StringName,
		_kind: StringName,
		_amount: int,
		_player_index: int
	) -> void:
		reentrant_apply[0] = session.apply_reserved_reward(token, int(reservation.reservation_id))
	session.reward_committed.connect(on_reward_committed)

	assert_str(String(session.apply_reserved_reward(
		StringName(reservation.token), int(reservation.reservation_id)
	))).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(reentrant_apply[0])).is_equal(String(GameSession.REWARD_DUPLICATE))
	session.reward_committed.disconnect(on_reward_committed)
	assert_int(player.level).is_equal(2)
	assert_int(player.xp).is_zero()
	assert_int(session.run_state.pending_upgrade_count).is_equal(1)


func test_legacy_immediate_adapter_uses_independent_tokens_across_worlds() -> void:
	var session := _session_with_players(1)
	var player := session.run_state.players[0]
	player.xp_to_next_level = 5
	var first_world := auto_free(CombatWorld.new()) as CombatWorld
	var replacement_world := auto_free(CombatWorld.new()) as CombatWorld
	first_world.session = session
	replacement_world.session = session
	session.reward_committed.connect(_on_reward_committed)

	var first := first_world.commit_enemy_reward_snapshot(21, 1, 5, 3)
	var replay := replacement_world.commit_enemy_reward_snapshot(21, 1, 5, 3)
	var zero_reward := replacement_world.commit_enemy_reward_snapshot(22, 1, 0, 0)
	var distinct_enemy := replacement_world.commit_enemy_reward_snapshot(23, 1, 0, 3)

	assert_str(String(first[GameSession.REWARD_EXPERIENCE])).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(first[GameSession.REWARD_SUPPLY])).is_equal(String(GameSession.REWARD_APPLIED))
	assert_str(String(replay[GameSession.REWARD_EXPERIENCE])).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_str(String(replay[GameSession.REWARD_SUPPLY])).is_equal(String(GameSession.REWARD_DUPLICATE))
	assert_int(zero_reward.size()).is_equal(0)
	assert_str(String(distinct_enemy[GameSession.REWARD_SUPPLY])).is_equal(String(GameSession.REWARD_APPLIED))
	assert_int(player.level).is_equal(2)
	assert_int(player.xp).is_equal(0)
	assert_int(player.materials).is_equal(41)
	assert_int(session.run_state.pending_upgrade_count).is_equal(1)
	assert_int(session.committed_reward_count()).is_equal(3)
	assert_int(_reward_signal_count).is_equal(3)

	var new_session := _session_with_players(1)
	assert_str(String(new_session.commit_reward_once(&"enemy/21/death/1/supply", GameSession.REWARD_SUPPLY, 3, 0))).is_equal(String(GameSession.REWARD_APPLIED))
	assert_int(new_session.run_state.players[0].materials).is_equal(38)


func test_session_start_and_wave_finish_are_single_commit_transitions() -> void:
	var registry := GogoContentRegistry.new()
	var snapshot := registry.build_snapshot(ValidationContentFactory.create_packs())
	var config := SessionConfig.new()
	config.seed = 77
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.RANGED_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()

	assert_int(session.start(config, snapshot)).is_equal(OK)
	session.finish_wave()
	var materials_after_first_finish := session.run_state.players[0].materials
	var pending_after_first_finish := session.run_state.pending_upgrade_count
	session.finish_wave()
	assert_int(session.run_state.players[0].materials).is_equal(materials_after_first_finish)
	assert_int(session.run_state.pending_upgrade_count).is_equal(pending_after_first_finish)
	session.run_state = null
	assert_int(session.start(config, snapshot)).is_equal(ERR_ALREADY_IN_USE)


func _session_with_players(count: int) -> GameSession:
	var session := GameSession.new()
	var run_state := GogoRunState.new()
	for index in count:
		var player := SessionPlayerState.new()
		player.player_index = index
		run_state.players.append(player)
	session.run_state = run_state
	return session


func _on_reward_committed(_token: StringName, _kind: StringName, _amount: int, _player_index: int) -> void:
	_reward_signal_count += 1


func _on_reward_committed_reentrant(
	token: StringName,
	kind: StringName,
	amount: int,
	player_index: int,
	session: GameSession
) -> void:
	_reward_signal_count += 1
	_reentrant_result = session.commit_reward_once(token, kind, amount, player_index)


func _on_state_changed() -> void:
	_state_signal_count += 1
