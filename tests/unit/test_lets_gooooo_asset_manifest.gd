extends GdUnitTestSuite


const MANIFEST_PATH := "res://content_packs/skins/lets_gooooo/asset_manifest.json"
const ASSET_ROOT := "res://content_packs/skins/lets_gooooo/assets/"
const VALIDATOR := preload("res://tools/assets/validate_skin_assets.gd")
const VALIDATOR_FIXTURE_ROOT := "user://tests/lets_gooooo_asset_validator"
const CURATED_PASSIVE_COLLECTION := "sprite-gen-curated-passives-2026-08-18"
const REQUIRED_PASSIVE_IDS := [
	"passive.arc_lens",
	"passive.bargain_chip",
	"passive.battle_rhythm",
	"passive.blood_filter",
	"passive.blood_vial",
	"passive.butterfly",
	"passive.cape",
	"passive.cinder_seed",
	"passive.close_quarters_manual",
	"passive.coffee",
	"passive.crack",
	"passive.dash_blades",
	"passive.dash_charge",
	"passive.drone_uplink",
	"passive.echo_round",
	"passive.ember_reservoir",
	"passive.evasion_mesh",
	"passive.flag",
	"passive.fortune_charm",
	"passive.frost_capacitor",
	"passive.golden_seed",
	"passive.guardian_core",
	"passive.harvest_bell",
	"passive.helmet",
	"passive.hunter_mark",
	"passive.interest_coil",
	"passive.iron_bark",
	"passive.knight_helmet",
	"passive.last_breath",
	"passive.leech",
	"passive.lucky_token",
	"passive.magazine",
	"passive.map",
	"passive.market_map",
	"passive.medic_patch",
	"passive.merchant_badge",
	"passive.mighty_sword",
	"passive.missile",
	"passive.muscle",
	"passive.panic_guard",
	"passive.plant",
	"passive.power_ball",
	"passive.prospector_eye",
	"passive.rage",
	"passive.rapid_loader",
	"passive.recycler_stamp",
	"passive.repair_gel",
	"passive.round_hat",
	"passive.salvage_hook",
	"passive.scrap_ledger",
	"passive.second_skin",
	"passive.sharpshooter_lens",
	"passive.shock_padding",
	"passive.storm_conductor",
	"passive.telescope",
	"passive.thorn_mesh",
	"passive.toxic_sludge",
	"passive.turret_gears",
	"passive.vest",
	"passive.volatile_core",
]
const FORBIDDEN_TOKENS := [
	"/prompt/",
	"/prompts/",
	"/candidate/",
	"/candidates/",
	"/review/",
	"/identity/",
	".mp4",
	".ds_store",
]


func after_test() -> void:
	_remove_tree(VALIDATOR_FIXTURE_ROOT)


