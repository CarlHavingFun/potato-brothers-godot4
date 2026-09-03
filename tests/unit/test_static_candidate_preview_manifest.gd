extends GdUnitTestSuite


const MANIFEST_PATH := "res://game/content/assets/gogobro_static_candidate_preview_v1.json"
const REDRAW_CONTRACT_PATH := "res://tools/assets/gogobro_static_redraw_contract_v1.json"
const BUILDER_PATH := "res://tools/assets/build_static_candidate_preview.py"
const COVERAGE_EVIDENCE_PATH := "res://tools/assets/gogobro_static_candidate_preview_coverage_v1.json"
const EXPECTED_COUNTS := {
	"weapon": 12,
	"item": 30,
	"upgrade": 5,
	"world": 11,
	"ui_brand": 7,
}
const EXPECTED_WEAPON_IDS := [
	"warmup_shiv",
	"community_tapper",
	"wood_stock_assault_rifle",
	"heavy_bolt_sniper",
	"suppressed_carbine",
	"suppressed_tactical_pistol",
	"heavy_hand_cannon",
	"service_pistol",
	"box_submachine_gun",
	"compact_submachine_gun",
	"bullpup_pdw",
	"folding_stock_submachine_gun",
]
const EXPECTED_WEAPON_SOURCE_PATHS := {
	"warmup_shiv": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/warmup_shiv/candidate-003/curated/warmup-shiv-butterfly-knife-64x64.png",
	"community_tapper": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/community_tapper/candidate-002/curated/community-tapper-karambit-64x64.png",
	"wood_stock_assault_rifle": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/wood_stock_assault_rifle/candidate-004/curated/wood-stock-assault-rifle-ak-world-96x64.png",
	"heavy_bolt_sniper": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/heavy_bolt_sniper/candidate-002/curated/heavy-bolt-sniper-awp-world-96x64.png",
	"suppressed_carbine": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/suppressed_carbine/candidate-003/curated/suppressed-carbine-m4a1s-world-96x64.png",
	"suppressed_tactical_pistol": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/suppressed_tactical_pistol/candidate-002/curated/suppressed-tactical-pistol-usps-96x64.png",
	"heavy_hand_cannon": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/heavy_hand_cannon/candidate-003/curated/heavy-hand-cannon-desert-eagle-96x64.png",
	"service_pistol": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/service_pistol/candidate-002/curated/service-pistol-glock18-96x64.png",
	"box_submachine_gun": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/box_submachine_gun/candidate-002/curated/box-submachine-gun-mac10-96x64.png",
	"compact_submachine_gun": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/compact_submachine_gun/candidate-002/curated/compact-submachine-gun-mp9-96x64.png",
	"bullpup_pdw": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/bullpup_pdw/candidate-002/curated/bullpup-pdw-p90-96x64.png",
	"folding_stock_submachine_gun": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/folding_stock_submachine_gun/candidate-002/curated/folding-stock-submachine-gun-ump45-96x64.png",
}
const EXPECTED_REMEDIATED_SOURCE_PATHS := {
	"warmup_shiv": "GOGOBRO_ASSET_INBOX/02_static_assets/weapons/warmup_shiv/candidate-003/curated/warmup-shiv-butterfly-knife-64x64.png",
	"pre_aim_drills": "GOGOBRO_ASSET_INBOX/02_static_assets/upgrades/pre_aim_drills/candidate-003/curated/pre_aim_drills-icon-64x64.png",
	"smoke_shell_helmet": "GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-005/curated/smoke_shell_helmet-icon-64x64.png",
	"combat_hud_shell": "GOGOBRO_ASSET_INBOX/02_static_assets/ui_brand/combat_hud_shell/candidate-002/curated/combat_hud_shell-logical-320x180.png",
	"zone_thumbnail": "GOGOBRO_ASSET_INBOX/02_static_assets/ui_brand/zone_thumbnail/candidate-002/curated/zone_thumbnail-256x144.png",
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
	assert_int(int(manifest.get("expected_unit_count", -1))).is_equal(65)
	var category_counts := manifest.get("category_counts", {}) as Dictionary
	for category: String in EXPECTED_COUNTS:
		assert_int(int(category_counts.get(category, -1))).is_equal(int(EXPECTED_COUNTS[category]))

	var units := manifest.get("units", []) as Array
	assert_int(units.size()).is_equal(65)
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
			var anchor_name := "contact" if asset_id in ["warmup_shiv", "community_tapper"] else "muzzle"
			var anchor := (unit.get("anchors_px", {}) as Dictionary).get(anchor_name, []) as Array
			assert_int(anchor.size()).is_equal(2)
			if anchor.size() != 2:
				continue
			assert_bool(int(anchor[0]) >= int(pivot[0])).is_true()


func test_preview_manifest_binds_the_exact_twelve_weapon_candidates_to_contract_geometry() -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var contract := JSON.parse_string(FileAccess.get_file_as_string(REDRAW_CONTRACT_PATH)) as Dictionary
	var contract_weapons := contract.get("weapons", {}) as Dictionary
	var weapon_units: Array[Dictionary] = []
	for unit_value: Variant in manifest.get("units", []) as Array:
		var unit := unit_value as Dictionary
		if String(unit.get("category", "")) == "weapon":
			weapon_units.append(unit)
	var weapon_ids: Array[String] = []
	for unit: Dictionary in weapon_units:
		weapon_ids.append(String(unit.get("asset_id", "")))
	assert_array(weapon_ids).is_equal(EXPECTED_WEAPON_IDS)
	for unit: Dictionary in weapon_units:
		var asset_id := String(unit.get("asset_id", ""))
		var record := contract_weapons.get(asset_id, {}) as Dictionary
		assert_str(String(unit.get("resource_path", ""))).is_equal(
			"res://game/assets/gogobro_static_preview/weapons/%s.png" % asset_id
		)
		assert_str(String(unit.get("source_candidate_path", ""))).is_equal(
			String(EXPECTED_WEAPON_SOURCE_PATHS[asset_id])
		)
		assert_str(FileAccess.get_sha256(String(unit.resource_path)).to_upper()).is_equal(
			String(unit.get("sha256", "")).to_upper()
		)
		_assert_integer_pair_equals(unit.get("pixel_size"), int(record.width), int(record.height))
		_assert_integer_pair_equals(unit.get("display_size_px"), int(record.width), int(record.height))
		_assert_integer_pair_equals(
			unit.get("pivot_px"), int((record.pivot_px as Array)[0]), int((record.pivot_px as Array)[1])
		)
		var expected_anchors := record.get("anchor_px", {}) as Dictionary
		var actual_anchors := unit.get("anchors_px", {}) as Dictionary
		assert_array(actual_anchors.keys()).contains_exactly_in_any_order(expected_anchors.keys())
		for anchor_name: String in expected_anchors:
			var point := expected_anchors[anchor_name] as Array
			_assert_integer_pair_equals(actual_anchors.get(anchor_name), int(point[0]), int(point[1]))
		assert_array(unit.get("preview_alias_asset_ids", []) as Array).is_empty()


func test_multi_part_preview_units_declare_every_runtime_selector_as_a_real_png() -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var units_by_id: Dictionary = {}
	for unit_variant: Variant in manifest.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		units_by_id[String(unit.get("asset_id", ""))] = unit
	var expected_selectors := {
		"community_server_decor_pack": [
			"decor_variant_01", "decor_variant_02", "decor_variant_03",
			"decor_variant_04", "decor_variant_05", "decor_variant_06",
		],
		"card_and_rarity_frame_kit": ["common", "uncommon", "rare", "legendary"],
		"four_state_button": ["normal", "hover", "pressed", "disabled"],
	}
	for asset_id: String in expected_selectors:
		var unit := units_by_id.get(asset_id, {}) as Dictionary
		var variants := unit.get("variants", []) as Array
		assert_int(variants.size()).is_equal((expected_selectors[asset_id] as Array).size())
		var selectors: Array[String] = []
		for variant_value: Variant in variants:
			var variant := variant_value as Dictionary
			var selector := String(variant.get("selector", ""))
			selectors.append(selector)
			var resource_path := String(variant.get("resource_path", ""))
			assert_bool(FileAccess.file_exists(resource_path)).is_true()
			assert_str(FileAccess.get_sha256(resource_path).to_upper()).is_equal(
				String(variant.get("sha256", "")).to_upper()
			)
		assert_array(selectors).is_equal(expected_selectors[asset_id])


func test_preview_manifest_never_aliases_any_weapon_identity() -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	for unit_variant: Variant in manifest.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) != "weapon":
			continue
		assert_array(unit.get("preview_alias_asset_ids", []) as Array).is_empty()


