extends GdUnitTestSuite


const Registry = preload("res://game/content/assets/static_asset_registry.gd")
const CANONICAL_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CANDIDATE_002_METADATA_PATH := "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/candidate-metadata.json"
const EXPECTED_ITEM_APPEARANCES := {
	"ballistic_liner": ["torso", "chest_center", "FRAME_OVERLAY", 40],
	"silent_step_insoles": ["feet", "feet_pair", "FRAME_OVERLAY", 40],
	"crosshair_shim": ["wrist", "wrist_right", "FRAME_OVERLAY", 40],
	"supply_radar": ["side_left", "hip_left", "RIGID", 40],
	"trade_guard": ["wrist", "wrist_left", "FRAME_OVERLAY", 40],
	"tactical_med_patch": ["torso", "chest_left", "FRAME_OVERLAY", 40],
	"smoke_shell_helmet": ["head", "head_shell", "RIGID", 40],
	"force_buy_runners": ["feet", "feet_pair", "FRAME_OVERLAY", 40],
	"eco_round_coin_pouch": ["side_right", "hip_right", "RIGID", 40],
	"rebound_fire_bottle": ["side_left", "hip_left", "RIGID", 40],
	"entry_fragger_dumbbell": ["back", "back_upper", "RIGID", -10],
	"corner_lucky_claw": ["trinket_left", "trinket_left", "RIGID", 40],
	"scorched_defuse_pliers": ["side_right", "hip_right", "RIGID", 40],
	"save_time_watch": ["wrist", "wrist_right", "FRAME_OVERLAY", 40],
	"skyline_grenade": ["side_left", "hip_left", "RIGID", 40],
	"post_match_analysis_desk": ["back", "back_center", "RIGID", -10],
	"one_missed_shot": ["trinket_right", "trinket_right", "RIGID", 40],
	"falling_sniper_charm": ["trinket_left", "trinket_left", "RIGID", 40],
	"boost_step_stool": ["back", "back_lower", "RIGID", -10],
	"post_match_mic": ["torso", "chest_center", "FRAME_OVERLAY", 40],
	"halftime_tactics_board": ["back", "back_center", "RIGID", -10],
	"hand_cannon_ace_coin": ["trinket_right", "trinket_right", "RIGID", 40],
	"sneaky_site_mask": ["face", "face_mask", "RIGID", 40],
	"arena_chant_cassette": ["side_right", "hip_right", "RIGID", 40],
	"mouse_lift_pad": ["back", "back_upper", "RIGID", -10],
	"lineup_chalk": ["side_left", "hip_left", "RIGID", 40],
	"site_hold_bandana": ["head", "forehead", "RIGID", 40],
	"airshot_wing_charm": ["trinket_left", "trinket_left", "RIGID", 40],
	"clutch_stopwatch": ["wrist", "wrist_left", "FRAME_OVERLAY", 40],
	"three_beat_magazine": ["side_right", "hip_right", "RIGID", 40],
}


func test_canonical_registry_keeps_only_noncharacter_scope_and_excludes_generic_carbine() -> void:
	var result := Registry.load_registry(CANONICAL_PATH)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	var registry := result.get("registry", {}) as Dictionary
	assert_array(errors).is_empty()
	assert_int((registry.get("units", []) as Array).size()).is_equal(70)
	assert_int(_approval_status_count(registry, "planned")).is_equal(61)
	assert_int(_approval_status_count(registry, "review")).is_equal(0)
	assert_int(_approval_status_count(registry, "approved")).is_equal(9)
	for approved_asset_id in [
		"warmup_shiv",
		"service_pistol",
		"projectile_hit_kit",
		"ballistic_liner",
		"one_more_round",
		"hud_icon_kit",
		"control_icon_kit",
		"difficulty_badge_kit",
		"smoke_shell_helmet",
	]:
		assert_str(str(_unit_by_asset_id(registry, approved_asset_id).get("approval_status", ""))).is_equal("approved")
	for excluded_asset_id in ["community_tapper", "supply_crate", "four_state_button"]:
		assert_str(str(_unit_by_asset_id(registry, excluded_asset_id).get("approval_status", ""))).is_equal("planned")
	for removed_asset_id in [
		"service_carbine",
		"master_ni",
		"lost_rotator",
		"long_angle_sentry",
		"force_buy_rusher",
		"site_scout_chicken",
	]:
		assert_dict(_unit_by_asset_id(registry, removed_asset_id)).is_empty()
	var category_counts := registry.get("category_counts", {}) as Dictionary
	assert_bool(category_counts.has("character_creature")).is_false()
	assert_int(int(category_counts.get("weapon", 0))).is_equal(12)
	assert_int(int(category_counts.get("projectile_hit_kit", 0))).is_equal(1)
	assert_int(int(category_counts.get("item", 0))).is_equal(30)
	assert_int(int(category_counts.get("upgrade", 0))).is_equal(6)
	assert_int(int(category_counts.get("world", 0))).is_equal(11)
	assert_int(int(category_counts.get("ui_brand", 0))).is_equal(10)


