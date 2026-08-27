extends GdUnitTestSuite


const CONTENT_PATH := "res://game/content/assets/gogobro_static_preview_content_v1.json"
const TRIGGER_RUNTIME_PATH := "res://game/gameplay/weapons/weapon_trigger_runtime.gd"
const SKYLINE_GRENADE_ID: StringName = &"gogobro.preview:item/skyline_grenade"
const EXPECTED_ARCHETYPES := {
	"warmup_shiv": {
		"content_id": &"weapon.training_blade:weapon/training_blade",
		"name": "蝴蝶刀",
		"mode": GogoWeaponDefinition.Mode.MELEE,
		"damage": 7.0,
		"cooldown": 0.55,
		"range": 92.0,
		"projectile_speed": 620.0,
		"knockback": 46.0,
		"price": 15,
		"impact_kind": &"normal",
	},
	"community_tapper": {
		"content_id": &"gogobro.preview:weapon/community_tapper",
		"name": "爪子刀",
		"mode": GogoWeaponDefinition.Mode.MELEE,
		"damage": 3.0,
		"cooldown": 0.18,
		"range": 88.0,
		"projectile_speed": 650.0,
		"knockback": 10.0,
		"price": 12,
		"impact_kind": &"normal",
	},
	"wood_stock_assault_rifle": {
		"content_id": &"gogobro.preview:weapon/wood_stock_assault_rifle",
		"name": "AK-47",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 8.0,
		"cooldown": 0.34,
		"range": 560.0,
		"projectile_speed": 760.0,
		"knockback": 24.0,
		"price": 22,
		"impact_kind": &"pierce_exit",
	},
	"heavy_bolt_sniper": {
		"content_id": &"gogobro.preview:weapon/heavy_bolt_sniper",
		"name": "AWP",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 30.0,
		"cooldown": 1.45,
		"range": 820.0,
		"projectile_speed": 980.0,
		"knockback": 70.0,
		"price": 34,
		"impact_kind": &"critical",
	},
	"suppressed_carbine": {
		"content_id": &"gogobro.preview:weapon/suppressed_carbine",
		"name": "M4A1-S",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 7.0,
		"cooldown": 0.38,
		"range": 540.0,
		"projectile_speed": 740.0,
		"knockback": 18.0,
		"price": 23,
		"impact_kind": &"normal",
	},
	"suppressed_tactical_pistol": {
		"content_id": &"gogobro.preview:weapon/suppressed_tactical_pistol",
		"name": "USP-S",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 6.0,
		"cooldown": 0.42,
		"range": 470.0,
		"projectile_speed": 700.0,
		"knockback": 16.0,
		"price": 18,
		"impact_kind": &"normal",
	},
	"heavy_hand_cannon": {
		"content_id": &"gogobro.preview:weapon/heavy_hand_cannon",
		"name": "Desert Eagle",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 18.0,
		"cooldown": 0.82,
		"range": 520.0,
		"projectile_speed": 800.0,
		"knockback": 52.0,
		"price": 28,
		"impact_kind": &"normal",
	},
	"service_pistol": {
		"content_id": &"weapon.training_blaster:weapon/training_blaster",
		"name": "Glock-18",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 4.0,
		"cooldown": 0.42,
		"range": 520.0,
		"projectile_speed": 620.0,
		"knockback": 22.0,
		"price": 15,
		"impact_kind": &"normal",
	},
	"box_submachine_gun": {
		"content_id": &"gogobro.preview:weapon/box_submachine_gun",
		"name": "MAC-10",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 4.0,
		"cooldown": 0.16,
		"range": 390.0,
		"projectile_speed": 650.0,
		"knockback": 9.0,
		"price": 17,
		"impact_kind": &"normal",
	},
	"compact_submachine_gun": {
		"content_id": &"gogobro.preview:weapon/compact_submachine_gun",
		"name": "MP9",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 4.5,
		"cooldown": 0.15,
		"range": 370.0,
		"projectile_speed": 660.0,
		"knockback": 9.0,
		"price": 18,
		"impact_kind": &"normal",
	},
	"bullpup_pdw": {
		"content_id": &"gogobro.preview:weapon/bullpup_pdw",
		"name": "P90",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 5.0,
		"cooldown": 0.20,
		"range": 430.0,
		"projectile_speed": 690.0,
		"knockback": 12.0,
		"price": 20,
		"impact_kind": &"normal",
	},
	"folding_stock_submachine_gun": {
		"content_id": &"gogobro.preview:weapon/folding_stock_submachine_gun",
		"name": "UMP-45",
		"mode": GogoWeaponDefinition.Mode.RANGED,
		"damage": 5.5,
		"cooldown": 0.22,
		"range": 450.0,
		"projectile_speed": 700.0,
		"knockback": 14.0,
		"price": 20,
		"impact_kind": &"normal",
	},
}


