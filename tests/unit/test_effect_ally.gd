extends GdUnitTestSuite


class ProjectileSink:
	extends RefCounted

	var requests: Array[Dictionary] = []

	func request_projectile(
		origin: Vector2,
		target: Node2D,
		damage: float,
		source: Node2D,
		metadata: Dictionary
	) -> void:
		requests.append({
			"origin": origin,
			"target": target,
			"damage": damage,
			"source": source,
			"metadata": metadata,
		})


func after_test() -> void:
	Global.end_run()


func test_turrets_and_drones_have_distinct_runtime_profiles() -> void:
	Global.begin_run(1001, null, 0)
	Global.current_run.player_stats.set_stat(StatId.ENGINEERING, 20.0)
	var anchor := auto_free(Node2D.new()) as Node2D
	add_child(anchor)
	var turret := auto_free(EffectAlly.new()) as EffectAlly
	var drone := auto_free(EffectAlly.new()) as EffectAlly
	add_child(turret)
	add_child(drone)

	turret.setup(&"building", &"building/test", anchor, 0)
	drone.setup(&"summon", &"summon/test", anchor, 1)

	assert_float(turret.lifetime_remaining).is_equal(-1.0)
	assert_bool(drone.lifetime_remaining > 0.0).is_true()
	assert_bool(turret.attack_range > drone.attack_range).is_true()
	assert_bool(turret.damage > drone.damage).is_true()
	assert_bool(drone.attack_interval < turret.attack_interval).is_true()


func test_effect_ally_uses_projectile_protocol_instead_of_forcing_direct_damage() -> void:
	var ally := auto_free(EffectAlly.new()) as EffectAlly
	var target := auto_free(Node2D.new()) as Node2D
	add_child(ally)
	add_child(target)
	ally.setup(&"building", &"building/test", null, 0)
	var sink := ProjectileSink.new()
	ally.set_projectile_callback(sink.request_projectile)

	assert_bool(ally.request_attack(target)).is_true()
	assert_int(sink.requests.size()).is_equal(1)
	assert_object(sink.requests[0].target).is_same(target)
	assert_str(String(sink.requests[0].metadata.entity_kind)).is_equal("building")