func test_all_thirty_items_keep_the_fixed_slot_socket_mode_and_depth_mapping() -> void:
	var registry := _canonical_registry()
	var actual := {}
	for unit_variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if unit.get("category") != "item":
			continue
		var appearance := unit.get("appearance", {}) as Dictionary
		actual[str(unit.get("asset_id"))] = [
			appearance.get("slot"),
			appearance.get("socket"),
			appearance.get("mode"),
			int(appearance.get("depth", 0)),
		]
	assert_int(actual.size()).is_equal(30)
	assert_dict(actual).is_equal(EXPECTED_ITEM_APPEARANCES)


func test_loader_rejects_each_required_malformed_temporary_fixture() -> void:
	var missing_unit := _canonical_registry()
	(missing_unit["units"] as Array).pop_back()
	_assert_fixture_error(missing_unit, "expected 70 units")

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

	var missing_item_socket := _canonical_registry()
	((_first_unit_in_category(missing_item_socket, "item") as Dictionary)["appearance"] as Dictionary).erase("socket")
	_assert_fixture_error(missing_item_socket, "item appearance missing socket")

	var mismatched_item_socket := _canonical_registry()
	((_first_unit_in_category(mismatched_item_socket, "item") as Dictionary)["appearance"] as Dictionary)["socket"] = "head_shell"
	_assert_fixture_error(mismatched_item_socket, "item appearance slot/socket mismatch")

	var front_layer_back_item := _canonical_registry()
	var back_item := _unit_by_asset_id(front_layer_back_item, "entry_fragger_dumbbell")
	(back_item["appearance"] as Dictionary)["depth"] = 40
	_assert_fixture_error(front_layer_back_item, "back appearance depth must be negative")

	var valid_but_wrong_item_socket := _canonical_registry()
	var supply_radar := _unit_by_asset_id(valid_but_wrong_item_socket, "supply_radar")
	(supply_radar["appearance"] as Dictionary)["slot"] = "side_right"
	(supply_radar["appearance"] as Dictionary)["socket"] = "hip_right"
	_assert_fixture_error(valid_but_wrong_item_socket, "item appearance violates fixed slot contract")

	var wrong_front_depth := _canonical_registry()
	var front_item := _unit_by_asset_id(wrong_front_depth, "supply_radar")
	(front_item["appearance"] as Dictionary)["depth"] = -10
	_assert_fixture_error(wrong_front_depth, "item appearance violates fixed depth contract")

	var fractional_depth := _canonical_registry()
	var fractional_item := _unit_by_asset_id(fractional_depth, "supply_radar")
	(fractional_item["appearance"] as Dictionary)["depth"] = 40.5
	_assert_fixture_error(fractional_depth, "item appearance depth must be an integer")

	var handwritten_effect_copy := _canonical_registry()
	var english_copy := ((_first_unit_in_category(handwritten_effect_copy, "item") as Dictionary)["localization"] as Dictionary)["en"] as Dictionary
	english_copy["description"] = "+3 max health"
	_assert_fixture_error(handwritten_effect_copy, "handwritten numeric effect text")


func test_loader_accepts_only_the_canonical_approval_states() -> void:
	for approval_status in ["planned", "generated", "review", "approved", "integrated", "qa_passed"]:
		var accepted := _canonical_registry()
		var accepted_unit := _smoke_shell_helmet(accepted) if approval_status == "review" else _unit_by_asset_id(accepted, "community_tapper")
		accepted_unit["approval_status"] = approval_status
		if approval_status == "review":
			accepted_unit.erase("approval_history")
		_assert_fixture_has_no_errors(accepted)
	for approval_status in ["draft", "rejected"]:
		var rejected := _canonical_registry()
		_unit_by_asset_id(rejected, "community_tapper")["approval_status"] = approval_status
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
	var item_copy := ((_first_unit_in_category(numeric_flavor, "item") as Dictionary)["localization"] as Dictionary)["en"] as Dictionary
	item_copy["flavor"] = "Wins with 3 precise moves."
	_assert_fixture_error(numeric_flavor, "handwritten numeric effect text")


