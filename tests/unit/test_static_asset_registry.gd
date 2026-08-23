extends GdUnitTestSuite


const Registry = preload("res://game/content/assets/static_asset_registry.gd")
const CANONICAL_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const CANDIDATE_002_METADATA_PATH := "E:/01_gobro/GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/candidate-metadata.json"


func test_canonical_registry_loads_seventy_five_planned_and_one_review_approval_unit() -> void:
	var result := Registry.load_registry(CANONICAL_PATH)
	var errors := result.get("errors", PackedStringArray()) as PackedStringArray
	var registry := result.get("registry", {}) as Dictionary
	assert_array(errors).is_empty()
	assert_int((registry.get("units", []) as Array).size()).is_equal(76)
	assert_int(_approval_status_count(registry, "planned")).is_equal(75)
	assert_int(_approval_status_count(registry, "review")).is_equal(1)
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
		var accepted_unit := _smoke_shell_helmet(accepted) if approval_status == "review" else (accepted["units"] as Array)[0] as Dictionary
		accepted_unit["approval_status"] = approval_status
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


func test_smoke_shell_helmet_review_record_has_exact_copy_and_candidate_provenance() -> void:
	var result := Registry.load_registry(CANONICAL_PATH)
	var helmet := _smoke_shell_helmet(result.get("registry", {}) as Dictionary)
	var localization := helmet.get("localization", {}) as Dictionary
	assert_str(str(helmet.get("approval_status", ""))).is_equal("review")
	assert_str(str(helmet.get("active_candidate_id", ""))).is_equal("candidate-002")
	assert_int((helmet.get("candidate_history", []) as Array).size()).is_equal(2)
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
		["anchors", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/appearance/anchors-walk-down.json", 1806, "c8bfe6231d40a3ab6643ec06dd7d34287a23729bf39094794b4c46a5c76b024a", {"format":"JSON","state":"walk_down","anchor_count":8}],
		["composite_frame", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/composite-frame-001.png", 3241, "7a03b64c3cdba6f0ce701f70ee91f30b61d5b7304a3a1e2ccab65f04e813d08c", {"format":"PNG","width":128,"height":128,"alpha":true}],
		["composite_atlas", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/composite-atlas-8x128.png", 9271, "ae2951fcc74e76eccb1e4dcb7bba8d9801c80b0bddcf3ecb9af29b4472c00db7", {"format":"PNG","width":1024,"height":128,"alpha":true}],
		["runtime_preview", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/runtime-size-1920x1080.png", 15371, "03dd0cbfa73f77f47dc3a900c54862a7060444fdf84763359829f046e670377b", {"format":"PNG","width":1920,"height":1080,"alpha":true}],
		["harmony_overlay", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-overlay.png", 9496, "9e736b02c4584ed8b42abdfe4bd6773e3323dc83d7d14ffeadd5f2fdbde19edf", {"format":"PNG","width":1024,"height":128,"alpha":true}],
		["harmony_actual_size", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-actual-size.png", 20018, "433d9ea7d9799b90d76f092bc1d44697b9eda2f6ab574ce8f7d9a2d2ba902a1f", {"format":"PNG","width":1920,"height":1080,"alpha":true}],
		["harmony_report", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/harmony-report.json", 1712, "0beadd99e85fbb022f9a4acf43e0c0f2f92bf8a566735b758143f399f0305b90", {"format":"JSON"}],
		["visual_rubric", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/visual-rubric.json", 1040, "1b1687fd7d06941384399076bac901798ec7da2291729fbc678c3fcfbe4573ee", {"format":"JSON"}],
		["pixel_qa_report", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/pixel-qa-report.json", 1638, "850784385759528e050ee8c07a933a26b6ce6dd18362a9a44fa545e9da99db83", {"format":"JSON"}],
		["approval_card", "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/smoke_shell_helmet/candidate-002/qa/approval-card.png", 158255, "339b3ce9a44b2ad823b781e6733086e88894f69cab85e0329a318843679c24f5", {"format":"PNG","width":1800,"height":1200,"alpha":true}],
	]:
		var artifact := _candidate_artifact(active_candidate, expected[0])
		assert_str(str(artifact.get("path", ""))).is_equal(expected[1])
		assert_int(int(artifact.get("bytes", 0))).is_equal(expected[2])
		assert_str(str(artifact.get("sha256", ""))).is_equal(expected[3])
		_assert_output_spec(artifact.get("output_spec", {}) as Dictionary, expected[4] as Dictionary)
	var metrics := active_candidate.get("metrics", {}) as Dictionary
	assert_float(float(metrics.get("max_feature_center_error_px", -1.0))).is_equal(0.4375)
	assert_float(float(metrics.get("max_protected_occlusion_ratio", -1.0))).is_equal(0.0)
	assert_float(float(metrics.get("max_residual_jitter_px", -1.0))).is_equal(0.0)
	assert_float(float(metrics.get("outer_width_ratio", -1.0))).is_equal(1.103448275862069)
	assert_int(int(metrics.get("visual_rubric_total", 0))).is_equal(10)
	assert_str(str(active_candidate.get("visual_rubric_sha256", ""))).is_equal("1b1687fd7d06941384399076bac901798ec7da2291729fbc678c3fcfbe4573ee")
	var fonts := active_candidate.get("font_provenance", {}) as Dictionary
	assert_str(str((fonts.get("regular", {}) as Dictionary).get("path", ""))).is_equal("C:\\Windows\\Fonts\\msyh.ttc")
	assert_str(str((fonts.get("regular", {}) as Dictionary).get("sha256", ""))).is_equal("d79c55e68b1131eea0cc1c47be4f572d964f28c682e143db2ad09c1e4cb07a3f")
	assert_str(str((fonts.get("bold", {}) as Dictionary).get("path", ""))).is_equal("C:\\Windows\\Fonts\\msyhbd.ttc")
	assert_str(str((fonts.get("bold", {}) as Dictionary).get("sha256", ""))).is_equal("4508821b3dffe01f0ef5e5326a3e60df705a44633858811f67b6982dce3f6ee6")
	var report_verdicts := active_candidate.get("report_verdicts", {}) as Dictionary
	assert_bool(bool(report_verdicts.get("pixel_qa_passed", false))).is_true()
	assert_str(str(report_verdicts.get("harmony", ""))).is_equal("harmony_pass")
	assert_dict(active_candidate.get("source_sha256", {}) as Dictionary).is_equal(metadata.get("source_sha256", {}) as Dictionary)
	assert_int(((active_candidate.get("source_sha256", {}) as Dictionary).get("candidate_001_tree", {}) as Dictionary).size()).is_equal(52)


func test_loader_rejects_missing_duplicate_or_unresolved_active_candidate_history() -> void:
	var missing_active := _canonical_registry()
	_smoke_shell_helmet(missing_active).erase("active_candidate_id")
	_assert_fixture_error(missing_active, "review unit missing active_candidate_id")

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


func test_loader_keeps_active_harmony_candidate_in_review() -> void:
	var approved_harmony := _canonical_registry()
	_candidate_history_entry(_smoke_shell_helmet(approved_harmony), "candidate-002")["harmony_verdict"] = "approved"
	_assert_fixture_error(approved_harmony, "active candidate harmony_verdict must be harmony_pass or review")

	var approved_unit := _canonical_registry()
	_smoke_shell_helmet(approved_unit)["approval_status"] = "approved"
	_assert_fixture_error(approved_unit, "candidate history unit approval_status must remain review")


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
