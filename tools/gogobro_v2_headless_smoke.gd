extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var registry := GogoContentRegistry.new()
	var snapshot := registry.build_snapshot(ValidationContentFactory.create_packs())
	if not _require(snapshot != null, "content snapshot"):
		_finish()
		return
	_require(not snapshot.all(&"character").is_empty(), "character content")
	_require(not snapshot.all(&"weapon").is_empty(), "weapon content")
	_require(not snapshot.all(&"enemy").is_empty(), "enemy content")
	_require(not snapshot.all(&"item").is_empty(), "item content")
	_require(snapshot.all(&"upgrade").size() >= 4, "upgrade choice content")
	if not failures.is_empty():
		_finish()
		return
	var config := SessionConfig.new()
	config.seed = 424242
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.MELEE_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	if not _require(session.start(config, snapshot) == OK, "session start"):
		_finish()
		return
	var total_waves := session.run_state.total_waves
	var zone := snapshot.definition(config.zone_id, &"zone") as GogoZoneDefinition
	if not _require(zone != null and zone.wave_ids.size() == total_waves, "authored zone wave count"):
		_finish()
		return
	var build := PlayerBuildService.new()
	var shop := ShopRuntimeService.new()
	var purchases := 0
	for expected_wave in range(1, total_waves + 1):
		if not _require(session.run_state.current_wave == expected_wave, "wave order"):
			_finish()
			return
		session.finish_wave()
		while session.run_state.pending_upgrade_count > 0:
			var upgrade := snapshot.all(&"upgrade")[0] as GogoUpgradeDefinition
			if not _require(build.apply_upgrade(session, session.run_state.player(), upgrade.content_id) == OK, "upgrade application"):
				_finish()
				return
			session.run_state.pending_upgrade_count -= 1
		if session.run_state.phase == &"upgrade":
			if not _require(session.transition(&"shop") == OK, "upgrade to shop"):
				_finish()
				return
		shop.open_shop(session)
		session.run_state.player().add_materials(10000)
		for offer_index in shop.offers.size():
			if shop.offers[offer_index] != null and shop.buy(session, offer_index) == OK:
				purchases += 1
				break
		if expected_wave < total_waves:
			if not _require(session.continue_after_shop(), "wave continuation"):
				_finish()
				return
		else:
			if not _require(session.is_final_shop(), "final shop boundary") \
				or not _require(session.finish_normal_run(), "normal victory settlement"):
				_finish()
				return
	_require(purchases > 0, "at least one shop purchase")
	_require(session.run_state.ended and session.run_state.won, "victory settlement")
	if not _require(session.prepare_checkpoint() == OK, "schema3 checkpoint preparation"):
		_finish()
		return
	var serialized := session.run_state.to_dictionary()
	_require(serialized.schema_version == 3 and typeof(serialized.rng_state) == TYPE_INT,
		"schema3 RNG wire")
	var round_trip := GogoRunState.from_dictionary(serialized, snapshot)
	_require(round_trip != null and round_trip.current_wave == total_waves and round_trip.won, "run-state round trip")
	_require(round_trip != null and round_trip.rng_state == session.rng.state, "RNG state round trip")
	if failures.is_empty():
		print("GOGOBRO_V2_SMOKE_OK waves=%d packs=%d" % [total_waves, snapshot.pack_ids.size()])
	_finish()


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	failures.append(label)
	push_error("GOGOBRO_V2_SMOKE_FAILED: " + label)
	return false


func _finish() -> void:
	print("GOGOBRO_V2_SMOKE_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
