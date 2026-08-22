extends SceneTree


func _initialize() -> void:
	var registry := GogoContentRegistry.new()
	var snapshot := registry.build_snapshot(ValidationContentFactory.create_packs())
	_require(snapshot != null, "content snapshot")
	_require(snapshot.all(&"character").size() == 2, "two characters")
	_require(snapshot.all(&"weapon").size() == 2, "two weapons")
	_require(snapshot.all(&"enemy").size() == 3, "three enemies")
	_require(snapshot.all(&"item").size() == 6, "six items")
	_require(snapshot.all(&"upgrade").size() == 6, "six upgrades")
	_require(snapshot.all(&"wave").size() == 5, "five waves")
	var config := SessionConfig.new()
	config.seed = 424242
	config.character_id = ValidationContentFactory.CHARACTER_ID
	config.starting_weapon_id = ValidationContentFactory.MELEE_ID
	config.difficulty_id = ValidationContentFactory.DIFFICULTY_ID
	config.zone_id = ValidationContentFactory.ZONE_ID
	var session := GameSession.new()
	_require(session.start(config, snapshot) == OK, "session start")
	var build := PlayerBuildService.new()
	var shop := ShopRuntimeService.new()
	for expected_wave in range(1, 6):
		_require(session.run_state.current_wave == expected_wave, "wave order")
		session.finish_wave()
		while session.run_state.pending_upgrade_count > 0:
			var upgrade := snapshot.all(&"upgrade")[0] as GogoUpgradeDefinition
			_require(build.apply_upgrade(session, session.run_state.player(), upgrade.content_id) == OK, "upgrade application")
			session.run_state.pending_upgrade_count -= 1
		if session.run_state.phase == &"upgrade":
			_require(session.transition(&"shop") == OK, "upgrade to shop")
		shop.open_shop(session)
		session.run_state.player().add_materials(100)
		if not shop.offers.is_empty():
			_require(shop.buy(session, 0) == OK, "shop purchase")
		var continues := session.continue_after_shop()
		_require(continues == (expected_wave < 5), "wave continuation")
	_require(session.run_state.ended and session.run_state.won, "victory settlement")
	var round_trip := GogoRunState.from_dictionary(session.run_state.to_dictionary())
	_require(round_trip != null and round_trip.current_wave == 5 and round_trip.won, "run-state round trip")
	print("GOGOBRO_V2_SMOKE_OK waves=5 packs=%d" % snapshot.pack_ids.size())
	quit(0)


func _require(condition: bool, label: String) -> void:
	if condition:
		return
	push_error("GOGOBRO_V2_SMOKE_FAILED: " + label)
	quit(1)
