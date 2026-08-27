extends GdUnitTestSuite


const CANDIDATE_MANIFEST_PATH := "res://game/content/assets/gogobro_static_candidate_preview_v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const SHIPPING_MANIFEST_PATH := "res://game/content/assets/gogobro_static_runtime_bindings_v1.json"
const REDRAW_CONTRACT_PATH := "res://tools/assets/gogobro_static_redraw_contract_v1.json"
const MECHANICS_BASELINE_PATH := (
	"res://tests/fixtures/gogobro_static_item_mechanics_baseline_v1.json"
)
const SHIPPING_MANIFEST_WITHOUT_REGISTRY_HASH_SHA256 := (
	"8089E5561E3DD57F74D3DEFE016B6245F21746BC5F6B3C52AAA6C74974A4D858"
)

const REDRAW_BINDINGS := {
	"ballistic_liner": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/ballistic_liner/candidate-002/curated/ballistic_liner-icon-64x64.png",
		"sha256": "CB30303A895ED72F7344C848918DF1384B519D8EA289710D068FE36D478E2FB9",
	},
	"one_missed_shot": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/one_missed_shot/candidate-002/curated/one_missed_shot-icon-64x64.png",
		"sha256": "2DDC9347849ED2DDC2B68551EC4CFEA199ECC4D2F5ED60A31CF736197A3CE2C6",
	},
	"skyline_grenade": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/skyline_grenade/candidate-002/curated/skyline_grenade-icon-64x64.png",
		"sha256": "25B7B1DA885DC77EA9E7F011249C21103AAFFD03B4848D86B71C14FD5F5C6AE3",
	},
	"silent_step_insoles": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/silent_step_insoles/candidate-002/curated/silent_step_insoles-icon-64x64.png",
		"sha256": "53BA7432ECE1CD9CA743E0C26369613C9E794CC4AA73E7D866BE32EF7422E44F",
	},
	"crosshair_shim": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/crosshair_shim/candidate-002/curated/crosshair_shim-icon-64x64.png",
		"sha256": "D10569BAD4A310E9508CEEE260635A28A84EFA71963E43867004C1138C838033",
	},
	"corner_lucky_claw": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/corner_lucky_claw/candidate-002/curated/corner_lucky_claw-icon-64x64.png",
		"sha256": "6963913CC090C0559A73F432F4A4A4B640B4A17D72BA62BD8024B9F0A817A7FA",
	},
	"falling_sniper_charm": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/falling_sniper_charm/candidate-002/curated/falling_sniper_charm-icon-64x64.png",
		"sha256": "FCFBF8DE84DCDD1F0430D90F369C99DFCCF3FEFBE6835B0F9377B819F9328139",
	},
	"lineup_chalk": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/lineup_chalk/candidate-002/curated/lineup_chalk-icon-64x64.png",
		"sha256": "49F1ED348DB91CF8899EEEB7F879B6F8515B74149BB9E4C41D9B3B7FFB985CF3",
	},
	"airshot_wing_charm": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/airshot_wing_charm/candidate-002/curated/airshot_wing_charm-icon-64x64.png",
		"sha256": "1A4A3DF851D09A6917C30C9F962EE15D5B58DD1F797D6902ED28B88F1C2576F9",
	},
	"post_match_analysis_desk": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/post_match_analysis_desk/candidate-002/curated/post_match_analysis_desk-icon-64x64.png",
		"sha256": "5F0224AB4FADE7D23596588ADA0562EFC31B3FAC2C547FDD4C3626D1413E5ED3",
	},
	"halftime_tactics_board": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/halftime_tactics_board/candidate-002/curated/halftime_tactics_board-icon-64x64.png",
		"sha256": "AD35681A4DA489B8FDAFD9B1C5881D2AC90A9EF58A3BB0E73459949A465A2D34",
	},
	"sneaky_site_mask": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/sneaky_site_mask/candidate-002/curated/sneaky-site-mask-balaclava-64x64.png",
		"sha256": "83E525BFFA0392C5A0D54D4B64C4C9CF256CE8F4E926D6E3DFEFABA00E348396",
	},
	"supply_radar": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/supply_radar/candidate-002/curated/supply-radar-handheld-scanner-64x64.png",
		"sha256": "E133B0F308274F32B9B39A2F5A820B1172CD0F9B6CCD67465ACCE9460F7A062F",
	},
	"trade_guard": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/trade_guard/candidate-003/curated/trade-guard-open-bracer-64x64.png",
		"sha256": "E598C863FBFCA693F2DAFD87CAB6D606F039328B83341FBD3DDB9D407D4B43AF",
	},
	"post_match_mic": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/post_match_mic/candidate-002/curated/post-match-mic-broadcast-64x64.png",
		"sha256": "ADCB0FEA64DF15FB38820975BEBCCF968F626D6C406E893B2DCA8413D45A1FCA",
	},
	"mouse_lift_pad": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/mouse_lift_pad/candidate-002/curated/mouse-lift-pad-raised-64x64.png",
		"sha256": "D85DAC7C2CD6B199C8C98493E93AF33EEB5B2EBC6843698C5427B64EF6098AEC",
	},
	"tactical_med_patch": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/tactical_med_patch/candidate-003/curated/tactical_med_patch-icon-64x64.png",
		"sha256": "B4B156E01D7BBC962E850556D3DE6243ABA0DD2A5610E4B80515D321337F90AA",
	},
	"smoke_shell_helmet": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-005/curated/smoke_shell_helmet-icon-64x64.png",
		"sha256": "AC3ACB1118DEFA21907EE7323BC4D07B8DEE53FCCCABDD94CD26DA73686680DE",
	},
	"force_buy_runners": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/force_buy_runners/candidate-002/curated/force_buy_runners-icon-64x64.png",
		"sha256": "F59A6E6B6AD452078B0679AB24FD0EAC0D18D25B5038226A2751421D275FE403",
	},
	"eco_round_coin_pouch": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/eco_round_coin_pouch/candidate-002/curated/eco_round_coin_pouch-icon-64x64.png",
		"sha256": "1D8B20433D661999EF707CEDE2C11A6C3BC2633C7A94A17FB2D4C0E57280B65E",
	},
	"entry_fragger_dumbbell": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/entry_fragger_dumbbell/candidate-002/curated/entry_fragger_dumbbell-icon-64x64.png",
		"sha256": "25A4A184CF8E87FB3729E25A4E62D5B29C7C74E7A03648F68161294DE3156769",
	},
	"save_time_watch": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/save_time_watch/candidate-002/curated/save_time_watch-icon-64x64.png",
		"sha256": "9182EAF1DE72DA9330D3CCA2DCCC89A77E92FF31B7E5F87F3B3E48D1FDEB3B5D",
	},
	"hand_cannon_ace_coin": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/hand_cannon_ace_coin/candidate-002/curated/hand-cannon-ace-coin-64x64.png",
		"sha256": "08B4BDAC9087D7BA147BCCCB41AF14B501A10937ADFE30560819E6B442868040",
	},
	"arena_chant_cassette": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/arena_chant_cassette/candidate-002/curated/arena-chant-cassette-64x64.png",
		"sha256": "0F17BC99B79D927EC10BA4117EB2ABF2C8009C72797089C0A8665AD9434E9B78",
	},
	"site_hold_bandana": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/site_hold_bandana/candidate-002/curated/site-hold-bandana-64x64.png",
		"sha256": "F3FE51E77A32A8CA931F3C5F714359B776905E8031F536E0605BD96B4FE75368",
	},
	"clutch_stopwatch": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/clutch_stopwatch/candidate-002/curated/clutch-stopwatch-64x64.png",
		"sha256": "6249013AE28FF6C19E8A618E026DA05BA85F93FE194444CE8284AF3E6105445D",
	},
	"three_beat_magazine": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/three_beat_magazine/candidate-002/curated/three-beat-magazine-64x64.png",
		"sha256": "FAD6426E87A9BF3D8C03B6F1274794403E20861ED25BD025150C06E084009527",
	},
}