func test_manifest_tracks_only_approved_shipping_assets() -> void:
	assert_bool(FileAccess.file_exists(MANIFEST_PATH)).is_true()
	var manifest := _load_manifest()
	assert_str(String(manifest.get("kind", ""))).is_equal("lets-gooooo-static-assets")
	assert_int(int(manifest.get("schema_version", 0))).is_equal(1)
	assert_int(int(manifest.get("logical_canvas", 0))).is_equal(64)
	assert_int(int(manifest.get("output_canvas", 0))).is_equal(256)
	assert_int(int(manifest.get("nearest_scale", 0))).is_equal(4)
	var assets: Array = manifest.get("assets", []) as Array
	assert_int(assets.size()).is_greater_equal(100)
	var ids := {}
	var categories := {}
	for raw_entry: Variant in assets:
		var entry := raw_entry as Dictionary
		var asset_id := String(entry.get("id", ""))
		var path := String(entry.get("path", ""))
		assert_bool(asset_id.is_empty()).is_false()
		assert_bool(ids.has(asset_id)).is_false()
		ids[asset_id] = true
		assert_bool(path.begins_with(ASSET_ROOT)).is_true()
		assert_bool(FileAccess.file_exists(path)).is_true()
		assert_str(FileAccess.get_sha256(path)).is_equal(String(entry.get("sha256", "")))
		assert_bool(bool(entry.get("shipping_allowed", false))).is_true()
		assert_str(String((entry.get("approval", {}) as Dictionary).get("status", ""))).is_equal(
			"approved"
		)
		assert_str(String((entry.get("rights", {}) as Dictionary).get("status", ""))).is_equal(
			"cleared"
		)
		assert_bool((entry.get("source", {}) as Dictionary).has("sha256")).is_true()
		for forbidden: String in FORBIDDEN_TOKENS:
			assert_bool(path.to_lower().contains(forbidden)).is_false()
		var category := String(entry.get("category", ""))
		categories[category] = int(categories.get(category, 0)) + 1
	assert_int(int(categories.get("weapon_icon", 0))).is_greater_equal(24)
	assert_int(int(categories.get("passive_icon", 0))).is_equal(60)
	assert_int(int(categories.get("scene_background", 0))).is_greater_equal(1)
	assert_int(int(categories.get("scene_floor", 0))).is_greater_equal(1)
	assert_int(int(categories.get("pickup_world", 0))).is_greater_equal(3)
	assert_int(int(categories.get("prop_world", 0))).is_greater_equal(3)
	assert_int(int(categories.get("ally_world", 0))).is_greater_equal(2)
	assert_int(int(categories.get("ui_logo", 0))).is_greater_equal(1)
	assert_int(int(categories.get("ui_app_icon", 0))).is_greater_equal(1)
	assert_int(int(categories.get("projectile_world", 0))).is_greater_equal(4)


func test_weapon_assets_have_initial_runtime_anchors() -> void:
	var required_weapon_ids := [
		"weapon.carbine",
		"weapon.shotgun",
		"weapon.railbow",
		"weapon.laser",
		"weapon.pistol",
		"weapon.revolver",
		"weapon.smg",
		"weapon.shrapnel_launcher",
		"weapon.needler",
		"weapon.boomerang",
		"weapon.drone_beacon",
		"weapon.ember_staff",
		"weapon.axe",
		"weapon.chainsaw",
		"weapon.mace",
		"weapon.punch",
		"weapon.sword",
		"weapon.wand",
		"weapon.spear",
		"weapon.cleaver",
		"weapon.turret_kit",
		"weapon.void_prism",
		"weapon.storm_coil",
		"weapon.frost_orb",
	]
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	for asset_id: String in required_weapon_ids:
		assert_bool(by_id.has(asset_id)).is_true()
		var anchors := (by_id[asset_id] as Dictionary).get("anchors", {}) as Dictionary
		assert_str(String(anchors.get("calibration_status", ""))).is_equal(
			"runtime_calibrated_2026_08_19"
		)
		assert_bool(anchors.has("pivot_logical")).is_true()
		assert_float(float(anchors.get("world_scale", 0.0))).is_between(0.12, 0.35)
		assert_int((anchors.get("mount_position_world", []) as Array).size()).is_equal(2)
		if asset_id in [
			"weapon.ember_staff",
			"weapon.void_prism",
			"weapon.storm_coil",
			"weapon.frost_orb",
		]:
			assert_bool(anchors.has("throw_origin_logical")).is_true()
		elif asset_id == "weapon.turret_kit":
			assert_bool(anchors.has("placement_origin_logical")).is_true()
		elif asset_id in [
			"weapon.axe",
			"weapon.chainsaw",
			"weapon.mace",
			"weapon.punch",
			"weapon.sword",
			"weapon.spear",
			"weapon.cleaver",
		]:
			assert_bool(anchors.has("strike_origin_logical")).is_true()
		else:
			assert_bool(anchors.has("muzzle_logical")).is_true()


func test_curated_generated_weapons_record_pipeline_and_visual_approval() -> void:
	var curated_weapon_ids := [
		"weapon.axe",
		"weapon.chainsaw",
		"weapon.mace",
		"weapon.punch",
		"weapon.sword",
		"weapon.wand",
		"weapon.spear",
		"weapon.cleaver",
		"weapon.turret_kit",
		"weapon.void_prism",
		"weapon.storm_coil",
		"weapon.frost_orb",
	]
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	for asset_id: String in curated_weapon_ids:
		assert_bool(by_id.has(asset_id)).is_true()
		var entry := by_id[asset_id] as Dictionary
		var source := entry.get("source", {}) as Dictionary
		assert_str(String(source.get("kind", ""))).is_equal("generated_and_curated_art")
		assert_array(source.get("pipeline", []) as Array).is_equal(
			["built_in_image_gen", "sprite_gen_curation"]
		)
		assert_str(String((entry.get("approval", {}) as Dictionary).get("basis", ""))).is_equal(
			"agent_visual_qa"
		)
		assert_bool(bool(entry.get("shipping_allowed", false))).is_true()