func test_all_twelve_slots_keep_numbers_and_use_exact_cs_names_modes_and_impacts() -> void:
	var content := _debug_content()
	assert_object(content).is_not_null()
	if content == null:
		return
	assert_int(content.all(&"weapon").size()).is_equal(12)
	for asset_id: String in EXPECTED_ARCHETYPES:
		var expected := EXPECTED_ARCHETYPES[asset_id] as Dictionary
		var weapon := content.definition(expected.content_id, &"weapon") as GogoWeaponDefinition
		assert_object(weapon).is_not_null()
		if weapon == null:
			continue
		assert_str(String(weapon.icon_asset_id)).is_equal(asset_id)
		assert_str(weapon.display_name).is_equal(String(expected.name))
		assert_int(weapon.mode).is_equal(int(expected.mode))
		assert_float(weapon.damage).is_equal_approx(float(expected.damage), 0.0001)
		assert_float(weapon.cooldown_seconds).is_equal_approx(float(expected.cooldown), 0.0001)
		assert_float(weapon.attack_range).is_equal_approx(float(expected.range), 0.0001)
		assert_float(weapon.projectile_speed).is_equal_approx(
			float(expected.projectile_speed),
			0.0001
		)
		assert_float(weapon.knockback).is_equal_approx(float(expected.knockback), 0.0001)
		assert_int(weapon.price).is_equal(int(expected.price))
		assert_int(weapon.projectile_count).is_equal(1)
		assert_float(weapon.spread_degrees).is_equal_approx(0.0, 0.0001)
		assert_str(String(weapon.impact_kind)).is_equal(String(expected.impact_kind))


func test_preview_weapon_rows_declare_modes_and_factory_rejects_invalid_mode() -> void:
	var parsed := JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH)) as Dictionary
	var rows := parsed.get("weapons", []) as Array
	assert_int(rows.size()).is_equal(10)
	for raw_variant: Variant in rows:
		var raw := raw_variant as Dictionary
		assert_bool(raw.has("mode")).is_true()
		assert_bool(["melee", "ranged"].has(String(raw.get("mode", "")))).is_true()

	var invalid := (rows[0] as Dictionary).duplicate(true)
	invalid["mode"] = "thrown"
	assert_object(GogoStaticPreviewContentFactory._weapon_definition(invalid)).is_null()


func test_skyline_grenade_emits_only_on_each_seventh_owned_ranged_attack() -> void:
	var runtime := _trigger_runtime()
	if runtime == null:
		return
	var owned_items: Array[StringName] = [SKYLINE_GRENADE_ID]
	for _index in 6:
		assert_array(runtime.call("note_ranged_attack", 101, owned_items)).is_empty()
	var events := runtime.call(
		"note_ranged_attack",
		101,
		owned_items
	) as Array
	assert_int(events.size()).is_equal(1)
	assert_str(String(events[0].impact_kind)).is_equal("explosion")
	assert_float(float(events[0].damage_scale)).is_equal_approx(1.0, 0.0001)
	assert_str(String(events[0].source_item_id)).is_equal(String(SKYLINE_GRENADE_ID))
	for _index in 6:
		assert_array(runtime.call("note_ranged_attack", 101, owned_items)).is_empty()
	assert_int((runtime.call("note_ranged_attack", 101, owned_items) as Array).size()).is_equal(1)


func test_skyline_counter_is_per_weapon_instance_ignores_unowned_calls_and_resets() -> void:
	var runtime := _trigger_runtime()
	if runtime == null:
		return
	var owned_items: Array[StringName] = [SKYLINE_GRENADE_ID]
	var no_items: Array[StringName] = []
	for _index in 9:
		assert_array(runtime.call("note_ranged_attack", 101, no_items)).is_empty()
	for _index in 6:
		assert_array(runtime.call("note_ranged_attack", 101, owned_items)).is_empty()
		assert_array(runtime.call("note_ranged_attack", 202, owned_items)).is_empty()
	assert_int((runtime.call("note_ranged_attack", 101, owned_items) as Array).size()).is_equal(1)
	assert_int((runtime.call("note_ranged_attack", 202, owned_items) as Array).size()).is_equal(1)
	runtime.call("reset")
	for _index in 6:
		assert_array(runtime.call("note_ranged_attack", 101, owned_items)).is_empty()


func test_duplicate_weapon_definitions_keep_independent_skyline_counters() -> void:
	var runtime := _trigger_runtime()
	if runtime == null:
		return
	var owned_items: Array[StringName] = [SKYLINE_GRENADE_ID]
	for _index in 6:
		assert_array(runtime.call("note_ranged_attack", 301, owned_items)).is_empty()
	assert_array(runtime.call("note_ranged_attack", 302, owned_items)).is_empty()
	assert_int((runtime.call("note_ranged_attack", 301, owned_items) as Array).size()).is_equal(1)
	for _index in 5:
		assert_array(runtime.call("note_ranged_attack", 302, owned_items)).is_empty()
	assert_int((runtime.call("note_ranged_attack", 302, owned_items) as Array).size()).is_equal(1)


func _debug_content() -> ContentSnapshot:
	return GogoContentRegistry.new().build_snapshot(ValidationContentFactory.create_packs())


func _trigger_runtime() -> RefCounted:
	var script := load(TRIGGER_RUNTIME_PATH) as Script
	assert_object(script).is_not_null()
	if script == null:
		return null
	var runtime := script.new() as RefCounted
	assert_object(runtime).is_not_null()
	assert_bool(runtime.has_method("note_ranged_attack")).is_true()
	assert_bool(runtime.has_method("reset")).is_true()
	return runtime