const PRESERVED_PREVIEW_BINDINGS := {
	"rebound_fire_bottle": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/rebound_fire_bottle/candidate-001/curated/rebound-fire-bottle-icon-64.png",
		"sha256": "27882A8B4B921D5B5E946704059E97974A7700F3B586C8695D0F8526C0ABD75D",
	},
	"scorched_defuse_pliers": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/scorched_defuse_pliers/candidate-001/curated/scorched_defuse_pliers-icon-64x64.png",
		"sha256": "8AC0697B27311729E280121B63A7EDC828C56CDBEB85223946A5254ABEE8E023",
	},
	"boost_step_stool": {
		"source": "GOGOBRO_ASSET_INBOX/02_static_assets/items/boost_step_stool/candidate-001/curated/boost_step_stool-icon-64x64.png",
		"sha256": "97DCA7B6837F0C6D6E92D25CD87F0ED07075BDB46F1E46CB995360A17858C909",
	},
}

const SHIPPING_BINDINGS := {
	"ballistic_liner": {
		"path": "res://game/assets/gogobro_static/items/ballistic_liner.png",
		"sha256": "1F673E6190EB9627B58EAA287FD22DB0F113AE80A6C7529C63EC4FBCDF89BC9F",
	},
	"smoke_shell_helmet": {
		"path": "res://game/assets/gogobro_static/items/smoke_shell_helmet.png",
		"sha256": "9D5D9A14D005BE3B08C5CC90F2E11C74EF214BAC8C921452F34DC1DAEF509BEC",
	},
}


