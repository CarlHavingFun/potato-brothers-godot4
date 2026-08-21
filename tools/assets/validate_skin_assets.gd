extends SceneTree


const MANIFEST_FILE := "asset_manifest.json"
const LOGICAL_CANVAS := 64
const OUTPUT_CANVAS := 256
const NEAREST_SCALE := 4
const CURATED_COLLECTION := "sprite-gen-curated-weapons-2026-08-18"
const CURATED_WORLD_COLLECTION := "sprite-gen-curated-world-assets-2026-08-18"
const CURATED_PROJECTILE_COLLECTION := "sprite-gen-curated-projectiles-2026-08-18"
const CURATED_PASSIVE_COLLECTION := "sprite-gen-curated-passives-2026-08-18"
const GENERATED_SCENE_COLLECTION := "generated-scene-art-2026-08-18"
const CODE_NATIVE_COLLECTION := "original-code-native-vectors-2026-08-18"
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
const FORBIDDEN_PATH_TOKENS := [
	"/identity/",
	"/review/",
	"/source/",
	"/candidate/",
	"/candidates/",
	"/prompt/",
	"/prompts/",
	"/raw/",
	"/frames/",
	"/qa/",
	"/exports/",
	"/curated/",
	".prompt.",
	".qa.",
	"contact-sheet",
	".mp4",
	".webm",
	".gif",
	".ds_store",
]


func _init() -> void:
	var root := _argument(
		OS.get_cmdline_user_args(),
		"--skin-root",
		"res://content_packs/skins/lets_gooooo"
	)
	var errors := validate_skin_root(root)
	if not errors.is_empty():
		for error: String in errors:
			push_error(error)
		quit(ERR_INVALID_DATA)
		return
	print("STATIC_SKIN_ASSET_VALIDATION passed: %s" % root)
	quit(OK)


