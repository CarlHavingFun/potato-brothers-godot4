extends GdUnitTestSuite


const TEST_SAVE_PATH := "user://tests/core_parity_regressions/save_v2.json"


class EffectSource:
	extends Node2D

	var pierce := 0
	var bounce := 0
	var projectile_count := 0

	func apply_attack_effects(result: EffectResult) -> void:
		pierce += result.pierce
		bounce += result.bounce

	func spawn_effect_projectiles(commands: Array[Dictionary]) -> void:
		for command: Dictionary in commands:
			projectile_count += int(command.get("count", 0))


class EffectArenaSink:
	extends Node2D

	var summons := 0
	var buildings := 0

	func spawn_effect_entities(kind: StringName, commands: Array[Dictionary], _context: GameplayEventContext) -> void:
		for command: Dictionary in commands:
			if kind == &"summon":
				summons += int(command.get("count", 0))
			elif kind == &"building":
				buildings += int(command.get("count", 0))


var _original_provider: SaveProvider


func before_test() -> void:
	_original_provider = Global.save_provider
	Global.save_provider = LocalSaveProvider.new(TEST_SAVE_PATH)
	Global.end_run()


func after_test() -> void:
	Global.end_run()
	Global.save_provider = _original_provider
	for suffix: String in ["", ".tmp", ".bak"]:
		var path := TEST_SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_service_random_streams_continue_after_checkpoint_restore() -> void:
	Global.begin_run(44017, null, 50)
	Global.current_run.character_id = &"test:character"
	Global.current_run.starting_weapon_id = &"test:weapon"
	Global.current_run.phase = RunPhase.COMBAT
	Global.shop_service.rng.randi()
	Global.reward_service.rng.randi()
	Global.combat_resolver.rng.randi()
	Global.gameplay_effects.rng.randi()
	assert_int(Global.save_progress(true)).is_equal(OK)
	var expected := {
		"shop": Global.shop_service.rng.randi(),
		"reward": Global.reward_service.rng.randi(),
		"combat": Global.combat_resolver.rng.randi(),
		"effects": Global.gameplay_effects.rng.randi(),
	}
	var payload := Global.save_provider.load_slot()
	var restored := RunState.from_dict(payload.get("run_state", {}))

	assert_bool(Global.resume_run_state(restored)).is_true()
	assert_int(Global.shop_service.rng.randi()).is_equal(expected.shop)
	assert_int(Global.reward_service.rng.randi()).is_equal(expected.reward)
	assert_int(Global.combat_resolver.rng.randi()).is_equal(expected.combat)
	assert_int(Global.gameplay_effects.rng.randi()).is_equal(expected.effects)


func test_shop_purchase_consumes_the_selected_duplicate_slot_only() -> void:
	var service := ShopService.new(77)
	var run := RunState.new(77)
	run.materials = 500
	var item := Content.catalog.get_shop_items()[0]
	service.store_offers(run, [item, item], Content.catalog)
	service.set_slot_locked(run, 0, true)

	var result: Variant = service.call("try_purchase_offer", run, 1, Content.catalog)

	assert_int(int(result)).is_equal(InventoryService.OK)
	assert_bool(run.shop_slots[0].locked).is_true()
	assert_bool(run.shop_slots[0].is_empty()).is_false()
	assert_bool(run.shop_slots[1].is_empty()).is_true()


func test_purchased_shop_slot_survives_checkpoint_without_refilling_or_overwriting_neighbors() -> void:
	var service := ShopService.new(78)
	var run := RunState.new(78)
	run.materials = 500
	var items := Content.catalog.get_shop_items().slice(0, 4)
	service.store_offers(run, items, Content.catalog)
	var neighbor_ids := [run.shop_slots[0].offer_id, run.shop_slots[2].offer_id, run.shop_slots[3].offer_id]
	assert_int(service.try_purchase_offer(run, 1, Content.catalog)).is_equal(InventoryService.OK)
	var restored := RunState.from_dict(run.to_dict())

	service.store_offers(restored, [Content.catalog.get_shop_items()[4]], Content.catalog)

	assert_bool(restored.shop_slots[1].purchased).is_true()
	assert_object(service.resolve_slot_offer(restored, 1, Content.catalog)).is_null()
	assert_array([
		restored.shop_slots[0].offer_id,
		restored.shop_slots[2].offer_id,
		restored.shop_slots[3].offer_id,
	]).is_equal(neighbor_ids)


func test_duplicate_effect_registration_scales_to_the_effect_stack_cap() -> void:
	var runtime := GameplayEffectRuntime.new(19)
	var effect := EffectDef.new()
	effect.effect_id = &"effect/test/stacked"
	effect.max_stacks = 3
	effect.trigger_events = [GameplayEvent.Type.HIT]
	effect.operations = [EffectOperationDef.extra_damage(2.0)]

	assert_bool(runtime.register_effect(effect)).is_true()
	assert_bool(runtime.register_effect(effect)).is_true()
	assert_bool(runtime.register_effect(effect)).is_true()
	assert_bool(runtime.register_effect(effect)).is_false()
	var result := runtime.dispatch(GameplayEventContext.new(GameplayEvent.Type.HIT))

	assert_float(result.extra_damage).is_equal(6.0)
	assert_int(result.applied_effect_ids.size()).is_equal(3)