func test_item_manifest_installs_exact_redraws_and_preserves_all_accepted_bytes() -> void:
	var manifest := _read_json(CANDIDATE_MANIFEST_PATH)
	var units := manifest.get("units", []) as Array
	assert_int(int(manifest.get("expected_unit_count", -1))).is_equal(65)
	assert_int(units.size()).is_equal(65)
	var weapon_count := 0
	var item_units: Dictionary = {}
	for unit_value: Variant in units:
		var unit := unit_value as Dictionary
		match String(unit.get("category", "")):
			"weapon":
				weapon_count += 1
			"item":
				item_units[String(unit.get("asset_id", ""))] = unit
	assert_int(weapon_count).is_equal(12)
	assert_int(item_units.size()).is_equal(30)

	for asset_id: String in REDRAW_BINDINGS:
		_assert_preview_binding(item_units, asset_id, REDRAW_BINDINGS[asset_id] as Dictionary)
	for asset_id: String in PRESERVED_PREVIEW_BINDINGS:
		_assert_preview_binding(
			item_units, asset_id, PRESERVED_PREVIEW_BINDINGS[asset_id] as Dictionary
		)
	for asset_id: String in SHIPPING_BINDINGS:
		assert_bool(item_units.has(asset_id)).is_true()
		var binding := SHIPPING_BINDINGS[asset_id] as Dictionary
		assert_str(FileAccess.get_sha256(String(binding.path)).to_upper()).is_equal(
			String(binding.sha256)
		)


func test_all_thirty_item_mechanics_equal_the_pre_redraw_baseline() -> void:
	var baseline := _read_json(MECHANICS_BASELINE_PATH)
	var registry := _read_json(REGISTRY_PATH)
	var actual_items: Array = []
	for unit_value: Variant in registry.get("units", []) as Array:
		var unit := unit_value as Dictionary
		if String(unit.get("category", "")) != "item":
			continue
		actual_items.append(
			{
				"asset_id": unit.get("asset_id"),
				"effects": unit.get("effects"),
				"rarity": unit.get("rarity"),
				"max_count": unit.get("max_count"),
				"appearance": unit.get("appearance"),
			}
		)
	assert_int(actual_items.size()).is_equal(30)
	assert_array(actual_items).is_equal(baseline.get("items", []) as Array)


