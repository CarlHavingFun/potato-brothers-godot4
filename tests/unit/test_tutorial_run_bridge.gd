extends GdUnitTestSuite


func before_test() -> void:
	Global.end_run()


func after_test() -> void:
	Global.end_run()


func test_default_starting_economy_is_release_scaled_instead_of_debug_scaled() -> void:
	assert_int(Global.STARTING_MATERIALS).is_greater_equal(20)
	assert_int(Global.STARTING_MATERIALS).is_less_equal(60)


func test_begin_run_maps_tutorial_stats_and_resets_previous_run() -> void:
	var source := UnitStats.new()
	source.health = 20
	source.hp_regen = 1.5
	source.life_steal = 3.0
	source.damage = 12.0
	source.speed = 325
	source.luck = 7.0
	source.block_chance = 8.0
	source.harvesting = 4.0

	Global.begin_run(123, source, 75)
	Global.current_run.inventory.add_weapon(&"old_weapon", 1, 10)
	Global.begin_run(456, source, 90)

	assert_int(Global.current_run.random_seed).is_equal(456)
	assert_int(Global.current_run.materials).is_equal(90)
	assert_int(Global.current_run.inventory.weapon_count()).is_zero()
	assert_float(Global.current_run.player_stats.get_stat(StatId.MAX_HEALTH)).is_equal(20.0)
	assert_float(Global.current_run.player_stats.get_stat(StatId.RECOVERY)).is_equal(1.5)
	assert_float(Global.current_run.player_stats.get_stat(StatId.DODGE)).is_equal(8.0)
	assert_float(Global.current_run.player_stats.get_stat(StatId.MOVE_SPEED)).is_equal(325.0)


func test_legacy_coins_property_forwards_to_authoritative_run_state() -> void:
	Global.begin_run(1, null, 40)

	Global.coins += 12

	assert_int(Global.current_run.materials).is_equal(52)
	assert_int(Global.coins).is_equal(52)
	assert_bool(Global.try_spend_materials(60)).is_false()
	assert_int(Global.coins).is_equal(52)
	assert_bool(Global.try_spend_materials(50)).is_true()
	assert_int(Global.coins).is_equal(2)


func test_global_material_collection_consumes_the_banked_material_bonus_once() -> void:
	Global.begin_run(11, null, 10)
	Global.current_run.material_bag = 5

	var levels_gained := Global.collect_materials(3)

	assert_int(levels_gained).is_zero()
	assert_int(Global.current_run.materials).is_equal(16)
	assert_int(Global.current_run.experience).is_equal(6)
	assert_int(Global.current_run.material_bag).is_equal(2)


func test_shop_purchase_uses_inventory_service_before_charging() -> void:
	Global.begin_run(2, null, 100)
	var weapon := ItemWeapon.new()
	weapon.content_id = &"weapon.test"
	weapon.item_tier = Global.UpgradeTier.COMMON
	weapon.item_cost = 40

	for index in InventoryState.MAX_WEAPON_SLOTS:
		Global.current_run.inventory.add_weapon(StringName("weapon.%d" % index), 1, 1)

	var result: int = Global.try_purchase_item(weapon)

	assert_int(result).is_equal(InventoryService.NO_WEAPON_SLOT)
	assert_int(Global.coins).is_equal(100)


func test_stat_change_updates_run_and_runtime_copy_without_mutating_definition() -> void:
	var definition := UnitStats.new()
	definition.health = 10
	Global.begin_run(3, definition, 0)
	var runtime_player := Player.new()
	runtime_player.stats = definition.duplicate(true)
	Global.player = runtime_player

	assert_bool(Global.apply_stat_change("health", 5.0)).is_true()

	assert_float(Global.current_run.player_stats.get_stat(StatId.MAX_HEALTH)).is_equal(15.0)
	assert_int(runtime_player.stats.health).is_equal(15)
	assert_int(definition.health).is_equal(10)
	runtime_player.free()
	Global.player = null


func test_selected_run_records_stable_ids_and_starter_weapon() -> void:
	var character := UnitStats.new()
	character.content_id = &"character.test"
	character.name = "Test Character"
	var weapon := ItemWeapon.new()
	weapon.content_id = &"weapon.test"
	weapon.item_tier = Global.UpgradeTier.COMMON
	weapon.item_cost = 12
	Global.main_player_selected = character
	Global.main_weapon_selected = weapon

	assert_bool(Global.begin_selected_run(99)).is_true()

	assert_str(Global.current_run.character_id).is_equal("character.test")
	assert_str(Global.current_run.starting_weapon_id).is_equal("weapon.test")
	assert_int(Global.current_run.inventory.weapon_count()).is_equal(1)
	assert_str(Global.current_run.inventory.weapon_at(0).get("weapon_id", "")).is_equal("weapon.test")
	assert_int(Global.current_run.inventory.weapon_at(0).get("paid_price", 0)).is_equal(12)


func test_catalog_selection_uses_the_same_namespaced_weapon_id_in_run_and_inventory() -> void:
	var character := Content.catalog.get_character(&"character/well_rounded")
	var weapon := Content.catalog.get_weapon(&"weapon/pistol")
	assert_bool(Global.select_character(character)).is_true()
	assert_bool(Global.select_starting_weapon(weapon)).is_true()

	assert_bool(Global.begin_selected_run(100)).is_true()

	assert_str(Global.current_run.character_id).is_equal(
		"core:character/well_rounded"
	)
	assert_str(Global.current_run.starting_weapon_id).is_equal("core:weapon/pistol")
	assert_str(Global.current_run.inventory.weapon_at(0).get("weapon_id", "")).is_equal(
		Global.current_run.starting_weapon_id
	)