static func validate_skin_root(root: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var normalized_root := root.trim_suffix("/")
	var manifest_path := normalized_root.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		errors.append("Static asset manifest is missing: %s" % manifest_path)
		return errors
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		errors.append("Static asset manifest is not valid JSON: %s" % manifest_path)
		return errors
	var manifest := parsed as Dictionary
	if String(manifest.get("kind", "")) != "lets-gooooo-static-assets":
		errors.append("Unexpected static asset manifest kind")
	if int(manifest.get("schema_version", 0)) != 1:
		errors.append("Unsupported static asset manifest schema")
	if int(manifest.get("logical_canvas", 0)) != LOGICAL_CANVAS:
		errors.append("Static assets must use a 64x64 logical canvas")
	if int(manifest.get("output_canvas", 0)) != OUTPUT_CANVAS:
		errors.append("Static assets must be exported at 256x256")
	if int(manifest.get("nearest_scale", 0)) != NEAREST_SCALE:
		errors.append("Static assets must use a 4x nearest-neighbor scale")
	var raw_assets: Variant = manifest.get("assets", [])
	if not raw_assets is Array:
		errors.append("Static asset manifest assets must be an array")
		return errors
	var asset_paths := {}
	var asset_ids := {}
	var passive_ids := {}
	var category_counts := {}
	for raw_entry: Variant in raw_assets as Array:
		if not raw_entry is Dictionary:
			errors.append("Static asset entry must be a dictionary")
			continue
		var entry := raw_entry as Dictionary
		var asset_id := String(entry.get("id", ""))
		var path := String(entry.get("path", ""))
		var category := String(entry.get("category", ""))
		category_counts[category] = int(category_counts.get(category, 0)) + 1
		if category == "passive_icon":
			passive_ids[asset_id] = true
			var expected_passive_path := normalized_root.path_join(
				"assets/passives/%s.png" % asset_id.trim_prefix("passive.")
			)
			if path != expected_passive_path:
				errors.append("Passive icon path does not match its presentation ID: %s" % asset_id)
		if asset_id.is_empty() or asset_ids.has(asset_id):
			errors.append("Static asset ID is empty or duplicated: %s" % asset_id)
		else:
			asset_ids[asset_id] = true
		if not _is_child_res_path(path, normalized_root.path_join("assets")):
			errors.append("Static asset path escapes the selected skin: %s" % path)
			continue
		asset_paths[path] = true
		if _has_forbidden_path_token(path):
			errors.append("Forbidden source/review artifact path in asset manifest: %s" % path)
		if not bool(entry.get("shipping_allowed", false)):
			errors.append("Static asset is not allowed to ship: %s" % asset_id)
		if String((entry.get("approval", {}) as Dictionary).get("status", "")) != "approved":
			errors.append("Static asset is not approved: %s" % asset_id)
		if String((entry.get("rights", {}) as Dictionary).get("status", "")) != "cleared":
			errors.append("Static asset rights are not cleared: %s" % asset_id)
		if String((entry.get("source", {}) as Dictionary).get("sha256", "")).length() != 64:
			errors.append("Static asset source hash is missing: %s" % asset_id)
		var source := entry.get("source", {}) as Dictionary
		for forbidden_source_key: String in ["path", "file", "prompt", "references", "identity"]:
			if source.has(forbidden_source_key):
				errors.append(
					"Shipping provenance must not expose source material (%s): %s"
					% [forbidden_source_key, asset_id]
				)
		var collection := String(source.get("collection", ""))
		if collection in [
				CURATED_COLLECTION,
				CURATED_WORLD_COLLECTION,
				CURATED_PROJECTILE_COLLECTION,
				CURATED_PASSIVE_COLLECTION,
			]:
			var normalization := entry.get("normalization", {}) as Dictionary
			var is_pixel_unfake_curated := (
				String(normalization.get("mode", "")) == "sprite_gen_pixel_unfake_curated"
			)
			var expected_pipeline := (
				[
					"built_in_image_gen",
					"sprite_gen_component_row",
					"sprite_gen_pixel_unfake",
					"sprite_gen_curation",
				]
				if is_pixel_unfake_curated
				else ["built_in_image_gen", "sprite_gen_curation"]
			)
			if source.get("pipeline", []) != expected_pipeline:
				errors.append("Curated asset provenance pipeline is invalid: %s" % asset_id)
			var expected_approval_basis := (
				"agent_visual_qa_sprite_gen_curation"
				if is_pixel_unfake_curated
				else "agent_visual_qa"
			)
			if String((entry.get("approval", {}) as Dictionary).get("basis", "")) != expected_approval_basis:
				errors.append("Curated asset visual approval is missing: %s" % asset_id)
		if collection == CURATED_PASSIVE_COLLECTION:
			_validate_curated_passive_provenance(entry, errors)
		if collection == GENERATED_SCENE_COLLECTION:
			if source.get("pipeline", []) != ["built_in_image_gen"]:
				errors.append("Generated scene provenance pipeline is invalid: %s" % asset_id)
			if String(source.get("sha256", "")) != String(entry.get("sha256", "")):
				errors.append("Lossless generated scene hash changed: %s" % asset_id)
		if category == "weapon_icon":
			_validate_weapon_anchors(entry, errors)
		elif category in ["pickup_world", "prop_world", "ally_world"]:
			_validate_world_anchors(entry, errors)
		elif category == "projectile_world":
			_validate_projectile_anchors(entry, errors)
		if collection == CODE_NATIVE_COLLECTION:
			if String(source.get("kind", "")) != "original_code_native_vector":
				errors.append("Code-native vector provenance is invalid: %s" % asset_id)
			if String(source.get("sha256", "")) != String(entry.get("sha256", "")):
				errors.append("Code-native vector source hash changed: %s" % asset_id)
		_validate_asset_file(entry, errors)
	if int(category_counts.get("weapon_icon", 0)) < 24:
		errors.append("Selected skin must approve all 24 weapon icons")
	if int(category_counts.get("passive_icon", 0)) != REQUIRED_PASSIVE_IDS.size():
		errors.append("Selected skin must approve exactly 60 passive icons")
	for passive_id: String in REQUIRED_PASSIVE_IDS:
		if not passive_ids.has(passive_id):
			errors.append("Selected skin passive icon is missing: %s" % passive_id)
	for passive_id: Variant in passive_ids:
		if String(passive_id) not in REQUIRED_PASSIVE_IDS:
			errors.append("Selected skin contains an unknown passive icon: %s" % passive_id)
	if int(category_counts.get("pickup_world", 0)) < 3:
		errors.append("Selected skin must approve the imported pickup sprites")
	if int(category_counts.get("prop_world", 0)) < 3:
		errors.append("Selected skin must approve the imported prop sprites")
	if int(category_counts.get("ally_world", 0)) < 2:
		errors.append("Selected skin must approve the imported ally sprites")
	if int(category_counts.get("projectile_world", 0)) < 4:
		errors.append("Selected skin must approve the four projectile sprites")
	for projectile_id: String in [
		"projectile.pistol",
		"projectile.rifle",
		"projectile.sniper",
		"projectile.enemy",
	]:
		if not asset_ids.has(projectile_id):
			errors.append("Selected skin projectile sprite is missing: %s" % projectile_id)
	if not asset_ids.has("scene.title_background"):
		errors.append("Selected skin title background is missing")
	if not asset_ids.has("scene.arena_floor"):
		errors.append("Selected skin arena floor is missing")
	if not asset_ids.has("ui.logo") or not asset_ids.has("ui.app_icon"):
		errors.append("Selected skin code-native logo assets are missing")
	var disk_files := PackedStringArray()
	_collect_files(normalized_root.path_join("assets"), disk_files)
	for path: String in disk_files:
		if _has_forbidden_path_token(path):
			errors.append("Forbidden source/review artifact exists in selected skin: %s" % path)
		var extension := path.get_extension().to_lower()
		if extension in ["png", "svg"] and not asset_paths.has(path):
			errors.append("Shipping art is not approved by asset_manifest.json: %s" % path)
	for approved_path: Variant in asset_paths:
		if not disk_files.has(String(approved_path)):
			errors.append("Approved static asset is missing from disk: %s" % approved_path)
	return errors


static func _validate_curated_passive_provenance(
	entry: Dictionary,
	errors: PackedStringArray
) -> void:
	var asset_id := String(entry.get("id", ""))
	var source := entry.get("source", {}) as Dictionary
	if String(source.get("selected_candidate_sha256", "")) != String(source.get("sha256", "")):
		errors.append("Curated passive selected-source hash is inconsistent: %s" % asset_id)
	if String(source.get("raw_sheet_sha256", "")).length() != 64:
		errors.append("Curated passive raw-sheet hash is missing: %s" % asset_id)
	var curation := entry.get("curation", {}) as Dictionary
	if String(curation.get("sha256", "")) != String(entry.get("sha256", "")):
		errors.append("Curated passive final hash is inconsistent: %s" % asset_id)
	for hash_key: String in [
		"normalized_input_sha256",
		"selection_sha256",
		"qa_sha256",
	]:
		if String(curation.get(hash_key, "")).length() != 64:
			errors.append("Curated passive %s is missing: %s" % [hash_key, asset_id])
	if String(curation.get("picked", "")) not in ["A", "B", "C"]:
		errors.append("Curated passive selection is invalid: %s" % asset_id)
	var normalization := entry.get("normalization", {}) as Dictionary
	if String(normalization.get("mode", "")) != "lossless_curated_copy":
		errors.append("Curated passive must be copied losslessly: %s" % asset_id)
	if String(normalization.get("transparent_rgb", "")) != "zero":
		errors.append("Curated passive must clear transparent RGB: %s" % asset_id)


static func _validate_asset_file(entry: Dictionary, errors: PackedStringArray) -> void:
	var asset_id := String(entry.get("id", ""))
	var path := String(entry.get("path", ""))
	if not FileAccess.file_exists(path):
		errors.append("Approved static asset file is missing: %s" % path)
		return
	if FileAccess.get_sha256(path) != String(entry.get("sha256", "")):
		errors.append("Approved static asset hash mismatch: %s" % asset_id)
		return
	var extension := path.get_extension().to_lower()
	if extension == "svg":
		_validate_svg(entry, errors)
		return
	if extension != "png":
		errors.append("Approved static art must be PNG or SVG: %s" % path)
		return
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		errors.append("Approved static asset is not a readable PNG: %s" % path)
		return
	var category := String(entry.get("category", ""))
	if category in ["scene_background", "scene_floor"]:
		_validate_generated_scene_png(entry, image, errors)
		return
	if category == "ui_app_icon":
		_validate_user_selected_app_icon(entry, image, errors)
		return
	if category not in [
		"weapon_icon",
		"passive_icon",
		"pickup_world",
		"prop_world",
		"ally_world",
		"projectile_world",
	]:
		errors.append("Unsupported static asset category: %s" % category)
		return
	_validate_pixel_art_image(entry, image, errors)


static func _validate_pixel_art_image(
	entry: Dictionary,
	image: Image,
	errors: PackedStringArray
) -> void:
	var path := String(entry.get("path", ""))
	if image.get_width() != OUTPUT_CANVAS or image.get_height() != OUTPUT_CANVAS:
		errors.append("Approved static asset must be 256x256: %s" % path)
		return
	image.convert(Image.FORMAT_RGBA8)
	var logical := image.duplicate()
	logical.resize(LOGICAL_CANVAS, LOGICAL_CANVAS, Image.INTERPOLATE_NEAREST)
	var roundtrip := logical.duplicate()
	roundtrip.resize(OUTPUT_CANVAS, OUTPUT_CANVAS, Image.INTERPOLATE_NEAREST)
	if roundtrip.get_data() != image.get_data():
		errors.append("Approved static asset is not a nearest 4x logical image: %s" % path)
		return
	for logical_y: int in range(LOGICAL_CANVAS):
		for logical_x: int in range(LOGICAL_CANVAS):
			var expected: Color = logical.get_pixel(logical_x, logical_y)
			if expected.a != 0.0 and expected.a != 1.0:
				errors.append("Approved static asset contains partial alpha: %s" % path)
				return
			if (
				expected.a == 0.0
				and String((entry.get("normalization", {}) as Dictionary).get("transparent_rgb", "")) == "zero"
				and (expected.r != 0.0 or expected.g != 0.0 or expected.b != 0.0)
			):
				errors.append("Approved static asset contains color under transparent alpha: %s" % path)
				return
	if _has_suspect_chroma_edge(logical):
		errors.append("Approved static asset contains a saturated green chroma edge: %s" % path)


static func _validate_user_selected_app_icon(
	entry: Dictionary,
	image: Image,
	errors: PackedStringArray
) -> void:
	var asset_id := String(entry.get("id", ""))
	if image.get_width() != OUTPUT_CANVAS or image.get_height() != OUTPUT_CANVAS:
		errors.append("User-selected app icon must be a 256px pixel-art master: %s" % asset_id)
		return
	var source := entry.get("source", {}) as Dictionary
	if String(source.get("kind", "")) != "user_provided_art":
		errors.append("User-selected app icon provenance is invalid: %s" % asset_id)
	if source.get("pipeline", []) != ["sprite_gen_pixel_unfake", "sprite_gen_curation"]:
		errors.append("User-selected app icon curation pipeline is invalid: %s" % asset_id)
	if String((entry.get("approval", {}) as Dictionary).get("basis", "")) != "user_explicit_selection":
		errors.append("User-selected app icon approval is missing: %s" % asset_id)
	var normalization := entry.get("normalization", {}) as Dictionary
	if String(normalization.get("mode", "")) != "sprite_gen_pixel_unfake_curated":
		errors.append("User-selected app icon must use the curated pixel-unfake master: %s" % asset_id)
	var logical_canvas := normalization.get("logical_canvas", []) as Array
	if (
		logical_canvas.size() != 2
		or int(logical_canvas[0]) != LOGICAL_CANVAS
		or int(logical_canvas[1]) != LOGICAL_CANVAS
	):
		errors.append("User-selected app icon logical canvas is invalid: %s" % asset_id)
	if int(normalization.get("nearest_scale", 0)) != NEAREST_SCALE:
		errors.append("User-selected app icon nearest-neighbor scale is invalid: %s" % asset_id)
	if float(normalization.get("outline_strength", 0.0)) < 1.0:
		errors.append("User-selected app icon outline is not strong enough: %s" % asset_id)
	if float(normalization.get("edge_dark_fraction", 0.0)) < 0.85:
		errors.append("User-selected app icon lacks a clean dark silhouette: %s" % asset_id)
	_validate_pixel_art_image(entry, image, errors)


static func _has_suspect_chroma_edge(logical: Image) -> bool:
	for y: int in range(LOGICAL_CANVAS):
		for x: int in range(LOGICAL_CANVAS):
			var pixel := logical.get_pixel(x, y)
			var green_key_edge := (
				pixel.g >= 0.58
				and pixel.g - pixel.r >= 0.22
				and pixel.g - pixel.b >= 0.22
			)
			if pixel.a < 1.0 or not green_key_edge:
				continue
			for offset: Vector2i in [
				Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
				Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
			]:
				var neighbor := Vector2i(x, y) + offset
				if (
					neighbor.x < 0 or neighbor.x >= LOGICAL_CANVAS
					or neighbor.y < 0 or neighbor.y >= LOGICAL_CANVAS
				):
					continue
				if logical.get_pixelv(neighbor).a == 0.0:
					return true
	return false


static func _validate_svg(entry: Dictionary, errors: PackedStringArray) -> void:
	var asset_id := String(entry.get("id", ""))
	var path := String(entry.get("path", ""))
	var category := String(entry.get("category", ""))
	if category not in ["ui_logo", "ui_app_icon"]:
		errors.append("Only approved UI identity art may use SVG: %s" % asset_id)
		return
	var svg := FileAccess.get_file_as_string(path).to_lower()
	if not svg.contains("<svg"):
		errors.append("Code-native vector is not an SVG document: %s" % asset_id)
	for forbidden: String in [
		"<script",
		"<image",
		"xlink:href",
		"href=\"http",
		"href='http",
		"url(http",
		"url(//",
	]:
		if svg.contains(forbidden):
			errors.append("Code-native vector contains an external payload: %s" % asset_id)
			return


static func _validate_generated_scene_png(
	entry: Dictionary,
	image: Image,
	errors: PackedStringArray
) -> void:
	var asset_id := String(entry.get("id", ""))
	var path := String(entry.get("path", ""))
	var category := String(entry.get("category", ""))
	var normalization := entry.get("normalization", {}) as Dictionary
	if String(normalization.get("mode", "")) != "lossless_copy":
		errors.append("Generated scene must be installed losslessly: %s" % asset_id)
	var source_canvas := normalization.get("source_canvas", []) as Array
	var output_canvas := normalization.get("output_canvas", []) as Array
	if (
		source_canvas.size() != 2
		or output_canvas.size() != 2
		or int(source_canvas[0]) != image.get_width()
		or int(source_canvas[1]) != image.get_height()
		or int(output_canvas[0]) != image.get_width()
		or int(output_canvas[1]) != image.get_height()
	):
		errors.append("Generated scene dimensions do not match provenance: %s" % asset_id)
	if category == "scene_background":
		var ratio := float(image.get_width()) / float(maxi(1, image.get_height()))
		if image.get_width() < 1280 or image.get_height() < 720 or ratio < 1.70 or ratio > 1.82:
			errors.append("Title background must be a release-size widescreen PNG: %s" % path)
	elif category == "scene_floor":
		if image.get_width() < 1024 or image.get_width() != image.get_height():
			errors.append("Arena floor must be a release-size square PNG: %s" % path)
		if String(entry.get("sampling", "")) != "nearest":
			errors.append("Arena floor must request nearest sampling: %s" % asset_id)


static func _validate_weapon_anchors(entry: Dictionary, errors: PackedStringArray) -> void:
	var asset_id := String(entry.get("id", ""))
	var anchors := entry.get("anchors", {}) as Dictionary
	if String(anchors.get("coordinate_space", "")) != "logical_64":
		errors.append("Weapon anchor coordinate space is invalid: %s" % asset_id)
	if not _valid_logical_point(anchors.get("pivot_logical", [])):
		errors.append("Weapon pivot is missing or outside the logical canvas: %s" % asset_id)
	var world_scale := float(anchors.get("world_scale", 0.0))
	if world_scale < 0.12 or world_scale > 0.35:
		errors.append("Weapon world scale is missing or implausible: %s" % asset_id)
	var mount_position: Variant = anchors.get("mount_position_world", [])
	if not mount_position is Array or (mount_position as Array).size() != 2:
		errors.append("Weapon mount position is missing: %s" % asset_id)
	if String(anchors.get("calibration_status", "")) != "runtime_calibrated_2026_08_19":
		errors.append("Weapon runtime calibration is incomplete: %s" % asset_id)
	var has_action_origin := false
	for key: String in [
		"muzzle_logical",
		"strike_origin_logical",
		"throw_origin_logical",
		"placement_origin_logical",
	]:
		if anchors.has(key):
			has_action_origin = _valid_logical_point(anchors.get(key, []))
			if not has_action_origin:
				errors.append("Weapon action anchor is outside the logical canvas: %s" % asset_id)
			break
	if not has_action_origin:
		errors.append("Weapon action anchor is missing: %s" % asset_id)


static func _validate_world_anchors(entry: Dictionary, errors: PackedStringArray) -> void:
	var asset_id := String(entry.get("id", ""))
	var anchors := entry.get("anchors", {}) as Dictionary
	if String(anchors.get("coordinate_space", "")) != "logical_64":
		errors.append("World asset anchor coordinate space is invalid: %s" % asset_id)
	if not _valid_logical_point(anchors.get("pivot_logical", [])):
		errors.append("World asset pivot is missing or invalid: %s" % asset_id)
	if not _valid_logical_point(anchors.get("ground_origin_logical", [])):
		errors.append("World asset ground origin is missing or invalid: %s" % asset_id)


static func _validate_projectile_anchors(entry: Dictionary, errors: PackedStringArray) -> void:
	var asset_id := String(entry.get("id", ""))
	var anchors := entry.get("anchors", {}) as Dictionary
	if String(anchors.get("coordinate_space", "")) != "logical_64":
		errors.append("Projectile anchor coordinate space is invalid: %s" % asset_id)
	if not _valid_logical_point(anchors.get("center_logical", [])):
		errors.append("Projectile center anchor is missing or invalid: %s" % asset_id)
	if anchors.get("center_logical", []) != anchors.get("pivot_logical", []):
		errors.append("Projectile pivot must match its center anchor: %s" % asset_id)


static func _valid_logical_point(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var point := value as Array
	return (
		int(point[0]) >= 0
		and int(point[0]) < LOGICAL_CANVAS
		and int(point[1]) >= 0
		and int(point[1]) < LOGICAL_CANVAS
	)


static func _collect_files(path: String, output: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				_collect_files(entry_path, output)
			else:
				output.append(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	output.sort()


static func _is_child_res_path(path: String, root: String) -> bool:
	return path.begins_with(root.trim_suffix("/") + "/") and not path.contains("..")


static func _has_forbidden_path_token(path: String) -> bool:
	var lowered := path.replace("\\", "/").to_lower()
	for token: String in FORBIDDEN_PATH_TOKENS:
		if lowered.contains(token):
			return true
	return false


static func _argument(arguments: PackedStringArray, name: String, fallback: String) -> String:
	var index := arguments.find(name)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return fallback
