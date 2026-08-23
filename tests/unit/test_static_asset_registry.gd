extends GdUnitTestSuite


const Registry = preload("res://game/content/assets/static_asset_registry.gd")
const CANONICAL_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"


func test_canonical_registry_loads_all_seventy_six_planned_approval_units() -> void:
	var result := Registry.load_registry(CANONICAL_PATH)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	var registry := result.get("registry", {}) as Dictionary
	assert_int(errors.size()).is_equal(0)
	assert_int((registry.get("units", []) as Array).size()).is_equal(76)
	var category_counts := registry.get("category_counts", {}) as Dictionary
	assert_int(int(category_counts.get("character_creature", 0))).is_equal(5)
	assert_int(int(category_counts.get("weapon", 0))).is_equal(13)
	assert_int(int(category_counts.get("projectile_hit_kit", 0))).is_equal(1)
	assert_int(int(category_counts.get("item", 0))).is_equal(30)
	assert_int(int(category_counts.get("upgrade", 0))).is_equal(6)
	assert_int(int(category_counts.get("world", 0))).is_equal(11)
	assert_int(int(category_counts.get("ui_brand", 0))).is_equal(10)


func test_loader_rejects_each_required_malformed_temporary_fixture() -> void:
	var missing_unit := _canonical_registry()
	(missing_unit["units"] as Array).pop_back()
	_assert_fixture_error(missing_unit, "expected 76 units")

	var duplicate_asset_id := _canonical_registry()
	var duplicate_units := duplicate_asset_id["units"] as Array
	(duplicate_units[1] as Dictionary)["asset_id"] = (duplicate_units[0] as Dictionary)["asset_id"]
	_assert_fixture_error(duplicate_asset_id, "duplicate asset_id")

	var missing_english_copy := _canonical_registry()
	var missing_english_localization := (missing_english_copy["units"] as Array)[0].get("localization", {}) as Dictionary
	(missing_english_localization["en"] as Dictionary)["name"] = ""
	_assert_fixture_error(missing_english_copy, "missing English copy")

	var invalid_status := _canonical_registry()
	((invalid_status["units"] as Array)[0] as Dictionary)["approval_status"] = "rendered"
	_assert_fixture_error(invalid_status, "unknown approval_status")

	var missing_item_effects := _canonical_registry()
	(_first_unit_in_category(missing_item_effects, "item") as Dictionary).erase("effects")
	_assert_fixture_error(missing_item_effects, "item missing effects")

	var handwritten_effect_copy := _canonical_registry()
	var english_copy := ((_first_unit_in_category(handwritten_effect_copy, "item") as Dictionary)["localization"] as Dictionary)["en"] as Dictionary
	english_copy["description"] = "+3 max health"
	_assert_fixture_error(handwritten_effect_copy, "handwritten numeric effect text")


func test_loader_accepts_only_the_canonical_approval_states() -> void:
	for approval_status in ["planned", "generated", "review", "approved", "integrated", "qa_passed"]:
		var accepted := _canonical_registry()
		((accepted["units"] as Array)[0] as Dictionary)["approval_status"] = approval_status
		_assert_fixture_has_no_errors(accepted)
	for approval_status in ["draft", "rejected"]:
		var rejected := _canonical_registry()
		((rejected["units"] as Array)[0] as Dictionary)["approval_status"] = approval_status
		_assert_fixture_error(rejected, "unknown approval_status")


func test_loader_requires_bilingual_descriptions_and_category_flavor_without_numeric_prose() -> void:
	var missing_world_description := _canonical_registry()
	var world_copy := ((_first_unit_in_category(missing_world_description, "world") as Dictionary)["localization"] as Dictionary)["en"] as Dictionary
	world_copy.erase("description")
	_assert_fixture_error(missing_world_description, "missing English description")

	var missing_weapon_flavor := _canonical_registry()
	var weapon_copy := ((_first_unit_in_category(missing_weapon_flavor, "weapon") as Dictionary)["localization"] as Dictionary)["zh_CN"] as Dictionary
	weapon_copy["flavor"] = ""
	_assert_fixture_error(missing_weapon_flavor, "missing Chinese flavor")

	var numeric_flavor := _canonical_registry()
	var character_copy := ((_first_unit_in_category(numeric_flavor, "character_creature") as Dictionary)["localization"] as Dictionary)["en"] as Dictionary
	character_copy["flavor"] = "Wins with 3 precise moves."
	_assert_fixture_error(numeric_flavor, "handwritten numeric effect text")


func _canonical_registry() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANONICAL_PATH))
	return JSON.parse_string(JSON.stringify(parsed)) as Dictionary


func _assert_fixture_error(registry: Dictionary, expected_error: String) -> void:
	var fixture_path := "user://static_asset_registry_fixture_%s.json" % Time.get_ticks_usec()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(registry))
	file.close()
	var result := Registry.load_registry(fixture_path)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	assert_str("\n".join(errors)).contains(expected_error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


func _assert_fixture_has_no_errors(registry: Dictionary) -> void:
	var fixture_path := "user://static_asset_registry_fixture_%s.json" % Time.get_ticks_usec()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(registry))
	file.close()
	var result := Registry.load_registry(fixture_path)
	assert_int((result.get("errors", PackedStringArray()) as PackedStringArray).size()).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


func _first_unit_in_category(registry: Dictionary, category: String) -> Dictionary:
	for unit in registry.get("units", []) as Array:
		if (unit as Dictionary).get("category", "") == category:
			return unit as Dictionary
	return {}