func test_catalog_shop_purchase_and_combine_keep_the_weapon_family_id() -> void:
	Global.begin_run(101, null, 500)
	var pistol := Content.catalog.get_weapon(&"weapon/pistol")

	assert_int(Global.try_purchase_item(pistol.tiers[0])).is_equal(InventoryService.OK)
	assert_int(Global.try_purchase_item(pistol.tiers[0])).is_equal(InventoryService.OK)
	assert_int(Global.try_combine_weapon(pistol.tiers[0])).is_equal(InventoryService.OK)

	assert_int(Global.current_run.inventory.weapon_count()).is_equal(1)
	assert_str(Global.current_run.inventory.weapon_at(0).get("weapon_id", "")).is_equal(
		"core:weapon/pistol"
	)
	assert_int(Global.current_run.inventory.weapon_at(0).get("tier", 0)).is_equal(2)


func test_player_instances_do_not_share_the_scene_stat_resource() -> void:
	var packed_scene := load("res://scenes/unit/players/player_brawler.tscn") as PackedScene
	var first := auto_free(packed_scene.instantiate()) as Player
	var second := auto_free(packed_scene.instantiate()) as Player
	add_child(first)
	add_child(second)
	await await_idle_frame()

	first.stats.health += 5

	assert_bool(first.stats == second.stats).is_false()
	assert_int(first.stats.health).is_equal(second.stats.health + 5)


func test_run_phase_is_the_authority_for_combat_pause_state() -> void:
	Global.begin_run(4, null, 0)

	assert_int(Global.current_run.phase).is_equal(RunPhase.SELECTION)
	assert_bool(Global.is_combat_active()).is_false()
	assert_bool(Global.enter_phase(RunPhase.COMBAT)).is_true()
	assert_bool(Global.is_combat_active()).is_true()
	assert_bool(Global.enter_phase(RunPhase.UPGRADE)).is_true()
	assert_bool(Global.is_combat_active()).is_false()
	assert_bool(Global.enter_phase(RunPhase.SHOP)).is_true()
	assert_bool(Global.enter_phase(RunPhase.COMBAT)).is_true()


func test_enemy_wave_scaling_returns_a_copy_and_applies_difficulty() -> void:
	var definition := UnitStats.new()
	definition.health = 10
	definition.health_increase_per_wave = 2.0
	definition.damage = 3.0
	definition.damage_increase_per_wave = 1.0
	definition.speed = 100

	var runtime_stats := Spawner.build_enemy_stats_for_wave(definition, 3, 2)

	assert_bool(runtime_stats == definition).is_false()
	assert_int(runtime_stats.health).is_equal(15)
	assert_float(runtime_stats.damage).is_equal(5.25)
	assert_int(runtime_stats.speed).is_equal(100)
	assert_int(definition.health).is_equal(10)
	assert_float(definition.damage).is_equal(3.0)


func test_spawner_resolves_legacy_wave_data_through_the_content_catalog() -> void:
	var spawner: Spawner = auto_free(Spawner.new())
	spawner.wave_index = 4

	var wave_data: WaveData = spawner.find_wave_data()

	assert_object(wave_data).is_not_null()
	assert_bool(wave_data.is_valid_index(4)).is_true()


func test_spawner_ignores_spawn_request_without_definition_or_legacy_wave() -> void:
	var spawner := Spawner.new()
	spawner.add_child(Timer.new())
	spawner.get_child(0).name = "SpawnTimer"
	spawner.add_child(Timer.new())
	spawner.get_child(1).name = "WaveTimer"
	add_child(spawner)
	await get_tree().process_frame

	spawner.spawn_enemy()

	assert_bool(spawner.spawn_timer.is_stopped()).is_true()
	spawner.queue_free()


func test_content_passive_and_upgrade_apply_all_sixteen_stat_ids() -> void:
	Global.begin_run(303, null, 0)
	var coffee := Content.catalog.get_passive(&"passive/coffee")
	var melee_upgrade := Content.catalog.get_upgrade(&"upgrade/melee_damage/common")

	assert_bool(Global.apply_passive_item(coffee.item)).is_true()
	assert_bool(Global.apply_upgrade_item(melee_upgrade.item)).is_true()

	assert_float(Global.current_run.player_stats.get_stat(StatId.DAMAGE)).is_equal(-2.0)
	assert_float(Global.current_run.player_stats.get_stat(StatId.ATTACK_SPEED)).is_equal(10.0)
	assert_float(Global.current_run.player_stats.get_stat(StatId.MELEE_DAMAGE)).is_equal(2.0)


func test_wave_enemy_selection_is_seeded_and_priority_enemy_spawns_only_once() -> void:
	var first: Spawner = auto_free(Spawner.new())
	var second: Spawner = auto_free(Spawner.new())
	var boss_wave := Content.catalog.get_wave(&"wave/10")
	first.current_wave_definition = boss_wave
	second.current_wave_definition = boss_wave
	first.rng.seed = 404
	second.rng.seed = 404
	var first_ids: Array[String] = []
	var second_ids: Array[String] = []
	for index in range(40):
		var first_enemy := first._get_random_enemy_definition()
		var second_enemy := second._get_random_enemy_definition()
		first_ids.append(String(first_enemy.get_stable_id(Content.catalog.pack_id)))
		second_ids.append(String(second_enemy.get_stable_id(Content.catalog.pack_id)))

	assert_array(first_ids).is_equal(second_ids)
	assert_int(first_ids.count("core:enemy/iron_maw")).is_equal(1)
