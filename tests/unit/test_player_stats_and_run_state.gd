extends GdUnitTestSuite


func test_stat_ids_are_stable_and_complete() -> void:
	assert_int(StatId.size()).is_equal(16)
	assert_str(StatId.key(StatId.MAX_HEALTH)).is_equal("max_health")
	assert_int(StatId.from_key("attack_speed")).is_equal(StatId.ATTACK_SPEED)
	assert_int(StatId.from_key("missing_stat")).is_equal(-1)
	assert_int(AimMode.AUTO_TARGET).is_equal(0)
	assert_int(AimMode.MANUAL_MOUSE).is_equal(1)
	assert_bool(AimMode.is_valid(AimMode.MANUAL_MOUSE)).is_true()
	assert_bool(AimMode.is_valid(99)).is_false()


func test_player_stats_copies_do_not_share_runtime_values() -> void:
	var source := PlayerStats.new({
		StatId.MAX_HEALTH: 20.0,
		StatId.ARMOR: 3.0,
	})
	var first_run := source.copy()
	var second_run := source.copy()

	first_run.add_stat(StatId.MAX_HEALTH, 5.0)
	first_run.set_stat(StatId.ARMOR, 9.0)

	assert_float(first_run.get_stat(StatId.MAX_HEALTH)).is_equal(25.0)
	assert_float(second_run.get_stat(StatId.MAX_HEALTH)).is_equal(20.0)
	assert_float(source.get_stat(StatId.ARMOR)).is_equal(3.0)


func test_player_stats_round_trip_uses_stable_keys() -> void:
	var original := PlayerStats.new({
		StatId.DAMAGE: 12.5,
		StatId.LUCK: 8.0,
	})
	var encoded := original.to_dict()
	var restored := PlayerStats.from_dict(encoded)

	assert_bool(encoded.has("damage")).is_true()
	assert_float(restored.get_stat(StatId.DAMAGE)).is_equal(12.5)
	assert_float(restored.get_stat(StatId.LUCK)).is_equal(8.0)
	assert_float(restored.get_stat(StatId.MELEE_DAMAGE)).is_equal(0.0)


func test_run_state_owns_fresh_stats_and_inventory() -> void:
	var template := PlayerStats.new({StatId.MAX_HEALTH: 15.0})
	var first_run := RunState.new(12345, template)
	var second_run := RunState.new(12345, template)

	first_run.player_stats.add_stat(StatId.MAX_HEALTH, 10.0)
	first_run.inventory.add_weapon(&"axe", 1, 20)

	assert_float(second_run.player_stats.get_stat(StatId.MAX_HEALTH)).is_equal(15.0)
	assert_int(second_run.inventory.weapon_count()).is_zero()
	assert_int(first_run.random_seed).is_equal(12345)
	assert_int(first_run.phase).is_equal(RunPhase.SELECTION)


func test_run_state_rejects_invalid_phase_transition() -> void:
	var run_state := RunState.new(7)

	assert_bool(run_state.try_transition(RunPhase.COMBAT)).is_true()
	assert_bool(run_state.try_transition(RunPhase.CHEST)).is_false()
	assert_int(run_state.phase).is_equal(RunPhase.COMBAT)
	assert_bool(run_state.try_transition(RunPhase.UPGRADE)).is_true()
	assert_bool(run_state.try_transition(RunPhase.SHOP)).is_true()
	assert_bool(run_state.try_transition(RunPhase.COMBAT)).is_true()
	assert_bool(run_state.try_transition(RunPhase.VICTORY)).is_true()
	assert_bool(run_state.try_transition(RunPhase.COMBAT)).is_false()


func test_run_state_round_trip_preserves_core_progress() -> void:
	var original := RunState.new(91)
	original.character_id = &"well_rounded"
	original.difficulty = 3
	original.wave = 6
	original.level = 4
	original.experience = 17
	original.materials = 83
	original.player_health_ratio = 0.42
	original.player_stats.set_stat(StatId.RANGED_DAMAGE, 11.0)
	original.inventory.add_passive(&"coffee", 2)
	original.record_applied_upgrade(&"core:upgrade/ranged_damage/common", StatId.RANGED_DAMAGE, 2.0)
	assert_bool(original.try_transition(RunPhase.COMBAT)).is_true()

	var restored := RunState.from_dict(original.to_dict())

	assert_str(restored.character_id).is_equal("well_rounded")
	assert_int(restored.difficulty).is_equal(3)
	assert_int(restored.wave).is_equal(6)
	assert_int(restored.level).is_equal(4)
	assert_int(restored.experience).is_equal(17)
	assert_int(restored.materials).is_equal(83)
	assert_float(restored.player_health_ratio).is_equal_approx(0.42, 0.001)
	assert_int(restored.phase).is_equal(RunPhase.COMBAT)
	assert_float(restored.player_stats.get_stat(StatId.RANGED_DAMAGE)).is_equal(11.0)
	assert_int(restored.inventory.passive_count(&"coffee")).is_equal(2)
	assert_int(restored.applied_upgrades.size()).is_equal(1)
