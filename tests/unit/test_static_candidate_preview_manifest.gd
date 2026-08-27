extends GdUnitTestSuite


const MANIFEST_PATH := "res://game/content/assets/gogobro_static_candidate_preview_v1.json"
const EXPECTED_COUNTS := {
	"weapon": 10,
	"item": 28,
	"upgrade": 5,
	"world": 11,
	"ui_brand": 7,
}


func test_candidate_preview_covers_all_planned_noncharacter_units_without_shipping_claims() -> void:
	assert_bool(FileAccess.file_exists(MANIFEST_PATH)).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var manifest := parsed as Dictionary
	assert_str(String(manifest.get("schema_version", ""))).is_equal("gogobro-static-candidate-preview-v1")
	assert_str(String(manifest.get("kind", ""))).is_equal("development_candidate_preview_only")
	assert_bool(bool(manifest.get("enabled_in_shipping", true))).is_false()
	assert_bool(bool(manifest.get("human_approval_implied", true))).is_false()
	assert_bool(bool(manifest.get("character_assets_included", true))).is_false()
	assert_int(int(manifest.get("expected_unit_count", -1))).is_equal(61)
	var category_counts := manifest.get("category_counts", {}) as Dictionary
	for category: String in EXPECTED_COUNTS:
		assert_int(int(category_counts.get(category, -1))).is_equal(int(EXPECTED_COUNTS[category]))

	var units := manifest.get("units", []) as Array
	assert_int(units.size()).is_equal(61)
	var ids: Dictionary = {}
	for unit_variant: Variant in units:
		assert_bool(unit_variant is Dictionary).is_true()
		var unit := unit_variant as Dictionary
		var asset_id := String(unit.get("asset_id", ""))
		assert_bool(not asset_id.is_empty()).is_true()
		assert_bool(not ids.has(asset_id)).is_true()
		ids[asset_id] = true
		assert_str(asset_id).is_not_equal("service_carbine")
		assert_str(String(unit.get("approval_status", ""))).is_equal("candidate_preview_only")
		assert_str(String(unit.get("texture_filter", ""))).is_equal("nearest")
		assert_bool(bool(unit.get("mipmaps", true))).is_false()
		var resource_path := String(unit.get("resource_path", ""))
		assert_bool(resource_path.begins_with("res://game/assets/gogobro_static_preview/")).is_true()
		assert_bool(FileAccess.file_exists(resource_path)).is_true()
		var pixel_size := unit.get("pixel_size", []) as Array
		var pivot := unit.get("pivot_px", []) as Array
		assert_int(pixel_size.size()).is_equal(2)
		assert_int(pivot.size()).is_equal(2)
		assert_bool(int(pivot[0]) >= 0 and int(pivot[0]) < int(pixel_size[0])).is_true()
		assert_bool(int(pivot[1]) >= 0 and int(pivot[1]) < int(pixel_size[1])).is_true()
		if String(unit.get("category", "")) == "weapon":
			var muzzle := (unit.get("anchors_px", {}) as Dictionary).get("muzzle", []) as Array
			assert_int(muzzle.size()).is_equal(2)
			assert_bool(int(muzzle[0]) >= int(pivot[0])).is_true()