func test_shipping_manifest_rebinds_only_the_canonical_registry_hash() -> void:
	var manifest := _read_json(SHIPPING_MANIFEST_PATH)
	assert_str(String(manifest.get("canonical_registry_sha256", "")).to_upper()).is_equal(
		FileAccess.get_sha256(REGISTRY_PATH).to_upper()
	)
	var raw := FileAccess.get_file_as_string(SHIPPING_MANIFEST_PATH)
	var hash_pattern := RegEx.new()
	assert_int(
		hash_pattern.compile('"canonical_registry_sha256": "[0-9A-Fa-f]{64}"')
	).is_equal(OK)
	var normalized := hash_pattern.sub(
		raw,
		'"canonical_registry_sha256": "<canonical-registry-sha256>"',
		false
	)
	assert_str(normalized.sha256_text().to_upper()).is_equal(
		SHIPPING_MANIFEST_WITHOUT_REGISTRY_HASH_SHA256
	)


func test_all_item_localization_names_match_contract_and_prose_is_specific() -> void:
	var contract_items := _read_json(REDRAW_CONTRACT_PATH).get("items", {}) as Dictionary
	var registry := _read_json(REGISTRY_PATH)
	var item_count := 0
	for unit_value: Variant in registry.get("units", []) as Array:
		var unit := unit_value as Dictionary
		if String(unit.get("category", "")) != "item":
			continue
		item_count += 1
		var asset_id := String(unit.get("asset_id", ""))
		var contract := contract_items.get(asset_id, {}) as Dictionary
		var localization := unit.get("localization", {}) as Dictionary
		var zh := localization.get("zh_CN", {}) as Dictionary
		var en := localization.get("en", {}) as Dictionary
		assert_str(String(zh.get("name", ""))).is_equal(String(contract.visible_name_zh))
		assert_str(String(en.get("name", ""))).is_equal(String(contract.visible_name_en))
		_assert_specific_prose(String(zh.get("description", "")), true)
		_assert_specific_prose(String(zh.get("flavor", "")), true)
		_assert_specific_prose(String(en.get("description", "")), false)
		_assert_specific_prose(String(en.get("flavor", "")), false)
	assert_int(item_count).is_equal(30)


func _assert_preview_binding(item_units: Dictionary, asset_id: String, expected: Dictionary) -> void:
	assert_bool(item_units.has(asset_id)).is_true()
	if not item_units.has(asset_id):
		return
	var unit := item_units[asset_id] as Dictionary
	assert_str(String(unit.get("source_candidate_path", ""))).is_equal(String(expected.source))
	assert_str(String(unit.get("sha256", "")).to_upper()).is_equal(String(expected.sha256))
	assert_str(String(unit.get("resource_path", ""))).is_equal(
		"res://game/assets/gogobro_static_preview/items/%s.png" % asset_id
	)
	assert_str(FileAccess.get_sha256(String(unit.resource_path)).to_upper()).is_equal(
		String(expected.sha256)
	)
	_assert_pair(unit.get("pixel_size"), 64, 64)
	_assert_pair(unit.get("display_size_px"), 64, 64)
	_assert_pair(unit.get("pivot_px"), 32, 32)
	assert_array((unit.get("anchors_px", {}) as Dictionary).keys()).is_empty()
	assert_array(unit.get("preview_alias_asset_ids", []) as Array).is_empty()


func _assert_specific_prose(value: String, is_zh: bool) -> void:
	var stripped := value.strip_edges()
	assert_bool(not stripped.is_empty()).is_true()
	assert_bool(stripped.length() <= (60 if is_zh else 140)).is_true()
	for forbidden: String in [
		"静态视觉资产",
		"为 GOGOBRO 对局增添辨识度",
		"Static visual asset",
		"brings GOGOBRO a distinct match identity",
	]:
		assert_bool(not stripped.contains(forbidden)).is_true()


func _assert_pair(value: Variant, expected_x: int, expected_y: int) -> void:
	assert_bool(value is Array).is_true()
	if not value is Array:
		return
	var pair := value as Array
	assert_int(pair.size()).is_equal(2)
	if pair.size() != 2:
		return
	assert_int(int(pair[0])).is_equal(expected_x)
	assert_int(int(pair[1])).is_equal(expected_y)


func _read_json(path: String) -> Dictionary:
	assert_bool(FileAccess.file_exists(path)).is_true()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).is_true()
	return parsed as Dictionary