func test_smoke_shell_helmet_approval_preserves_candidate_provenance_and_human_evidence() -> void:
	var result := Registry.load_registry(CANONICAL_PATH)
	var helmet := _smoke_shell_helmet(result.get("registry", {}) as Dictionary)
	var localization := helmet.get("localization", {}) as Dictionary
	assert_str(str(helmet.get("approval_status", ""))).is_equal("approved")
	assert_str(str(helmet.get("active_candidate_id", ""))).is_equal("candidate-002")
	assert_int((helmet.get("candidate_history", []) as Array).size()).is_equal(2)
	assert_array(helmet.get("approval_history", []) as Array).contains_exactly([{
		"candidate_id": "candidate-002",
		"decision": "approved",
		"authority": "explicit_user_approval_in_current_task",
		"approved_at_utc": "2026-08-24T12:04:47Z",
	}])
	assert_str(str(((localization["zh_CN"] as Dictionary).get("description", "")))).is_equal("加固外壳提高防护，但沉重结构会拖慢转点。")
	assert_str(str(((localization["en"] as Dictionary).get("description", "")))).is_equal("A reinforced shell improves protection, but its weight slows every rotate.")
	assert_str(str(((localization["zh_CN"] as Dictionary).get("flavor", "")))).is_equal("烟封好了，脚步也顺便封住了。")
	assert_str(str(((localization["en"] as Dictionary).get("flavor", "")))).is_equal("The smoke is sealed. So is your sprint.")

	var old_candidate := _candidate_history_entry(helmet, "candidate-001")
	assert_str(str(old_candidate.get("decision", ""))).is_equal("revision_requested")
	assert_array(old_candidate.get("reasons", []) as Array).contains_exactly([
		"icon_reuse",
		"appearance_offset",
		"appearance_oversized",
	])
	assert_int((old_candidate.get("artifacts", []) as Array).size()).is_equal(10)
	var provenance := old_candidate.get("provenance", {}) as Dictionary
	assert_dict(provenance).is_equal({
		"prompt_version": "gogobro-static-v1",
		"request_artifact_roles": ["icon_request", "appearance_request"],
	})
	for expected in [
		["icon", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/icon/run/frames/icon/frame-0.png", 1968, "C0AD74445595D80A61BA979B4E668B1FF12A566FEDEF91EC801E38240F29002C", {"format":"PNG","width":256,"height":256,"alpha":true}],
		["appearance", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/cleaned/smoke-shell-helmet-appearance-128.png", 2206, "B3932E02DAF39074CE048E45B6FAE7F221019D87AD7B3A4327FA40714F25874A", {"format":"PNG","width":128,"height":128,"alpha":true,"appearance_mode":"RIGID"}],
		["anchors", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/appearance/anchors-walk-down.json", 8359, "BB07E3105A39B9071AD1A5706AE74CD48FAB2D7AE25D13CFE2EE1F86C1010D13", {"format":"JSON","state":"walk_down","anchor_count":8}],
		["composite_frame", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/qa/composite-frame-001.png", 3295, "491710EE2758D826B90B614C95ED54FB0AE675F7C16C60D974306AE6B370D14A", {"format":"PNG","width":128,"height":128,"alpha":true}],
		["composite_atlas", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/qa/composite-atlas-8x128.png", 9223, "1B80D5DD228D215F058D4B289C194F55C4191C9408941F9DAC5E67AB29D88D66", {"format":"PNG","width":1024,"height":128,"alpha":true,"columns":8,"frame_width":128,"frame_height":128}],
		["runtime_preview", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/qa/runtime-size-1920x1080.png", 14125, "DFA42A196AA3B05C78DF7970EBBF40A3D37766638317683FEFE1374169642D8B", {"format":"PNG","width":1920,"height":1080}],
		["approval_card", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/qa/approval-card.png", 168311, "44E594051E8522988372FB8C73C04220FA0490F7263C0D075CD3D2DC4C5B140D", {"format":"PNG","width":1800,"height":1200}],
		["qa_report", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/qa/candidate-qa-report.json", 8367, "030155097E2892F706E4246316D8E926D73D52A69F88D212A0792D46B1D06A3E", {"format":"JSON"}],
		["icon_request", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/requests/icon-request.json", 268, "4A8A4E327FFEDDDC95324070B7BD5D20B68218F801632A2E1388DA58CE708C79", {"format":"JSON","purpose":"provenance"}],
		["appearance_request", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/requests/appearance-request.json", 294, "13CD24D70593147C20EEFC8EAC6E229A21DE59B6B454522ECD3A1D707111E32D", {"format":"JSON","purpose":"provenance"}],
	]:
		var artifact := _candidate_artifact(old_candidate, expected[0])
		assert_str(str(artifact.get("path", ""))).is_equal(expected[1])
		assert_int(int(artifact.get("bytes", 0))).is_equal(expected[2])
		assert_str(str(artifact.get("sha256", ""))).is_equal(expected[3])
		_assert_output_spec(artifact.get("output_spec", {}) as Dictionary, expected[4] as Dictionary)

	var active_candidate := _candidate_history_entry(helmet, "candidate-002")
	var metadata := _candidate_metadata()
	assert_str(str(active_candidate.get("decision", ""))).is_equal("review")
	assert_str(str(active_candidate.get("harmony_verdict", ""))).is_equal("harmony_pass")
	assert_array(active_candidate.get("reasons", []) as Array).is_empty()
	assert_int((active_candidate.get("artifacts", []) as Array).size()).is_equal(12)
	for expected in [
		["icon", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/icon-256.png", 3030, "9d5d9a14d005be3b08c5cc90f2e11c74ef214bac8c921452f34dc1daef509bec", {"format":"PNG","width":256,"height":256,"alpha":true}],
		["appearance", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/appearance-128.png", 2206, "b3932e02daf39074ce048e45b6fae7f221019d87ad7b3a4327fa40714f25874a", {"format":"PNG","width":128,"height":128,"alpha":true}],
		["anchors", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/appearance/anchors-walk-down.json", 2289, "7055d9a6a12b35c06ba3744a78f8ca7cc4b5c9e7e48cf0ba94ba383898c0978e", {"format":"JSON","state":"walk_down","anchor_count":8}],
		["composite_frame", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/composite-frame-001.png", 3247, "5e58cd849ad75884506f4f7f686a3aa5d30007b855088e3a0592092ab1012717", {"format":"PNG","width":128,"height":128,"alpha":true}],
		["composite_atlas", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/composite-atlas-8x128.png", 9297, "75af426bf5131897830a60a581eebaf003f70e436ea6f4a00903cf186821eb1f", {"format":"PNG","width":1024,"height":128,"alpha":true}],
		["runtime_preview", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/runtime-size-1920x1080.png", 15373, "ae675561f3c102769dd07a6258131ef64d7a7209880578a9380e1eb4f0ce2462", {"format":"PNG","width":1920,"height":1080,"alpha":true}],
		["harmony_overlay", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-overlay.png", 9789, "d766e2b6de396977f522b13677df105467acf2cebe9ae71ceb46d609eafb59b6", {"format":"PNG","width":1024,"height":128,"alpha":true}],
		["harmony_actual_size", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-actual-size.png", 20053, "8de757de73a37158c7592e33867510e009cae3dc04dd91d4228202dcc6b4cb60", {"format":"PNG","width":1920,"height":1080,"alpha":true}],
		["harmony_report", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-report.json", 5859, "4d21dbb98d13b9ca24363af75c4426f3d017e0bed17562d242d77bec29dc82b1", {"format":"JSON"}],
		["visual_rubric", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/visual-rubric.json", 1094, "617b7c1a95917a9a8f903a54a5be68cc49b6162c9593c8f73960450e5cad0c6b", {"format":"JSON"}],
		["pixel_qa_report", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/pixel-qa-report.json", 1729, "23be2391ad691928883e9da25af13972b50410cfd90628d2a91a27657dc6c00e", {"format":"JSON"}],
		["approval_card", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/approval-card.png", 156765, "d231f9c62df796df79b64e22e70a83baf9c57d3a3628b4fac31057ca10961820", {"format":"PNG","width":1800,"height":1200,"alpha":true}],
	]:
		var artifact := _candidate_artifact(active_candidate, expected[0])
		assert_str(str(artifact.get("path", ""))).is_equal(expected[1])
		assert_int(int(artifact.get("bytes", 0))).is_equal(expected[2])
		assert_str(str(artifact.get("sha256", ""))).is_equal(expected[3])
		_assert_output_spec(artifact.get("output_spec", {}) as Dictionary, expected[4] as Dictionary)
	var metrics := active_candidate.get("metrics", {}) as Dictionary
	assert_float(float(metrics.get("max_feature_center_error_px", -1.0))).is_equal(0.0)
	assert_float(float(metrics.get("max_protected_occlusion_ratio", -1.0))).is_equal(0.0)
	assert_float(float(metrics.get("max_residual_jitter_px", -1.0))).is_equal(0.0)
	assert_float(float(metrics.get("outer_width_ratio", -1.0))).is_equal(1.0689655172413792)
	assert_int(int(metrics.get("visual_rubric_total", 0))).is_equal(10)
	assert_str(str(active_candidate.get("visual_rubric_sha256", ""))).is_equal("617b7c1a95917a9a8f903a54a5be68cc49b6162c9593c8f73960450e5cad0c6b")
	var fonts := active_candidate.get("font_provenance", {}) as Dictionary
	assert_str(str((fonts.get("regular", {}) as Dictionary).get("path", ""))).is_equal("C:\\Windows\\Fonts\\msyh.ttc")
	assert_str(str((fonts.get("regular", {}) as Dictionary).get("sha256", ""))).is_equal("d79c55e68b1131eea0cc1c47be4f572d964f28c682e143db2ad09c1e4cb07a3f")
	assert_str(str((fonts.get("bold", {}) as Dictionary).get("path", ""))).is_equal("C:\\Windows\\Fonts\\msyhbd.ttc")
	assert_str(str((fonts.get("bold", {}) as Dictionary).get("sha256", ""))).is_equal("4508821b3dffe01f0ef5e5326a3e60df705a44633858811f67b6982dce3f6ee6")
	var report_verdicts := active_candidate.get("report_verdicts", {}) as Dictionary
	assert_bool(bool(report_verdicts.get("pixel_qa_passed", false))).is_true()
	assert_str(str(report_verdicts.get("harmony", ""))).is_equal("harmony_pass")
	var approved_review_sources := (active_candidate.get("source_sha256", {}) as Dictionary).duplicate(true)
	var reusable_metadata_sources := (metadata.get("source_sha256", {}) as Dictionary).duplicate(true)
	assert_str(str(approved_review_sources.get("registry", ""))).is_equal("12554079eb14503f92f618c1d5957d05834a2b00226f7a6d0de1a396f095eb62")
	# Candidate provenance binds the registry snapshot used during that review;
	# later approved shipping additions must not rewrite historical evidence.
	assert_str(str(reusable_metadata_sources.get("registry", ""))).is_equal("37a7fc8512a1c0488cd4e67cb542d6e9cfeb4f7f49a94efbc07d2874c1b7b908")
	approved_review_sources.erase("registry")
	reusable_metadata_sources.erase("registry")
	assert_dict(approved_review_sources).is_equal(reusable_metadata_sources)
	assert_int((approved_review_sources.get("candidate_001_tree", {}) as Dictionary).size()).is_equal(52)


func test_loader_rejects_missing_duplicate_or_unresolved_active_candidate_history() -> void:
	var missing_active := _canonical_registry()
	_smoke_shell_helmet(missing_active).erase("active_candidate_id")
	_assert_fixture_error(missing_active, "candidate history unit missing active_candidate_id")

	var duplicate_id := _canonical_registry()
	var duplicate_history := _smoke_shell_helmet(duplicate_id).get("candidate_history", []) as Array
	if duplicate_history.size() >= 2:
		(duplicate_history[1] as Dictionary)["candidate_id"] = (duplicate_history[0] as Dictionary).get("candidate_id", "")
	_assert_fixture_error(duplicate_id, "duplicate candidate_id")

	var unresolved_active := _canonical_registry()
	_smoke_shell_helmet(unresolved_active)["active_candidate_id"] = "candidate-999"
	_assert_fixture_error(unresolved_active, "active_candidate_id must resolve exactly once")

	var multiple_review := _canonical_registry()
	var multiple_review_history := _smoke_shell_helmet(multiple_review).get("candidate_history", []) as Array
	if not multiple_review_history.is_empty():
		(multiple_review_history[0] as Dictionary)["decision"] = "review"
	_assert_fixture_error(multiple_review, "candidate history must contain exactly one review decision")


func test_loader_rejects_incomplete_revision_history_and_active_report_roles() -> void:
	var missing_revision_artifacts := _canonical_registry()
	_candidate_history_entry(_smoke_shell_helmet(missing_revision_artifacts), "candidate-001").erase("artifacts")
	_assert_fixture_error(missing_revision_artifacts, "revision_requested candidate missing artifacts")

	var missing_revision_reasons := _canonical_registry()
	_candidate_history_entry(_smoke_shell_helmet(missing_revision_reasons), "candidate-001")["reasons"] = []
	_assert_fixture_error(missing_revision_reasons, "revision_requested candidate missing reasons")

	for role in ["pixel_qa_report", "harmony_report"]:
		var missing_report := _canonical_registry()
		_remove_candidate_role(_candidate_history_entry(_smoke_shell_helmet(missing_report), "candidate-002"), role)
		_assert_fixture_error(missing_report, "active candidate missing required artifact role: %s" % role)


func test_loader_requires_exact_candidate_role_sets_and_no_legacy_single_candidate_fields() -> void:
	for role in ["composite_frame", "harmony_overlay", "harmony_actual_size", "visual_rubric"]:
		var missing_active_role := _canonical_registry()
		_remove_candidate_role(_candidate_history_entry(_smoke_shell_helmet(missing_active_role), "candidate-002"), role)
		_assert_fixture_error(missing_active_role, "candidate candidate-002 artifact roles must match exact required set")

	var missing_revision_role := _canonical_registry()
	_remove_candidate_role(_candidate_history_entry(_smoke_shell_helmet(missing_revision_role), "candidate-001"), "icon_request")
	_assert_fixture_error(missing_revision_role, "candidate candidate-001 artifact roles must match exact required set")

	for candidate_id in ["candidate-001", "candidate-002"]:
		var unknown_role := _canonical_registry()
		var candidate := _candidate_history_entry(_smoke_shell_helmet(unknown_role), candidate_id)
		var unknown_artifact := _candidate_artifact(candidate, "icon").duplicate(true) as Dictionary
		unknown_artifact["role"] = "unknown_role"
		(candidate.get("artifacts", []) as Array).append(unknown_artifact)
		_assert_fixture_error(unknown_role, "candidate %s artifact roles must match exact required set" % candidate_id)

	for obsolete_field in ["candidate_id", "candidate_provenance", "candidate_artifacts"]:
		var legacy_field := _canonical_registry()
		_smoke_shell_helmet(legacy_field)[obsolete_field] = "obsolete"
		_assert_fixture_error(legacy_field, "candidate history unit must not contain obsolete field: %s" % obsolete_field)


func test_loader_requires_exact_candidate_source_and_revision_provenance() -> void:
	var missing_source_key := _registry_with_exact_source_provenance()
	(_candidate_history_entry(_smoke_shell_helmet(missing_source_key), "candidate-002")["source_sha256"] as Dictionary).erase("candidate_001_tree")
	_assert_fixture_error(missing_source_key, "active candidate source provenance must match exact generated metadata")

	var changed_source_hash := _registry_with_exact_source_provenance()
	(_candidate_history_entry(_smoke_shell_helmet(changed_source_hash), "candidate-002")["source_sha256"] as Dictionary)["niko_atlas"] = "0000000000000000000000000000000000000000000000000000000000000000"
	_assert_fixture_error(changed_source_hash, "active candidate source provenance must match exact generated metadata")

	var missing_tree_entry := _registry_with_exact_source_provenance()
	var source_tree := ((_candidate_history_entry(_smoke_shell_helmet(missing_tree_entry), "candidate-002")["source_sha256"] as Dictionary)["candidate_001_tree"] as Dictionary)
	source_tree.erase("requests/icon-request.json")
	_assert_fixture_error(missing_tree_entry, "active candidate source provenance must match exact generated metadata")

	var replacement_tree_entry := _registry_with_exact_source_provenance()
	var replacement_tree := ((_candidate_history_entry(_smoke_shell_helmet(replacement_tree_entry), "candidate-002")["source_sha256"] as Dictionary)["candidate_001_tree"] as Dictionary)
	replacement_tree.erase("requests/icon-request.json")
	replacement_tree["requests/unknown-request.json"] = "4a8a4e327ffedddc95324070b7bd5d20b68218f801632a2e1388da58ce708c79"
	_assert_fixture_error(replacement_tree_entry, "active candidate source provenance must match exact generated metadata")

	for malformed_roles in [[], ["icon_request"], ["appearance_request", "icon_request"], ["icon_request", "appearance_request", "extra"]]:
		var changed_revision_provenance := _canonical_registry()
		var revision_provenance := _candidate_history_entry(_smoke_shell_helmet(changed_revision_provenance), "candidate-001").get("provenance", {}) as Dictionary
		revision_provenance["request_artifact_roles"] = malformed_roles
		_assert_fixture_error(changed_revision_provenance, "candidate-001 provenance must match preserved canonical record")
	for prompt_version in ["", "gogobro-static-v2"]:
		var changed_prompt_provenance := _canonical_registry()
		var prompt_provenance := _candidate_history_entry(_smoke_shell_helmet(changed_prompt_provenance), "candidate-001").get("provenance", {}) as Dictionary
		prompt_provenance["prompt_version"] = prompt_version
		_assert_fixture_error(changed_prompt_provenance, "candidate-001 provenance must match preserved canonical record")

	var unexpected_revision_provenance := _canonical_registry()
	(_candidate_history_entry(_smoke_shell_helmet(unexpected_revision_provenance), "candidate-001").get("provenance", {}) as Dictionary)["unexpected"] = true
	_assert_fixture_error(unexpected_revision_provenance, "candidate-001 provenance must match preserved canonical record")


func test_loader_rejects_malformed_or_unsafe_candidate_history_artifacts() -> void:
	var malformed_hash := _canonical_registry()
	_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(malformed_hash), "candidate-002"), "icon")["sha256"] = "bad-hash"
	_assert_fixture_error(malformed_hash, "candidate artifact icon has invalid sha256")

	var malformed_bytes := _canonical_registry()
	_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(malformed_bytes), "candidate-002"), "icon")["bytes"] = 0
	_assert_fixture_error(malformed_bytes, "candidate artifact has invalid byte size")

	var malformed_output_spec := _canonical_registry()
	var icon_spec := _candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(malformed_output_spec), "candidate-002"), "icon").get("output_spec", {}) as Dictionary
	icon_spec["width"] = 128
	_assert_fixture_error(malformed_output_spec, "candidate artifact icon output_spec must match required specification")

	var unexpected_output_spec_field := _canonical_registry()
	var unexpected_icon_spec := _candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(unexpected_output_spec_field), "candidate-002"), "icon").get("output_spec", {}) as Dictionary
	unexpected_icon_spec["unexpected"] = true
	_assert_fixture_error(unexpected_output_spec_field, "candidate artifact icon output_spec must match required specification")

	var runtime_path := _canonical_registry()
	_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(runtime_path), "candidate-002"), "icon")["path"] = "res://game/assets/items/smoke_shell_helmet.png"
	_assert_fixture_error(runtime_path, "candidate artifact icon path must stay outside runtime res://")

	var curated_path := _canonical_registry()
	_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(curated_path), "candidate-002"), "icon")["path"] = "workspace://GOGOBRO_ASSET_INBOX/curated/smoke-shell-helmet.png"
	_assert_fixture_error(curated_path, "candidate artifact icon path must not contain /curated/")

	for unsafe_path in [
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/../candidate-001/cleaned/smoke-shell-helmet-appearance-128.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/./harmony-overlay.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002//derived/icon-256.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/icon-256.png?raw=1",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/icon-256.png#fragment",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/%2e%2e/candidate-001/icon.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/%2Fgame/assets/x.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived%5cicon.png",
		"workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-001/icon/run/frames/icon/frame-0.png",
		"workspace://GOGOBRO_ASSET_INBOX/../../game/assets/x.png",
	]:
		var escaped_path := _canonical_registry()
		_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(escaped_path), "candidate-002"), "icon")["path"] = unsafe_path
		_assert_fixture_error(escaped_path, "candidate artifact icon path must stay within exact candidate root")

	var exact_icon_path := "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/derived/icon-256.png"
	for whitespace_wrapped_path in [
		" " + exact_icon_path,
		exact_icon_path + " ",
		"\t" + exact_icon_path,
		exact_icon_path + "\t",
		"\n" + exact_icon_path,
		exact_icon_path + "\r\n",
	]:
		var whitespace_path := _canonical_registry()
		_candidate_artifact(_candidate_history_entry(_smoke_shell_helmet(whitespace_path), "candidate-002"), "icon")["path"] = whitespace_wrapped_path
		_assert_fixture_error(whitespace_path, "candidate artifact icon path must stay within exact candidate root")

	var canonical_json := FileAccess.get_file_as_string(CANONICAL_PATH)
	for malformed_byte_literal in ["1.0", "1.5", "1e3", "0", "-1", "\"1\"", "null"]:
		var malformed_bytes_json := canonical_json.replace("\"bytes\":1968", "\"bytes\":%s" % malformed_byte_literal)
		_assert_raw_fixture_error(malformed_bytes_json, "invalid byte size")
	for escaped_bytes_key in ["\\u0062ytes", "b\\u0079tes", "\\u0062\\u0079\\u0074\\u0065\\u0073"]:
		for malformed_byte_literal in ["1.0", "1.5", "1e3", "0", "-1", "\"1\"", "null"]:
			var escaped_malformed_bytes_json := canonical_json.replace("\"bytes\":3030", "\"%s\":%s" % [escaped_bytes_key, malformed_byte_literal])
			_assert_raw_fixture_error(escaped_malformed_bytes_json, "invalid byte size")
	var valid_escaped_bytes_json := canonical_json.replace("\"bytes\":3030", "\"\\u0062ytes\":3030")
	_assert_raw_fixture_has_no_errors(valid_escaped_bytes_json)

	var duplicate_role := _canonical_registry()
	var active_candidate := _candidate_history_entry(_smoke_shell_helmet(duplicate_role), "candidate-002")
	var duplicate_icon := _candidate_artifact(active_candidate, "icon").duplicate(true) as Dictionary
	(active_candidate.get("artifacts", []) as Array).append(duplicate_icon)
	_assert_fixture_error(duplicate_role, "duplicate candidate artifact role: icon")


func test_loader_keeps_harmony_verdict_mechanical_after_human_approval() -> void:
	var approved_harmony := _canonical_registry()
	_candidate_history_entry(_smoke_shell_helmet(approved_harmony), "candidate-002")["harmony_verdict"] = "approved"
	_assert_fixture_error(approved_harmony, "active candidate harmony_verdict must be harmony_pass or review")


func test_loader_rejects_forged_or_non_append_only_human_approval_transitions() -> void:
	var no_prior_review := _canonical_registry()
	_candidate_history_entry(_smoke_shell_helmet(no_prior_review), "candidate-002")["decision"] = "approved"
	_assert_fixture_error(no_prior_review, "approved candidate must preserve prior review decision")

	var non_active_candidate := _canonical_registry()
	_approval_event(_smoke_shell_helmet(non_active_candidate))["candidate_id"] = "candidate-001"
	_assert_fixture_error(non_active_candidate, "approval decision must target active_candidate_id")

	var multiple_approved := _canonical_registry()
	var approval_history := _smoke_shell_helmet(multiple_approved).get("approval_history", []) as Array
	approval_history.append((approval_history[0] as Dictionary).duplicate(true))
	_assert_fixture_error(multiple_approved, "approved unit must contain exactly one approval decision")

	for forged_status in ["integrated", "qa_passed"]:
		var forged := _canonical_registry()
		_smoke_shell_helmet(forged)["approval_status"] = forged_status
		_assert_fixture_error(forged, "candidate history unit cannot advance directly to approval_status: %s" % forged_status)

	var removed_provenance := _canonical_registry()
	var stripped_helmet := _smoke_shell_helmet(removed_provenance)
	stripped_helmet.erase("active_candidate_id")
	stripped_helmet.erase("candidate_history")
	stripped_helmet.erase("approval_history")
	_assert_fixture_error(removed_provenance, "candidate history unit missing candidate_history")

	var review_with_approval := _canonical_registry()
	_smoke_shell_helmet(review_with_approval)["approval_status"] = "review"
	_assert_fixture_error(review_with_approval, "review unit must not contain approval_history")


func test_loader_requires_exact_human_approval_evidence() -> void:
	var missing_history := _canonical_registry()
	_smoke_shell_helmet(missing_history).erase("approval_history")
	_assert_fixture_error(missing_history, "approved unit missing approval_history")

	var wrong_decision := _canonical_registry()
	_approval_event(_smoke_shell_helmet(wrong_decision))["decision"] = "integrated"
	_assert_fixture_error(wrong_decision, "approval decision must be approved")

	var wrong_authority := _canonical_registry()
	_approval_event(_smoke_shell_helmet(wrong_authority))["authority"] = "assistant_self_approval"
	_assert_fixture_error(wrong_authority, "approval decision must cite explicit user authority")

	for invalid_timestamp in ["2026-08-24", "2026-08-24T12:04:47+08:00", "2026-99-99T99:99:99Z"]:
		var malformed_time := _canonical_registry()
		_approval_event(_smoke_shell_helmet(malformed_time))["approved_at_utc"] = invalid_timestamp
		_assert_fixture_error(malformed_time, "approval decision approved_at_utc must be RFC 3339 UTC")

	var extra_claim := _canonical_registry()
	_approval_event(_smoke_shell_helmet(extra_claim))["integrated"] = true
	_assert_fixture_error(extra_claim, "approval decision fields must match exact schema")


func _canonical_registry() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANONICAL_PATH))
	var registry := JSON.parse_string(JSON.stringify(parsed)) as Dictionary
	_normalize_fixture_byte_sizes(registry)
	return registry


func _candidate_metadata() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_002_METADATA_PATH)) as Dictionary


func _registry_with_exact_source_provenance() -> Dictionary:
	var registry := _canonical_registry()
	var metadata := _candidate_metadata()
	_candidate_history_entry(_smoke_shell_helmet(registry), "candidate-002")["source_sha256"] = (metadata.get("source_sha256", {}) as Dictionary).duplicate(true)
	return registry


func _normalize_fixture_byte_sizes(registry: Dictionary) -> void:
	for unit in registry.get("units", []) as Array:
		for candidate in (unit as Dictionary).get("candidate_history", []) as Array:
			for artifact in (candidate as Dictionary).get("artifacts", []) as Array:
				if (artifact as Dictionary).get("bytes") is float:
					(artifact as Dictionary)["bytes"] = int((artifact as Dictionary).get("bytes"))


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


func _assert_raw_fixture_error(raw_json: String, expected_error: String) -> void:
	var fixture_path := "user://static_asset_registry_fixture_%s.json" % Time.get_ticks_usec()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(raw_json)
	file.close()
	var result := Registry.load_registry(fixture_path)
	assert_str("\n".join(result.get("errors", PackedStringArray()) as PackedStringArray)).contains(expected_error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


func _assert_raw_fixture_has_no_errors(raw_json: String) -> void:
	var fixture_path := "user://static_asset_registry_fixture_%s.json" % Time.get_ticks_usec()
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(raw_json)
	file.close()
	var result := Registry.load_registry(fixture_path)
	assert_int((result.get("errors", PackedStringArray()) as PackedStringArray).size()).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))


func _first_unit_in_category(registry: Dictionary, category: String) -> Dictionary:
	for unit in registry.get("units", []) as Array:
		if (unit as Dictionary).get("category", "") == category:
			return unit as Dictionary
	return {}


func _unit_by_asset_id(registry: Dictionary, asset_id: String) -> Dictionary:
	for unit_variant in registry.get("units", []) as Array:
		var unit := unit_variant as Dictionary
		if unit != null and unit.get("asset_id") == asset_id:
			return unit
	return {}


func _smoke_shell_helmet(registry: Dictionary) -> Dictionary:
	for unit in registry.get("units", []) as Array:
		if (unit as Dictionary).get("asset_id", "") == "smoke_shell_helmet":
			return unit as Dictionary
	return {}


func _candidate_history_entry(unit: Dictionary, candidate_id: String) -> Dictionary:
	for candidate in unit.get("candidate_history", []) as Array:
		if (candidate as Dictionary).get("candidate_id", "") == candidate_id:
			return candidate as Dictionary
	return {}


func _approval_event(unit: Dictionary) -> Dictionary:
	var history := unit.get("approval_history", []) as Array
	return history[0] as Dictionary if not history.is_empty() else {}


func _candidate_artifact(candidate: Dictionary, role: String) -> Dictionary:
	for artifact in candidate.get("artifacts", []) as Array:
		if (artifact as Dictionary).get("role", "") == role:
			return artifact as Dictionary
	return {}


func _remove_candidate_role(candidate: Dictionary, role: String) -> void:
	var artifacts := candidate.get("artifacts", []) as Array
	for index in artifacts.size():
		if (artifacts[index] as Dictionary).get("role", "") == role:
			artifacts.remove_at(index)
			return


func _approval_status_count(registry: Dictionary, approval_status: String) -> int:
	var count := 0
	for unit in registry.get("units", []) as Array:
		if (unit as Dictionary).get("approval_status", "") == approval_status:
			count += 1
	return count


func _assert_output_spec(actual: Dictionary, expected: Dictionary) -> void:
	assert_int(actual.size()).is_equal(expected.size())
	for field in expected:
		var expected_value: Variant = expected[field]
		if expected_value is bool:
			assert_bool(bool(actual.get(field, false))).is_equal(expected_value)
		elif expected_value is int:
			assert_int(int(actual.get(field, 0))).is_equal(expected_value)
		else:
			assert_str(str(actual.get(field, ""))).is_equal(str(expected_value))