func test_remediated_units_bind_only_the_new_preview_candidate_sources() -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var units_by_id: Dictionary = {}
	for unit_variant: Variant in manifest.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		units_by_id[String(unit.get("asset_id", ""))] = unit
	for asset_id: String in EXPECTED_REMEDIATED_SOURCE_PATHS:
		var unit := units_by_id.get(asset_id, {}) as Dictionary
		assert_bool(not unit.is_empty()).is_true()
		assert_str(String(unit.get("source_candidate_path", ""))).is_equal(
			String(EXPECTED_REMEDIATED_SOURCE_PATHS[asset_id])
		)
		assert_str(String(unit.get("approval_status", ""))).is_equal("candidate_preview_only")


func test_repaired_hud_underlay_has_transparent_outer_edge_and_empty_bottom_half() -> void:
	var image := Image.load_from_file(
		"res://game/assets/gogobro_static_preview/ui/combat_hud_shell.png"
	)
	assert_bool(not image.is_empty()).is_true()
	assert_int(image.get_width()).is_equal(320)
	assert_int(image.get_height()).is_equal(180)
	for y in image.get_height():
		for x in image.get_width():
			if x < 3 or y < 3 or x >= image.get_width() - 3 or y >= image.get_height() - 3:
				assert_float(image.get_pixel(x, y).a).is_zero()
	for y in range(image.get_height() / 2, image.get_height()):
		for x in image.get_width():
			assert_float(image.get_pixel(x, y).a).is_zero()