func test_complete_passive_art_matrix_has_exact_ids_and_curated_provenance() -> void:
	var passive_ids := PackedStringArray()
	var curated_count := 0
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		if String(entry.get("category", "")) != "passive_icon":
			continue
		var asset_id := String(entry.get("id", ""))
		passive_ids.append(asset_id)
		assert_str(String(entry.get("path", ""))).ends_with(
			"/passives/%s.png" % asset_id.trim_prefix("passive.")
		)
		var source := entry.get("source", {}) as Dictionary
		if String(source.get("collection", "")) != CURATED_PASSIVE_COLLECTION:
			continue
		curated_count += 1
		assert_array(source.get("pipeline", []) as Array).is_equal(
			["built_in_image_gen", "sprite_gen_curation"]
		)
		assert_str(String(source.get("selected_candidate_sha256", ""))).is_equal(
			String(source.get("sha256", ""))
		)
		assert_int(String(source.get("raw_sheet_sha256", "")).length()).is_equal(64)
		var curation := entry.get("curation", {}) as Dictionary
		assert_int(String(curation.get("sha256", "")).length()).is_equal(64)
		assert_str(String(curation.get("sha256", ""))).is_equal(String(entry.get("sha256", "")))
		assert_int(String(curation.get("selection_sha256", "")).length()).is_equal(64)
		assert_int(String(curation.get("qa_sha256", "")).length()).is_equal(64)
		assert_str(String((entry.get("approval", {}) as Dictionary).get("basis", ""))).is_equal(
			"agent_visual_qa"
		)
	passive_ids.sort()
	assert_array(passive_ids).contains_exactly(REQUIRED_PASSIVE_IDS)
	assert_int(curated_count).is_equal(37)


