extends GdUnitTestSuite


const HARNESS_PATH := "res://core/simulation/run_simulation_harness.gd"


func test_fixed_seed_standard_run_reaches_one_terminal_victory() -> void:
	assert_bool(ResourceLoader.exists(HARNESS_PATH)).is_true()
	if not ResourceLoader.exists(HARNESS_PATH):
		return
	var result: Dictionary = load(HARNESS_PATH).new(Content.catalog, 20260815).simulate(
		20, RunMode.STANDARD, 5
	)
	var run := RunState.from_dict(result.get("checkpoint", {}))

	assert_int(run.highest_wave_reached).is_equal(20)
	assert_bool(run.standard_victory_recorded).is_true()
	assert_int(run.phase).is_equal(RunPhase.VICTORY)
	assert_int(run.boss_kill_count).is_equal(1)
	assert_str(str(result.get("event_hash", ""))).has_length(64)


func test_fixed_seed_endless_runs_reach_30_50_and_100_with_expected_boss_schedule() -> void:
	assert_bool(ResourceLoader.exists(HARNESS_PATH)).is_true()
	if not ResourceLoader.exists(HARNESS_PATH):
		return
	var harness: RefCounted = load(HARNESS_PATH).new(Content.catalog, 20260815)
	var expected_cycles := {30: 2, 50: 6, 100: 16}
	for target_wave: int in [30, 50, 100]:
		var result: Dictionary = harness.call("simulate", target_wave, RunMode.ENDLESS, 5)
		var run := RunState.from_dict(result.get("checkpoint", {}))
		assert_int(run.highest_wave_reached).is_equal(target_wave)
		assert_int(run.endless_cycle).is_equal(expected_cycles[target_wave])
		assert_bool(run.standard_victory_recorded).is_true()
		assert_int(run.phase).is_equal(RunPhase.SHOP)
		assert_bool(_boss_count_at(result, 30) == 1).is_true()
		if target_wave >= 50:
			assert_int(_boss_count_at(result, 50)).is_equal(2)
		assert_str(str(result.get("event_hash", ""))).has_length(64)


func test_same_seed_and_inputs_produce_identical_long_run_hash_and_checkpoint() -> void:
	assert_bool(ResourceLoader.exists(HARNESS_PATH)).is_true()
	if not ResourceLoader.exists(HARNESS_PATH):
		return
	var first: Dictionary = load(HARNESS_PATH).new(Content.catalog, 44017).simulate(
		100, RunMode.ENDLESS, 4
	)
	var second: Dictionary = load(HARNESS_PATH).new(Content.catalog, 44017).simulate(
		100, RunMode.ENDLESS, 4
	)

	assert_str(str(first.get("event_hash", ""))).is_equal(str(second.get("event_hash", "")))
	assert_dict(first.get("checkpoint", {})).is_equal(second.get("checkpoint", {}))


func test_checkpoint_round_trip_preserves_long_run_random_stream_and_summary() -> void:
	assert_bool(ResourceLoader.exists(HARNESS_PATH)).is_true()
	if not ResourceLoader.exists(HARNESS_PATH):
		return
	var result: Dictionary = load(HARNESS_PATH).new(Content.catalog, 987654).simulate(
		50, RunMode.ENDLESS, 3
	)
	var checkpoint: Dictionary = result.get("checkpoint", {})
	var restored := RunState.from_dict(checkpoint)

	assert_dict(restored.to_dict()).is_equal(checkpoint)
	assert_bool(restored.rng_states.has("simulation_wave")).is_true()
	assert_int(restored.boss_kill_count).is_greater_equal(5)
	assert_float(restored.elapsed_seconds).is_greater_equal(20.0 * 30.0)


func _boss_count_at(result: Dictionary, wave_number: int) -> int:
	for record: Dictionary in result.get("boss_waves", []):
		if int(record.get("wave", 0)) == wave_number:
			return (record.get("bosses", []) as Array).size()
	return 0
