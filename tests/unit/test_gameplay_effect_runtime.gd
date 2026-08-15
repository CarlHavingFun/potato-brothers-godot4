extends GdUnitTestSuite


func test_effects_execute_by_priority_then_stable_id() -> void:
	var runtime := GameplayEffectRuntime.new(7)
	runtime.register_effect(_effect(&"effect/zeta", 5, GameplayEvent.Type.HIT))
	runtime.register_effect(_effect(&"effect/alpha", 5, GameplayEvent.Type.HIT))
	runtime.register_effect(_effect(&"effect/urgent", -10, GameplayEvent.Type.HIT))

	var result := runtime.dispatch(GameplayEventContext.new(GameplayEvent.Type.HIT))

	assert_array(result.applied_effect_ids).contains_exactly([
		&"effect/urgent", &"effect/alpha", &"effect/zeta",
	])


func test_tag_condition_and_stat_operation_build_a_typed_result() -> void:
	var runtime := GameplayEffectRuntime.new(11)
	var effect := _effect(&"effect/burning_power", 0, GameplayEvent.Type.CRITICAL_HIT)
	effect.conditions.append(EffectConditionDef.event_has_tag(&"elemental/fire"))
	effect.operations.append(EffectOperationDef.add_stat(StatId.DAMAGE, 4.0))
	runtime.register_effect(effect)
	var missing_tag := GameplayEventContext.new(GameplayEvent.Type.CRITICAL_HIT)
	var matching := GameplayEventContext.new(GameplayEvent.Type.CRITICAL_HIT)
	matching.tags.append(&"elemental/fire")

	assert_float(runtime.dispatch(missing_tag).stat_changes.get(StatId.DAMAGE, 0.0)).is_zero()
	assert_float(runtime.dispatch(matching).stat_changes.get(StatId.DAMAGE, 0.0)).is_equal(4.0)


func test_recursive_events_stop_at_the_root_recursion_limit() -> void:
	var runtime := GameplayEffectRuntime.new(23, 3)
	var effect := _effect(&"effect/echo", 0, GameplayEvent.Type.HIT)
	effect.operations.append(EffectOperationDef.emit_event(GameplayEvent.Type.HIT))
	runtime.register_effect(effect)

	var result := runtime.dispatch(GameplayEventContext.new(GameplayEvent.Type.HIT))

	assert_int(result.processed_event_count).is_equal(4)
	assert_bool(result.recursion_blocked).is_true()


func test_combat_operations_cover_projectile_status_area_summon_and_building_commands() -> void:
	var runtime := GameplayEffectRuntime.new(31)
	var effect := _effect(&"effect/toolkit", 0, GameplayEvent.Type.KILLED)
	effect.operations.assign([
		EffectOperationDef.extra_damage(12.0),
		EffectOperationDef.apply_status(&"burn", 3.0, 2),
		EffectOperationDef.add_pierce(2),
		EffectOperationDef.add_bounce(1),
		EffectOperationDef.explosion(96.0, 0.75),
		EffectOperationDef.chain(3, 180.0),
		EffectOperationDef.spawn_projectile(&"projectile/ember", 2),
		EffectOperationDef.summon(&"summon/drone", 1),
		EffectOperationDef.build(&"building/turret", 1),
	])
	runtime.register_effect(effect)

	var result := runtime.dispatch(GameplayEventContext.new(GameplayEvent.Type.KILLED))

	assert_float(result.extra_damage).is_equal(12.0)
	assert_int(result.pierce).is_equal(2)
	assert_int(result.bounce).is_equal(1)
	assert_int(result.status_commands.size()).is_equal(1)
	assert_int(result.area_commands.size()).is_equal(2)
	assert_int(result.projectile_commands.size()).is_equal(1)
	assert_int(result.summon_commands.size()).is_equal(1)
	assert_int(result.building_commands.size()).is_equal(1)


func test_status_immunity_and_source_attribution_are_preserved() -> void:
	var target: Unit = auto_free(Unit.new())
	var source: Node2D = auto_free(Node2D.new())
	target.status_immunities = [&"slow"]

	target.apply_effect_status({"status_id": "slow", "duration": 2.0, "stacks": 1}, source)
	assert_int(target.effect_status_stacks(&"slow")).is_zero()
	target.apply_effect_status({"status_id": "burn", "duration": 2.0, "stacks": 2}, source)

	assert_int(target.effect_status_stacks(&"burn")).is_equal(2)
	assert_object(target.status_source(&"burn")).is_same(source)
	target.record_damage_source(source)
	assert_object(target.kill_credit_source(null)).is_same(source)


func _effect(effect_id: StringName, priority: int, trigger: int) -> EffectDef:
	var result := EffectDef.new()
	result.effect_id = effect_id
	result.priority = priority
	result.trigger_events.append(trigger)
	return result