func test_title_background_is_a_lossless_widescreen_generated_asset() -> void:
	var background: Dictionary = {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		if String(entry.get("id", "")) == "scene.title_background":
			background = entry
			break
	assert_bool(background.is_empty()).is_false()
	assert_str(String(background.get("category", ""))).is_equal("scene_background")
	assert_array(background.get("uses", []) as Array).contains(["scene.background"])
	var source := background.get("source", {}) as Dictionary
	assert_str(String(source.get("kind", ""))).is_equal("generated_art")
	assert_array(source.get("pipeline", []) as Array).is_equal(["built_in_image_gen"])
	assert_str(String(source.get("sha256", ""))).is_equal(String(background.get("sha256", "")))
	var normalization := background.get("normalization", {}) as Dictionary
	assert_str(String(normalization.get("mode", ""))).is_equal("lossless_copy")
	var image := Image.new()
	assert_int(
		image.load_png_from_buffer(FileAccess.get_file_as_bytes(String(background.get("path", ""))))
	).is_equal(OK)
	assert_int(image.get_width()).is_greater_equal(1280)
	assert_int(image.get_height()).is_greater_equal(720)
	assert_float(float(image.get_width()) / float(image.get_height())).is_between(1.7, 1.82)


func test_arena_floor_is_a_lossless_square_generated_asset_with_nearest_sampling() -> void:
	var floor_asset: Dictionary = {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		if String(entry.get("id", "")) == "scene.arena_floor":
			floor_asset = entry
			break
	assert_bool(floor_asset.is_empty()).is_false()
	assert_str(String(floor_asset.get("category", ""))).is_equal("scene_floor")
	assert_array(floor_asset.get("uses", []) as Array).contains(["scene.floor"])
	assert_array(floor_asset.get("uses", []) as Array).contains(["scene.background"])
	assert_str(String(floor_asset.get("sampling", ""))).is_equal("nearest")
	var source := floor_asset.get("source", {}) as Dictionary
	assert_str(String(source.get("kind", ""))).is_equal("generated_art")
	assert_array(source.get("pipeline", []) as Array).is_equal(["built_in_image_gen"])
	assert_str(String(source.get("sha256", ""))).is_equal(String(floor_asset.get("sha256", "")))
	var image := Image.new()
	assert_int(
		image.load_png_from_buffer(FileAccess.get_file_as_bytes(String(floor_asset.get("path", ""))))
	).is_equal(OK)
	assert_int(image.get_width()).is_greater_equal(1024)
	assert_int(image.get_width()).is_equal(image.get_height())


func test_curated_world_assets_have_semantic_uses_and_initial_anchors() -> void:
	var expected := {
		"prop.supply_crate": "prop.world",
		"pickup.material": "pickup.world",
		"pickup.heal": "pickup.world",
		"pickup.chest": "pickup.world",
		"prop.weapon_rack": "prop.world",
		"ally.turret": "ally.world",
		"ally.drone": "ally.world",
		"prop.hazard_beacon": "prop.world",
	}
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	for asset_id: String in expected:
		assert_bool(by_id.has(asset_id)).is_true()
		var entry := by_id[asset_id] as Dictionary
		assert_array(entry.get("uses", []) as Array).contains([expected[asset_id]])
		var source := entry.get("source", {}) as Dictionary
		var normalization := entry.get("normalization", {}) as Dictionary
		var expected_pipeline := (
			[
				"built_in_image_gen",
				"sprite_gen_component_row",
				"sprite_gen_pixel_unfake",
				"sprite_gen_curation",
			]
			if String(normalization.get("mode", "")) == "sprite_gen_pixel_unfake_curated"
			else ["built_in_image_gen", "sprite_gen_curation"]
		)
		assert_array(source.get("pipeline", []) as Array).is_equal(expected_pipeline)
		var anchors := entry.get("anchors", {}) as Dictionary
		assert_bool(anchors.has("pivot_logical")).is_true()
		assert_bool(anchors.has("ground_origin_logical")).is_true()


func test_curated_projectiles_have_center_anchors_and_shipping_provenance() -> void:
	var expected_paths := {
		"projectile.pistol": "projectiles/pistol.png",
		"projectile.rifle": "projectiles/rifle.png",
		"projectile.sniper": "projectiles/sniper.png",
		"projectile.enemy": "projectiles/enemy.png",
	}
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	for asset_id: String in expected_paths:
		assert_bool(by_id.has(asset_id)).is_true()
		var entry := by_id[asset_id] as Dictionary
		assert_str(String(entry.get("category", ""))).is_equal("projectile_world")
		assert_str(String(entry.get("path", ""))).ends_with(String(expected_paths[asset_id]))
		assert_array(entry.get("uses", []) as Array).contains(["projectile.world"])
		assert_bool(bool(entry.get("shipping_allowed", false))).is_true()
		var source := entry.get("source", {}) as Dictionary
		assert_array(source.get("pipeline", []) as Array).is_equal(
			["built_in_image_gen", "sprite_gen_curation"]
		)
		var anchors := entry.get("anchors", {}) as Dictionary
		assert_bool(anchors.has("center_logical")).is_true()
		assert_array(anchors.get("center_logical", []) as Array).is_equal(
			anchors.get("pivot_logical", []) as Array
		)


func test_original_logo_is_manifested_and_contains_no_external_payloads() -> void:
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	assert_bool(by_id.has("ui.logo")).is_true()
	var entry := by_id["ui.logo"] as Dictionary
	assert_array(entry.get("uses", []) as Array).contains(["ui.logo"])
	assert_str(String((entry.get("source", {}) as Dictionary).get("kind", ""))).is_equal(
		"original_code_native_vector"
	)
	var svg := FileAccess.get_file_as_string(String(entry.get("path", ""))).to_lower()
	assert_str(svg).contains("<svg")
	assert_str(svg).not_contains("<script")
	assert_str(svg).not_contains("<image")
	assert_str(svg).not_contains("xlink:href")


func test_user_selected_chicken_is_the_curated_pixel_shipping_app_icon() -> void:
	var by_id := {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		by_id[String(entry.get("id", ""))] = entry
	assert_bool(by_id.has("ui.app_icon")).is_true()
	var entry := by_id["ui.app_icon"] as Dictionary
	assert_str(String(entry.get("path", ""))).ends_with("/assets/ui/app_icon.png")
	assert_str(String(entry.get("format", ""))).is_equal("png")
	assert_array(entry.get("uses", []) as Array).contains(["ui.app_icon"])
	assert_str(String((entry.get("source", {}) as Dictionary).get("kind", ""))).is_equal(
		"user_provided_art"
	)
	assert_str(String((entry.get("approval", {}) as Dictionary).get("basis", ""))).is_equal(
		"user_explicit_selection"
	)
	var normalization := entry.get("normalization", {}) as Dictionary
	assert_str(String(normalization.get("mode", ""))).is_equal(
		"sprite_gen_pixel_unfake_curated"
	)
	assert_array(normalization.get("logical_canvas", []) as Array).contains_exactly([64.0, 64.0])
	assert_int(int(normalization.get("nearest_scale", 0))).is_equal(4)
	assert_float(float(normalization.get("edge_dark_fraction", 0.0))).is_greater_equal(0.85)
	assert_str(FileAccess.get_sha256(String(entry.get("path", "")))).is_equal(
		"677d1fc236182d09d879085b047b91eff996ac4565584d025ebb7c62218cdd92"
	)


func test_pickup_material_is_a_single_warm_gold_shard_with_hard_sparse_glints() -> void:
	var material: Dictionary = {}
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		if String(entry.get("id", "")) == "pickup.material":
			material = entry
			break
	assert_bool(material.is_empty()).is_false()
	var source := material.get("source", {}) as Dictionary
	assert_str(String(source.get("asset_ref", ""))).is_equal(
		"pickup-material-gold-shard-v2"
	)
	assert_array(source.get("pipeline", []) as Array).contains_exactly(
		[
			"built_in_image_gen",
			"sprite_gen_component_row",
			"sprite_gen_pixel_unfake",
			"sprite_gen_curation",
		]
	)
	var normalization := material.get("normalization", {}) as Dictionary
	assert_str(String(normalization.get("mode", ""))).is_equal(
		"sprite_gen_pixel_unfake_curated"
	)
	var declared_bbox := normalization.get("logical_bbox_xywh", []) as Array
	assert_int(declared_bbox.size()).is_equal(4)
	assert_int(int(declared_bbox[2])).is_between(44, 48)
	assert_int(int(declared_bbox[3])).is_between(28, 34)
	assert_float(float(declared_bbox[2]) * 30.0 / 64.0).is_between(20.5, 22.5)
	assert_int(int(declared_bbox[0])).is_greater_equal(6)
	assert_int(int(declared_bbox[1])).is_greater_equal(6)
	assert_int(int(declared_bbox[0]) + int(declared_bbox[2])).is_less_equal(58)
	assert_int(int(declared_bbox[1]) + int(declared_bbox[3])).is_less_equal(58)
	var image := Image.new()
	assert_int(
		image.load_png_from_buffer(
			FileAccess.get_file_as_bytes(String(material.get("path", "")))
		)
	).is_equal(OK)
	image.convert(Image.FORMAT_RGBA8)
	image.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var opaque := 0
	var warm_gold := 0
	var neutral := 0
	var min_x := 64
	var min_y := 64
	var max_x := -1
	var max_y := -1
	for y: int in range(64):
		for x: int in range(64):
			var pixel := image.get_pixel(x, y)
			if pixel.a < 1.0:
				assert_bool(
					is_zero_approx(pixel.r)
					and is_zero_approx(pixel.g)
					and is_zero_approx(pixel.b)
				).is_true()
				continue
			opaque += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			if pixel.r >= 0.28 and pixel.r > pixel.g * 1.08 and pixel.g > pixel.b * 1.35:
				warm_gold += 1
			if absf(pixel.r - pixel.g) <= 0.06 and absf(pixel.g - pixel.b) <= 0.06:
				neutral += 1
	var bbox_width := max_x - min_x + 1
	var bbox_height := max_y - min_y + 1
	assert_int(opaque).is_between(600, 1000)
	assert_int(bbox_width).is_between(44, 48)
	assert_int(bbox_height).is_between(28, 34)
	assert_float(float(bbox_width) * 30.0 / 64.0).is_between(20.5, 22.5)
	assert_int(min_x).is_greater_equal(6)
	assert_int(min_y).is_greater_equal(6)
	assert_int(max_x).is_less_equal(57)
	assert_int(max_y).is_less_equal(57)
	assert_float(float(warm_gold) / float(opaque)).is_greater_equal(0.65)
	assert_float(float(neutral) / float(opaque)).is_less_equal(0.10)


func test_pngs_are_true_64_pixel_logical_assets_upscaled_nearest_to_256() -> void:
	for raw_entry: Variant in (_load_manifest().get("assets", []) as Array):
		var entry := raw_entry as Dictionary
		if String(entry.get("category", "")) not in [
			"weapon_icon",
			"passive_icon",
			"pickup_world",
			"prop_world",
			"ally_world",
			"projectile_world",
		]:
			continue
		var image := Image.new()
		assert_int(
			image.load_png_from_buffer(
				FileAccess.get_file_as_bytes(String(entry.get("path", "")))
			)
		).is_equal(OK)
		assert_int(image.get_width()).is_equal(256)
		assert_int(image.get_height()).is_equal(256)
		image.convert(Image.FORMAT_RGBA8)
		var logical := image.duplicate()
		logical.resize(64, 64, Image.INTERPOLATE_NEAREST)
		var roundtrip := logical.duplicate()
		roundtrip.resize(256, 256, Image.INTERPOLATE_NEAREST)
		assert_array(roundtrip.get_data()).is_equal(image.get_data())
		for logical_y: int in range(64):
			for logical_x: int in range(64):
				var expected: Color = logical.get_pixel(logical_x, logical_y)
				assert_bool(expected.a == 0.0 or expected.a == 1.0).is_true()


func test_release_validator_accepts_the_curated_gold_shard_pipeline() -> void:
	var report := "\n".join(
		VALIDATOR.validate_skin_root("res://content_packs/skins/lets_gooooo")
	)
	assert_str(report).is_empty()


func test_release_validator_rejects_unapproved_review_artifacts() -> void:
	_remove_tree(VALIDATOR_FIXTURE_ROOT)
	var approved_path := VALIDATOR_FIXTURE_ROOT.path_join("assets/passives/approved.png")
	var review_path := VALIDATOR_FIXTURE_ROOT.path_join(
		"assets/review/unselected-contact-sheet.png"
	)
	_write_fixture_png(approved_path)
	_write_fixture_png(review_path)
	var fixture_manifest := {
		"schema_version": 1,
		"kind": "lets-gooooo-static-assets",
		"logical_canvas": 64,
		"output_canvas": 256,
		"nearest_scale": 4,
		"assets": [
			{
				"id": "passive.fixture",
				"path": approved_path,
				"sha256": FileAccess.get_sha256(approved_path),
				"shipping_allowed": true,
				"approval": {"status": "approved"},
				"rights": {"status": "cleared"},
				"source": {
					"kind": "user_supplied_generated_art",
					"sha256": "0".repeat(64),
				},
			}
		],
	}
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(VALIDATOR_FIXTURE_ROOT)
	)
	var file := FileAccess.open(
		VALIDATOR_FIXTURE_ROOT.path_join("asset_manifest.json"),
		FileAccess.WRITE
	)
	file.store_string(JSON.stringify(fixture_manifest, "  ") + "\n")
	file.close()
	var report := "\n".join(VALIDATOR.validate_skin_root(VALIDATOR_FIXTURE_ROOT))
	assert_str(report).contains("Forbidden source/review artifact")
	assert_str(report).contains("not approved by asset_manifest.json")


func _load_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert_bool(parsed is Dictionary).is_true()
	return parsed as Dictionary


func _write_fixture_png(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(64, 64, 64, 64), Color(0.8, 0.2, 0.1, 1.0))
	assert_int(image.save_png(path)).is_equal(OK)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_remove_tree(entry_path)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(entry_path))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