func test_purchased_weapon_registers_its_runtime_effect() -> void:
	Global.begin_run(991, null, 500)
	var definition := Content.catalog.get_weapon(&"weapon/railbow")
	assert_object(definition).is_not_null()
	if definition == null:
		return
	var item := definition.tiers[0]

	assert_int(Global.try_purchase_item(item)).is_equal(InventoryService.OK)
	var result := Global.dispatch_gameplay_event(
		GameplayEvent.Type.ATTACKED,
		{"base_damage": item.stats.damage},
		definition.tags
	)

	assert_int(result.pierce).is_equal(1)
	assert_int(Global.dispatch_gameplay_event(
		GameplayEvent.Type.ATTACKED,
		{"base_damage": item.stats.damage},
		[&"ranged"] as Array[StringName]
	).pierce).is_equal(0)


func test_effect_commands_reach_status_attack_and_spawn_consumers() -> void:
	Global.begin_run(1203, null, 0)
	var source: EffectSource = auto_free(EffectSource.new()) as EffectSource
	add_child(source)
	var arena_sink: EffectArenaSink = auto_free(EffectArenaSink.new()) as EffectArenaSink
	add_child(arena_sink)
	arena_sink.add_to_group("effect_runtime/arena")
	var target_definition: EnemyDef = Content.catalog.get_enemy(&"enemy/swarm_mite")
	var target: Enemy = auto_free(target_definition.scene.instantiate() as Enemy) as Enemy
	target.definition = target_definition
	add_child(target)
	var effect := EffectDef.new()
	effect.effect_id = &"effect/test/consumers"
	effect.trigger_events = [GameplayEvent.Type.HIT]
	effect.operations.assign([
		EffectOperationDef.burn(2.0, 2.5, 2),
		EffectOperationDef.add_pierce(2),
		EffectOperationDef.add_bounce(1),
		EffectOperationDef.spawn_projectile(&"projectile/test", 3),
		EffectOperationDef.summon(&"summon/test", 1),
		EffectOperationDef.build(&"building/test", 2),
	])
	Global.gameplay_effects.register_effect(effect)

	Global.dispatch_gameplay_event(GameplayEvent.Type.HIT, {"damage": 10.0}, [], source, target)

	assert_bool(target.has_method("effect_status_stacks")).is_true()
	if target.has_method("effect_status_stacks"):
		assert_int(target.call("effect_status_stacks", &"burn")).is_equal(2)
	assert_int(source.pierce).is_equal(2)
	assert_int(source.bounce).is_equal(1)
	assert_int(source.projectile_count).is_equal(3)
	assert_int(arena_sink.summons).is_equal(1)
	assert_int(arena_sink.buildings).is_equal(2)


func test_explosion_damages_nearby_enemies_and_projectile_consumes_bounce_then_pierce() -> void:
	Global.begin_run(1307, null, 0)
	var definition: EnemyDef = Content.catalog.get_enemy(&"enemy/swarm_mite")
	var primary: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
	var secondary: Enemy = auto_free(definition.scene.instantiate() as Enemy) as Enemy
	primary.definition = definition
	secondary.definition = definition
	add_child(primary)
	add_child(secondary)
	primary.global_position = Vector2.ZERO
	secondary.global_position = Vector2(50.0, 0.0)
	var secondary_health := secondary.health_component.current_health
	var explosion := EffectDef.new()
	explosion.effect_id = &"effect/test/explosion"
	explosion.trigger_events = [GameplayEvent.Type.HIT]
	explosion.operations = [EffectOperationDef.explosion(100.0, 0.5)]
	Global.gameplay_effects.register_effect(explosion)

	Global.dispatch_gameplay_event(GameplayEvent.Type.HIT, {"damage": 10.0}, [], null, primary)

	assert_float(secondary.health_component.current_health).is_equal(secondary_health - 5.0)
	var projectile := auto_free(Projectile.new()) as Projectile
	add_child(projectile)
	projectile.velocity = Vector2(100.0, 0.0)
	projectile.bounce_remaining = 1
	projectile.pierce_remaining = 1
	projectile._on_hitbox_component_on_hit_hurtbox(primary.get_node("HurtboxComponent"))
	assert_int(projectile.bounce_remaining).is_equal(0)
	assert_bool(projectile.is_queued_for_deletion()).is_false()
	projectile._on_hitbox_component_on_hit_hurtbox(secondary.get_node("HurtboxComponent"))
	assert_int(projectile.pierce_remaining).is_equal(0)
	assert_bool(projectile.is_queued_for_deletion()).is_false()
	projectile._on_hitbox_component_on_hit_hurtbox(secondary.get_node("HurtboxComponent"))
	assert_bool(projectile.is_queued_for_deletion()).is_true()