func test_zone_thumbnail_preview_is_a_true_one_to_one_256_by_144_candidate() -> void:
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var unit: Dictionary = {}
	for unit_value: Variant in manifest.get("units", []) as Array:
		var candidate := unit_value as Dictionary
		if String(candidate.get("asset_id", "")) == "zone_thumbnail":
			unit = candidate
			break
	assert_bool(not unit.is_empty()).is_true()
	if unit.is_empty():
		return
	assert_str(String(unit.get("source_candidate_path", ""))).is_equal(
		"GOGOBRO_ASSET_INBOX/02_static_assets/ui_brand/zone_thumbnail/candidate-002/curated/zone_thumbnail-256x144.png"
	)
	_assert_integer_pair_equals(unit.get("pixel_size"), 256, 144)
	_assert_integer_pair_equals(unit.get("display_size_px"), 256, 144)
	_assert_integer_pair_equals(unit.get("pivot_px"), 128, 72)
	var image := Image.load_from_file(String(unit.get("resource_path", "")))
	assert_bool(not image.is_empty()).is_true()
	assert_int(image.get_width()).is_equal(256)
	assert_int(image.get_height()).is_equal(144)


func test_preview_builder_check_is_non_mutating_and_bound_to_fresh_coverage() -> void:
	assert_bool(FileAccess.file_exists(BUILDER_PATH)).is_true()
	assert_bool(FileAccess.file_exists(COVERAGE_EVIDENCE_PATH)).is_true()
	if not FileAccess.file_exists(BUILDER_PATH) or not FileAccess.file_exists(COVERAGE_EVIDENCE_PATH):
		return
	var manifest_before := FileAccess.get_sha256(MANIFEST_PATH).to_upper()
	var output: Array = []
	var exit_code := OS.execute(
		_python_executable(),
		[ProjectSettings.globalize_path(BUILDER_PATH), "--check"],
		output,
		true,
		false
	)
	assert_int(exit_code).is_equal(0)
	assert_str(FileAccess.get_sha256(MANIFEST_PATH).to_upper()).is_equal(manifest_before)
	var manifest := JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	var evidence := JSON.parse_string(
		FileAccess.get_file_as_string(COVERAGE_EVIDENCE_PATH)
	) as Dictionary
	assert_str(String(manifest.get("coverage_report_path", ""))).is_equal(
		COVERAGE_EVIDENCE_PATH
	)
	assert_str(String(manifest.get("coverage_report_sha256", "")).to_upper()).is_equal(
		FileAccess.get_sha256(COVERAGE_EVIDENCE_PATH).to_upper()
	)
	assert_int(int(evidence.get("unit_count", -1))).is_equal(65)
	var evidence_counts := evidence.get("category_counts", {}) as Dictionary
	for category: String in EXPECTED_COUNTS:
		assert_int(int(evidence_counts.get(category, -1))).is_equal(int(EXPECTED_COUNTS[category]))
	assert_int((evidence.get("rows", []) as Array).size()).is_equal(65)


func test_preview_builder_discovers_inbox_beside_a_normal_checkout_root() -> void:
	var script_path := ProjectSettings.globalize_path(BUILDER_PATH).replace("\\", "/")
	var code := (
		"import importlib.util,tempfile;from pathlib import Path;"
		+ "p=r'%s';s=importlib.util.spec_from_file_location('preview_builder',p);"
		+ "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
		+ "t=tempfile.TemporaryDirectory();r=Path(t.name);"
		+ "(r/'GOGOBRO_ASSET_INBOX').mkdir();m.REPO=r;"
		+ "assert m._discover_workspace_root(None)==r;t.cleanup()"
	) % script_path
	var output: Array = []
	var exit_code := OS.execute(_python_executable(), ["-c", code], output, true, false)
	assert_int(exit_code).is_equal(0)


func _assert_integer_pair_equals(value: Variant, expected_x: int, expected_y: int) -> void:
	assert_bool(value is Array).is_true()
	if not value is Array:
		return
	var pair := value as Array
	assert_int(pair.size()).is_equal(2)
	if pair.size() != 2:
		return
	assert_int(int(pair[0])).is_equal(expected_x)
	assert_int(int(pair[1])).is_equal(expected_y)


func _python_executable() -> String:
	var configured := String(ProjectSettings.get_setting("gogobro/tools/python_executable", ""))
	return configured if not configured.is_empty() else "python"
