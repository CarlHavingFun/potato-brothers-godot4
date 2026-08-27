extends GdUnitTestSuite


const CONTRACT_PATH := "res://tools/assets/gogobro_static_redraw_contract_v1.json"
const VALIDATOR_PATH := "res://tools/assets/validate_static_redraws.py"

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
const EXPECTED_ITEM_IDS := [
	"ballistic_liner",
	"silent_step_insoles",
	"crosshair_shim",
	"supply_radar",
	"trade_guard",
	"tactical_med_patch",
	"smoke_shell_helmet",
	"force_buy_runners",
	"eco_round_coin_pouch",
	"rebound_fire_bottle",
	"entry_fragger_dumbbell",
	"corner_lucky_claw",
	"scorched_defuse_pliers",
	"save_time_watch",
	"skyline_grenade",
	"post_match_analysis_desk",
	"one_missed_shot",
	"falling_sniper_charm",
	"boost_step_stool",
	"post_match_mic",
	"halftime_tactics_board",
	"hand_cannon_ace_coin",
	"sneaky_site_mask",
	"arena_chant_cassette",
	"mouse_lift_pad",
	"lineup_chalk",
	"site_hold_bandana",
	"airshot_wing_charm",
	"clutch_stopwatch",
	"three_beat_magazine",
]
const REQUIRED_RECORD_KEYS := [
	"asset_id",
	"visible_name_zh",
	"visible_name_en",
	"subject",
	"width",
	"height",
	"mode",
	"pivot_px",
	"anchor_px",
]
const EXPECTED_WEAPONS := {
	"warmup_shiv": {
		"visible_name_zh": "蝴蝶刀",
		"visible_name_en": "Butterfly Knife",
		"subject": "Butterfly Knife with split handles and exposed pivot",
		"width": 64,
		"height": 64,
		"mode": "melee",
	},
	"community_tapper": {
		"visible_name_zh": "爪子刀",
		"visible_name_en": "Karambit",
		"subject": "Karambit with finger ring and curved claw blade",
		"width": 64,
		"height": 64,
		"mode": "melee",
	},
	"wood_stock_assault_rifle": {
		"visible_name_zh": "AK-47",
		"visible_name_en": "AK-47",
		"subject": "AK-47 with wood furniture and curved magazine",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"heavy_bolt_sniper": {
		"visible_name_zh": "AWP",
		"visible_name_en": "AWP",
		"subject": "AWP with large scope and green chassis",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"suppressed_carbine": {
		"visible_name_zh": "M4A1-S",
		"visible_name_en": "M4A1-S",
		"subject": "M4A1-S with straight magazine and long suppressor",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"suppressed_tactical_pistol": {
		"visible_name_zh": "USP-S",
		"visible_name_en": "USP-S",
		"subject": "USP-S with angular slide and suppressor",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"heavy_hand_cannon": {
		"visible_name_zh": "Desert Eagle",
		"visible_name_en": "Desert Eagle",
		"subject": "Desert Eagle with oversized squared slide",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"service_pistol": {
		"visible_name_zh": "Glock-18",
		"visible_name_en": "Glock-18",
		"subject": "Glock-18 with compact squared slide",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"box_submachine_gun": {
		"visible_name_zh": "MAC-10",
		"visible_name_en": "MAC-10",
		"subject": "MAC-10 with boxy receiver and short barrel",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"compact_submachine_gun": {
		"visible_name_zh": "MP9",
		"visible_name_en": "MP9",
		"subject": "MP9 with polymer body and skeleton stock",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"bullpup_pdw": {
		"visible_name_zh": "P90",
		"visible_name_en": "P90",
		"subject": "P90 with horizontal top magazine",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
	"folding_stock_submachine_gun": {
		"visible_name_zh": "UMP-45",
		"visible_name_en": "UMP-45",
		"subject": "UMP-45 with long box magazine and folding stock",
		"width": 96,
		"height": 64,
		"mode": "ranged",
	},
}
const EXPECTED_ITEM_SUBJECTS := {
	"ballistic_liner": "ballistic plate insert",
	"silent_step_insoles": "gel tactical insoles",
	"crosshair_shim": "sight-calibration shim plate",
	"supply_radar": "handheld supply radar",
	"trade_guard": "padded forearm guard",
	"tactical_med_patch": "sealed trauma patch pouch",
	"smoke_shell_helmet": "smoke-shell helmet",
	"force_buy_runners": "tactical running shoes",
	"eco_round_coin_pouch": "coin pouch",
	"rebound_fire_bottle": "Molotov bottle",
	"entry_fragger_dumbbell": "entry-fragger dumbbell",
	"corner_lucky_claw": "claw keychain",
	"scorched_defuse_pliers": "scorched defuse pliers",
	"save_time_watch": "digital save-time watch",
	"skyline_grenade": "taped HE grenade",
	"post_match_analysis_desk": "folding laptop analysis desk",
	"one_missed_shot": "cracked scope lens in a protective case",
	"falling_sniper_charm": "dangling sniper charm",
	"boost_step_stool": "folding boost stool",
	"post_match_mic": "broadcast microphone",
	"halftime_tactics_board": "tactics clipboard",
	"hand_cannon_ace_coin": "engraved ace coin",
	"sneaky_site_mask": "balaclava",
	"arena_chant_cassette": "arena-chant cassette",
	"mouse_lift_pad": "mouse-lift pad",
	"lineup_chalk": "chalk holder",
	"site_hold_bandana": "site-hold bandana",
	"airshot_wing_charm": "wing-shaped sniper charm",
	"clutch_stopwatch": "clutch stopwatch",
	"three_beat_magazine": "three-stripe rifle magazine",
}
const EXPECTED_ITEM_NAMES_ZH := {
	"ballistic_liner": "防弹内衬",
	"silent_step_insoles": "静步鞋垫",
	"crosshair_shim": "准星校片",
	"supply_radar": "补给雷达",
	"trade_guard": "补枪护腕",
	"tactical_med_patch": "战术急救贴",
	"smoke_shell_helmet": "封烟头盔",
	"force_buy_runners": "强起跑鞋",
	"eco_round_coin_pouch": "经济局零钱袋",
	"rebound_fire_bottle": "反弹火线瓶",
	"entry_fragger_dumbbell": "突破手哑铃",
	"corner_lucky_claw": "夹点幸运爪",
	"scorched_defuse_pliers": "灼热拆包钳",
	"save_time_watch": "保枪倒计表",
	"skyline_grenade": "天外高抛雷",
	"post_match_analysis_desk": "赛后复盘台",
	"one_missed_shot": "裂镜纪念盒",
	"falling_sniper_charm": "坠线狙击挂件",
	"boost_step_stool": "垫点折凳",
	"post_match_mic": "赛后嘴硬麦",
	"halftime_tactics_board": "半场战术板",
	"hand_cannon_ace_coin": "手炮五杀币",
	"sneaky_site_mask": "静步面罩",
	"arena_chant_cassette": "主场合唱磁带",
	"mouse_lift_pad": "抬鼠垫",
	"lineup_chalk": "道具点位粉笔",
	"site_hold_bandana": "守点头巾",
	"airshot_wing_charm": "腾空狙击翼章",
	"clutch_stopwatch": "残局秒表",
	"three_beat_magazine": "三发节奏弹匣",
}


func test_redraw_contract_has_exact_weapon_and_item_sets() -> void:
	assert_bool(FileAccess.file_exists(CONTRACT_PATH)).is_true()
	if not FileAccess.file_exists(CONTRACT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	assert_bool(parsed is Dictionary).is_true()
	if not (parsed is Dictionary):
		return
	var contract := parsed as Dictionary
	assert_str(String(contract.get("schema_version", ""))).is_equal(
		"gogobro-static-redraw-contract-v1"
	)
	var weapons := contract.get("weapons", {}) as Dictionary
	var items := contract.get("items", {}) as Dictionary
	assert_array(weapons.keys()).contains_exactly_in_any_order(EXPECTED_WEAPON_IDS)
	assert_array(items.keys()).contains_exactly_in_any_order(EXPECTED_ITEM_IDS)

	for asset_id: String in EXPECTED_WEAPON_IDS:
		var record := weapons.get(asset_id, {}) as Dictionary
		assert_array(record.keys()).contains_exactly_in_any_order(REQUIRED_RECORD_KEYS)
		assert_str(String(record.get("asset_id", ""))).is_equal(asset_id)
		var expected := EXPECTED_WEAPONS[asset_id] as Dictionary
		for field: String in ["visible_name_zh", "visible_name_en", "subject", "mode"]:
			assert_that(record.get(field)).is_equal(expected.get(field))
		assert_int(int(record.get("width", 0))).is_equal(int(expected.width))
		assert_int(int(record.get("height", 0))).is_equal(int(expected.height))
		_assert_integer_point(record.get("pivot_px"), int(record.width), int(record.height))
		var expected_anchor := "contact" if String(record.mode) == "melee" else "muzzle"
		_assert_anchor(record, expected_anchor)
		var pivot := record.pivot_px as Array
		var anchor := (record.anchor_px as Dictionary)[expected_anchor] as Array
		assert_int(int(anchor[0])).is_greater(int(pivot[0]))
		if expected_anchor == "contact":
			assert_int(int(anchor[0])).is_greater_equal(int(record.width) * 2 / 3)
		else:
			assert_int(int(anchor[0])).is_greater_equal(int(record.width) * 3 / 4)

	for asset_id: String in EXPECTED_ITEM_IDS:
		var record := items.get(asset_id, {}) as Dictionary
		assert_array(record.keys()).contains_exactly_in_any_order(REQUIRED_RECORD_KEYS)
		assert_str(String(record.get("asset_id", ""))).is_equal(asset_id)
		assert_str(String(record.get("visible_name_zh", ""))).is_equal(
			String(EXPECTED_ITEM_NAMES_ZH[asset_id])
		)
		assert_str(String(record.get("subject", ""))).is_equal(
			String(EXPECTED_ITEM_SUBJECTS[asset_id])
		)
		assert_int(int(record.get("width", 0))).is_equal(64)
		assert_int(int(record.get("height", 0))).is_equal(64)
		assert_str(String(record.get("mode", ""))).is_equal("item")
		_assert_integer_point(record.get("pivot_px"), 64, 64)
		_assert_anchor(record, "contact")
		for forbidden: String in [
			"footprint", "arrow", "speed streak", "floating number", "status glyph",
		]:
			assert_bool(String(record.subject).to_lower().contains(forbidden)).is_false()

	var missed_shot := items.get("one_missed_shot", {}) as Dictionary
	assert_str(String(missed_shot.get("visible_name_en", ""))).is_equal(
		"Cracked-Scope Keepsake"
	)


func test_python_validator_accepts_every_production_contract_record_before_art_install() -> void:
	var root_uri := "user://static-redraw-production-contract-%s" % Time.get_ticks_usec()
	var root_path := ProjectSettings.globalize_path(root_uri)
	assert_int(DirAccess.make_dir_recursive_absolute(root_path)).is_equal(OK)
	var json_out_path := root_path.path_join("results.json")
	var output: Array = []
	var exit_code := OS.execute(
		_python_executable(),
		PackedStringArray([
			ProjectSettings.globalize_path(VALIDATOR_PATH),
			"--contract",
			ProjectSettings.globalize_path(CONTRACT_PATH),
			"--assets-root",
			root_path,
			"--json-out",
			json_out_path,
		]),
		output,
		true
	)
	assert_int(exit_code).is_equal(1)
	assert_bool(FileAccess.file_exists(json_out_path)).is_true()
	if not FileAccess.file_exists(json_out_path):
		return
	var rows := JSON.parse_string(FileAccess.get_file_as_string(json_out_path)) as Array
	assert_int(rows.size()).is_equal(EXPECTED_WEAPON_IDS.size() + EXPECTED_ITEM_IDS.size())
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var checks := row.get("checks", {}) as Dictionary
		assert_bool(bool(checks.get("contract", false))).is_true()
		assert_bool(bool(checks.get("file_present", true))).is_false()


func test_validator_accepts_crisp_connected_png_without_a_palette_chunkiness_gate() -> void:
	var fixture := _create_fixture(
		"detailed_item",
		"items",
		64,
		64,
		"item",
		[32, 32],
		"contact",
		[32, 32]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(2, 2, 60, 60), 30)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_equal(0)
	var row := _only_result_row(result)
	assert_bool(bool(row.get("mechanical_pass", false))).is_true()
	assert_str(String(row.get("visual_approval", ""))).is_equal("not_evaluated")
	assert_str(String(row.get("actual_size_readability", ""))).is_equal(
		"requires_human_review"
	)
	var metrics := row.get("metrics", {}) as Dictionary
	assert_int(int(metrics.get("unique_opaque_colors", 0))).is_greater(24)


func test_validator_rejects_soft_alpha_from_a_real_png() -> void:
	var fixture := _create_fixture(
		"soft_alpha_item",
		"items",
		64,
		64,
		"item",
		[32, 32],
		"contact",
		[32, 32]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(2, 2, 60, 60), 1)
	var image := Image.load_from_file(fixture.png_path)
	image.set_pixel(10, 10, Color8(220, 120, 40, 128))
	assert_int(image.save_png(fixture.png_path)).is_equal(OK)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var row := _only_result_row(result)
	assert_bool(bool(row.get("mechanical_pass", true))).is_false()
	assert_bool(bool((row.get("checks", {}) as Dictionary).get("binary_alpha", true))).is_false()


func test_validator_rejects_a_disconnected_subject_from_a_real_png() -> void:
	var fixture := _create_fixture(
		"disconnected_item",
		"items",
		64,
		64,
		"item",
		[32, 32],
		"contact",
		[32, 32]
	)
	var image := _blank_image(64, 64)
	_fill_rect(image, Rect2i(2, 2, 35, 60), Color8(220, 120, 40, 255))
	_fill_rect(image, Rect2i(40, 2, 22, 30), Color8(220, 120, 40, 255))
	assert_int(image.save_png(fixture.png_path)).is_equal(OK)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var checks := (_only_result_row(result).get("checks", {}) as Dictionary)
	assert_bool(bool(checks.get("connected_component", true))).is_false()


func test_validator_rejects_a_firearm_too_short_for_actual_size_readability() -> void:
	var fixture := _create_fixture(
		"short_firearm",
		"weapons",
		96,
		64,
		"ranged",
		[36, 40],
		"muzzle",
		[88, 28]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(20, 20, 69, 26), 3)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var checks := (_only_result_row(result).get("checks", {}) as Dictionary)
	assert_bool(bool(checks.get("silhouette_extent", true))).is_false()


func test_validator_rejects_firearm_satellites_that_only_inflate_the_total_bbox() -> void:
	var fixture := _create_fixture(
		"satellite_inflated_firearm",
		"weapons",
		96,
		64,
		"ranged",
		[36, 40],
		"muzzle",
		[88, 28]
	)
	var image := _blank_image(96, 64)
	_fill_rect(image, Rect2i(20, 20, 69, 26), Color8(70, 74, 80, 255))
	_fill_rect(image, Rect2i(2, 20, 2, 2), Color8(220, 120, 40, 255))
	assert_int(image.save_png(fixture.png_path)).is_equal(OK)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var row := _only_result_row(result)
	var checks := row.get("checks", {}) as Dictionary
	var metrics := row.get("metrics", {}) as Dictionary
	assert_bool(bool(checks.get("connected_component", false))).is_true()
	assert_bool(bool(checks.get("anchor_contract", false))).is_true()
	assert_bool(bool(checks.get("silhouette_extent", true))).is_false()
	assert_int(int(metrics.get("occupied_width", -1))).is_equal(87)
	assert_int(int(metrics.get("largest_component_width", -1))).is_equal(69)


func test_validator_accepts_a_firearm_at_the_largest_component_width_boundary() -> void:
	var fixture := _create_fixture(
		"valid_firearm",
		"weapons",
		96,
		64,
		"ranged",
		[36, 40],
		"muzzle",
		[89, 28]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(20, 20, 70, 26), 8)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_equal(0)
	var row := _only_result_row(result)
	var checks := row.get("checks", {}) as Dictionary
	var metrics := row.get("metrics", {}) as Dictionary
	assert_bool(bool(row.get("mechanical_pass", false))).is_true()
	assert_bool(bool(checks.get("silhouette_extent", false))).is_true()
	assert_int(int(metrics.get("largest_component_width", -1))).is_equal(70)


func test_validator_rejects_a_knife_too_small_for_actual_size_readability() -> void:
	var fixture := _create_fixture(
		"small_knife",
		"weapons",
		64,
		64,
		"melee",
		[20, 35],
		"contact",
		[52, 30]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(12, 12, 41, 41), 3)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var checks := (_only_result_row(result).get("checks", {}) as Dictionary)
	assert_bool(bool(checks.get("silhouette_extent", true))).is_false()


func test_validator_accepts_a_knife_at_the_largest_component_extent_boundary() -> void:
	var fixture := _create_fixture(
		"valid_knife",
		"weapons",
		64,
		64,
		"melee",
		[20, 35],
		"contact",
		[52, 30]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(11, 12, 42, 41), 8)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_equal(0)
	var row := _only_result_row(result)
	var checks := row.get("checks", {}) as Dictionary
	var metrics := row.get("metrics", {}) as Dictionary
	assert_bool(bool(row.get("mechanical_pass", false))).is_true()
	assert_bool(bool(checks.get("silhouette_extent", false))).is_true()
	assert_int(int(metrics.get("largest_component_width", -1))).is_equal(42)
	assert_int(int(metrics.get("largest_component_height", -1))).is_equal(41)


func test_validator_rejects_a_weapon_anchor_detached_from_the_subject() -> void:
	var fixture := _create_fixture(
		"detached_muzzle",
		"weapons",
		96,
		64,
		"ranged",
		[36, 39],
		"muzzle",
		[90, 5]
	)
	_write_rectangle_png(fixture.png_path, Rect2i(2, 28, 90, 18), 3)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var checks := (_only_result_row(result).get("checks", {}) as Dictionary)
	assert_bool(bool(checks.get("anchor_contract", true))).is_false()


func test_validator_rejects_a_muzzle_on_a_broken_off_barrel_segment() -> void:
	var fixture := _create_fixture(
		"broken_barrel",
		"weapons",
		96,
		64,
		"ranged",
		[36, 39],
		"muzzle",
		[91, 28]
	)
	var image := _blank_image(96, 64)
	_fill_rect(image, Rect2i(2, 28, 69, 18), Color8(70, 74, 80, 255))
	_fill_rect(image, Rect2i(80, 26, 13, 5), Color8(70, 74, 80, 255))
	assert_int(image.save_png(fixture.png_path)).is_equal(OK)
	var result := _run_validator(fixture)
	assert_int(int(result.exit_code)).is_not_equal(0)
	var row := _only_result_row(result)
	var checks := row.get("checks", {}) as Dictionary
	assert_bool(bool(checks.get("connected_component", false))).is_true()
	assert_bool(bool(checks.get("anchor_contract", true))).is_false()


func _assert_anchor(record: Dictionary, anchor_name: String) -> void:
	var anchors_value: Variant = record.get("anchor_px")
	assert_bool(anchors_value is Dictionary).is_true()
	if not (anchors_value is Dictionary):
		return
	var anchors := anchors_value as Dictionary
	assert_array(anchors.keys()).contains_exactly([anchor_name])
	_assert_integer_point(anchors.get(anchor_name), int(record.width), int(record.height))


func _assert_integer_point(value: Variant, width: int, height: int) -> void:
	assert_bool(value is Array).is_true()
	if not (value is Array):
		return
	var point := value as Array
	assert_int(point.size()).is_equal(2)
	if point.size() != 2:
		return
	# Godot represents every parsed JSON number as float, so verify integral value
	# here; the Python validator above verifies the native JSON token type is int.
	assert_float(float(point[0])).is_equal(float(int(point[0])))
	assert_float(float(point[1])).is_equal(float(int(point[1])))
	assert_bool(int(point[0]) >= 0 and int(point[0]) < width).is_true()
	assert_bool(int(point[1]) >= 0 and int(point[1]) < height).is_true()


func _create_fixture(
	asset_id: String,
	category: String,
	width: int,
	height: int,
	mode: String,
	pivot: Array,
	anchor_name: String,
	anchor: Array
) -> Dictionary:
	var root_uri := "user://static-redraw-%s-%s" % [asset_id, Time.get_ticks_usec()]
	var root_path := ProjectSettings.globalize_path(root_uri)
	var category_path := root_path.path_join(category)
	assert_int(DirAccess.make_dir_recursive_absolute(category_path)).is_equal(OK)
	var contract_path := root_path.path_join("contract.json")
	var json_out_path := root_path.path_join("results.json")
	var record := {
		"asset_id": asset_id,
		"visible_name_zh": "测试物件",
		"visible_name_en": "Fixture Object",
		"subject": "fixture physical object",
		"width": width,
		"height": height,
		"mode": mode,
		"pivot_px": pivot,
		"anchor_px": {anchor_name: anchor},
	}
	var contract := {
		"schema_version": "gogobro-static-redraw-contract-v1",
		"weapons": {asset_id: record} if category == "weapons" else {},
		"items": {asset_id: record} if category == "items" else {},
	}
	var file := FileAccess.open(contract_path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file != null:
		file.store_string(JSON.stringify(contract, "\t"))
		file.close()
	return {
		"asset_id": asset_id,
		"category": category,
		"root_path": root_path,
		"contract_path": contract_path,
		"json_out_path": json_out_path,
		"png_path": category_path.path_join(asset_id + ".png"),
	}


func _run_validator(fixture: Dictionary) -> Dictionary:
	var output: Array = []
	var exit_code := OS.execute(
		_python_executable(),
		PackedStringArray([
			ProjectSettings.globalize_path(VALIDATOR_PATH),
			"--contract",
			String(fixture.contract_path),
			"--assets-root",
			String(fixture.root_path),
			"--category",
			String(fixture.category),
			"--json-out",
			String(fixture.json_out_path),
		]),
		output,
		true
	)
	return {
		"exit_code": exit_code,
		"json_out_path": fixture.json_out_path,
		"output": output,
	}


func _only_result_row(result: Dictionary) -> Dictionary:
	var json_out_path := String(result.json_out_path)
	assert_bool(FileAccess.file_exists(json_out_path)).is_true()
	if not FileAccess.file_exists(json_out_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_out_path))
	assert_bool(parsed is Array).is_true()
	if not (parsed is Array):
		return {}
	var rows := parsed as Array
	assert_int(rows.size()).is_equal(1)
	if rows.size() != 1 or not (rows[0] is Dictionary):
		return {}
	return rows[0] as Dictionary


func _python_executable() -> String:
	var configured := OS.get_environment("PYTHON")
	return configured if not configured.is_empty() else "python"


func _write_rectangle_png(path: String, rect: Rect2i, color_count: int) -> void:
	var image := _blank_image(96 if rect.end.x > 64 else 64, 64)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var color_index := (x + y * rect.size.x) % color_count
			image.set_pixel(
				x,
				y,
				Color8(
					20 + color_index * 7,
					40 + color_index * 3,
					60 + color_index * 5,
					255
				)
			)
	assert_int(image.save_png(path)).is_equal(OK)


func _blank_image(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 0, 0, 0))
	return image


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			image.set_pixel(x, y, color)
