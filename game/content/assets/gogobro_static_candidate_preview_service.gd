class_name GogoStaticAssetCandidatePreviewService
extends RefCounted

const MANIFEST_PATH := "res://game/content/assets/gogobro_static_candidate_preview_v1.json"
const ASSET_ROOT := "res://game/assets/gogobro_static_preview/"
const SCHEMA_VERSION := "gogobro-static-candidate-preview-v1"
const MANIFEST_KIND := "development_candidate_preview_only"
const EXPECTED_UNIT_COUNT := 63
const EXPECTED_CATEGORY_COUNTS := {
	"weapon": 12,
	"item": 28,
	"upgrade": 5,
	"world": 11,
	"ui_brand": 7,
}
const CATEGORY_ROLE := {
	"weapon": &"world_sprite",
	"item": &"icon",
	"upgrade": &"icon",
	"world": &"world_sprite",
	"ui_brand": &"ui_texture",
}
const REQUIRED_VARIANT_SELECTORS := {
	"community_server_decor_pack": [
		"decor_variant_01",
		"decor_variant_02",
		"decor_variant_03",
		"decor_variant_04",
		"decor_variant_05",
		"decor_variant_06",
	],
	"card_and_rarity_frame_kit": ["common", "uncommon", "rare", "legendary"],
	"four_state_button": ["normal", "hover", "pressed", "disabled"],
}

var last_errors: Array[Dictionary] = []


func build_overlay(
	base_snapshot: GogoStaticAssetSnapshot,
	content: ContentSnapshot,
	manifest_path: String = MANIFEST_PATH,
	asset_root: String = ASSET_ROOT
) -> GogoStaticAssetSnapshot:
	last_errors.clear()
	if base_snapshot == null or content == null:
		_issue(&"candidate_preview_invalid_parameter", "Preview requires a base snapshot and content snapshot.")
		return null
	if not FileAccess.file_exists(manifest_path):
		_issue(&"candidate_preview_manifest_missing", "Candidate preview manifest is missing.")
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		_issue(&"candidate_preview_manifest_invalid", "Candidate preview manifest is not valid JSON.")
		return null
	var manifest := parsed as Dictionary
	if String(manifest.get("schema_version", "")) != SCHEMA_VERSION:
		_issue(&"candidate_preview_schema_mismatch", "Candidate preview schema is unexpected.")
	if String(manifest.get("kind", "")) != MANIFEST_KIND:
		_issue(&"candidate_preview_kind_mismatch", "Candidate preview kind is unexpected.")
	if bool(manifest.get("enabled_in_shipping", true)) or bool(manifest.get("human_approval_implied", true)):
		_issue(&"candidate_preview_shipping_claim", "Candidate preview must not claim shipping or human approval.")
	if bool(manifest.get("character_assets_included", true)):
		_issue(&"candidate_preview_character_forbidden", "Character assets are forbidden in the static preview overlay.")
	var units_variant: Variant = manifest.get("units")
	if not units_variant is Array:
		_issue(&"candidate_preview_units_invalid", "Candidate preview units must be an array.")
		return null
	var units := units_variant as Array
	if units.size() != EXPECTED_UNIT_COUNT:
		_issue(&"candidate_preview_count_mismatch", "Candidate preview must contain exactly 63 units.")

	var states: Dictionary = {}
	var handles: Dictionary = {}
	var content_bindings: Dictionary = {}
	var zone_bindings: Dictionary = {}
	var global_bindings: Dictionary = {}
	var category_counts: Dictionary = {}
	var normalized_root := _normalized_root(asset_root)
	for unit_variant: Variant in units:
		if not unit_variant is Dictionary:
			_issue(&"candidate_preview_unit_invalid", "Candidate preview contains a non-object unit.")
			continue
		var unit := unit_variant as Dictionary
		var asset_id := StringName(String(unit.get("asset_id", "")))
		var category := String(unit.get("category", ""))
		if asset_id.is_empty() or states.has(asset_id) or asset_id == &"service_carbine":
			_issue(&"candidate_preview_asset_id_invalid", "Candidate preview IDs must be unique and allowed.", asset_id)
			continue
		if not EXPECTED_CATEGORY_COUNTS.has(category):
			_issue(&"candidate_preview_category_invalid", "Candidate preview category is invalid.", asset_id)
			continue
		category_counts[category] = int(category_counts.get(category, 0)) + 1
		var expected_role: StringName = CATEGORY_ROLE[category]
		if StringName(String(unit.get("role", ""))) != expected_role:
			_issue(&"candidate_preview_role_invalid", "Candidate preview role does not match its category.", asset_id)
			continue
		var path := _normalized_path(String(unit.get("resource_path", "")))
		if not path.begins_with(normalized_root) or path.contains("..") or not FileAccess.file_exists(path):
			_issue(&"candidate_preview_path_invalid", "Candidate preview texture path is missing or outside its root.", asset_id)
			continue
		var declared_hash := String(unit.get("sha256", "")).to_upper()
		if declared_hash.length() != 64 or FileAccess.get_sha256(path).to_upper() != declared_hash:
			_issue(&"candidate_preview_hash_mismatch", "Candidate preview texture hash does not match.", asset_id)
			continue
		if String(unit.get("texture_filter", "")) != "nearest" or bool(unit.get("mipmaps", true)):
			_issue(&"candidate_preview_sampling_invalid", "Candidate preview must use nearest filtering and no mipmaps.", asset_id)
			continue
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
			_issue(&"candidate_preview_texture_invalid", "Candidate preview texture is not a readable PNG.", asset_id)
			continue
		var pixel_size := _pair_i(unit.get("pixel_size"))
		var display_size := _pair_i(unit.get("display_size_px"))
		var pivot := _pair_i(unit.get("pivot_px"))
		if pixel_size != image.get_size() or display_size != pixel_size:
			_issue(&"candidate_preview_size_mismatch", "Candidate preview dimensions do not match the PNG.", asset_id)
			continue
		if pivot.x < 0 or pivot.y < 0 or pivot.x >= display_size.x or pivot.y >= display_size.y:
			_issue(&"candidate_preview_pivot_invalid", "Candidate preview pivot is outside its texture.", asset_id)
			continue
		var anchors := _anchors(unit.get("anchors_px"), display_size, asset_id)
		if not last_errors.is_empty():
			continue
		var texture := ImageTexture.create_from_image(image)
		var key := _asset_key(asset_id, expected_role)
		handles[key] = _handle(asset_id, expected_role, texture, display_size, pivot, anchors)
		states[asset_id] = &"preview_ready"
		var aliases_variant: Variant = unit.get("preview_alias_asset_ids", [])
		if not aliases_variant is Array or not (aliases_variant as Array).is_empty():
			_issue(&"candidate_preview_alias_invalid", "Candidate preview aliases are forbidden; every weapon identity needs its own visual.", asset_id)
			continue
		_install_variants(unit, asset_id, expected_role, category, normalized_root, handles, global_bindings)
		if not last_errors.is_empty():
			continue
		if category == "weapon":
			var icon_key := _asset_key(asset_id, &"icon")
			handles[icon_key] = _handle(asset_id, &"icon", texture, display_size, Vector2i(display_size / 2), {})
			_bind_content_icons(content_bindings, content, asset_id, icon_key, [&"weapon"])
		elif category in ["item", "upgrade"]:
			_bind_content_icons(content_bindings, content, asset_id, key, [StringName(category)])
		else:
			global_bindings[_binding_key(&"global", &"", asset_id)] = key

	for category: String in EXPECTED_CATEGORY_COUNTS:
		if int(category_counts.get(category, 0)) != int(EXPECTED_CATEGORY_COUNTS[category]):
			_issue(&"candidate_preview_category_count_mismatch", "Candidate preview category counts are incomplete.")
	if not last_errors.is_empty():
		return null
	return base_snapshot.with_development_overlay(
		states,
		handles,
		content_bindings,
		zone_bindings,
		global_bindings
	)


func _bind_content_icons(
	bindings: Dictionary,
	content: ContentSnapshot,
	asset_id: StringName,
	asset_key: String,
	kinds: Array[StringName]
) -> void:
	for kind: StringName in kinds:
		for definition: GogoContentDefinition in content.all(kind):
			if definition.icon_asset_id == asset_id:
				bindings[_binding_key(kind, definition.content_id, &"icon")] = asset_key


func _handle(
	asset_id: StringName,
	role: StringName,
	texture: Texture2D,
	display_size: Vector2i,
	pivot: Vector2i,
	anchors: Dictionary,
	selector: StringName = &"",
	display_scale: Vector2 = Vector2.ONE
) -> GogoStaticAssetHandle:
	var handle := GogoStaticAssetHandle.new()
	var key := _asset_key(asset_id, role, selector)
	handle._configure({
		"binding_key": StringName(key),
		"asset_id": asset_id,
		"role": role,
		"selector": selector,
		"display_size_px": display_size,
		"display_scale": display_scale,
		"pivot_px": pivot,
		"anchors_px": anchors,
		"atlas_rect_px": Rect2i(Vector2i.ZERO, Vector2i(texture.get_size())),
		"source_kind": &"development_preview",
	}, texture)
	return handle


func _install_variants(
	unit: Dictionary,
	asset_id: StringName,
	role: StringName,
	category: String,
	normalized_root: String,
	handles: Dictionary,
	global_bindings: Dictionary
) -> void:
	var variants_variant: Variant = unit.get("variants", [])
	if not variants_variant is Array:
		_issue(&"candidate_preview_variants_invalid", "Candidate variants must be an array.", asset_id)
		return
	var variants := variants_variant as Array
	var expected: Array = REQUIRED_VARIANT_SELECTORS.get(String(asset_id), []) as Array
	if variants.size() != expected.size():
		_issue(&"candidate_preview_variant_count_mismatch", "Candidate variant count does not match the registry sub-assets.", asset_id)
		return
	for index in variants.size():
		var value: Variant = variants[index]
		if not value is Dictionary:
			_issue(&"candidate_preview_variant_invalid", "Candidate variant must be an object.", asset_id)
			return
		var variant := value as Dictionary
		var selector := StringName(String(variant.get("selector", "")))
		if selector.is_empty() or String(selector) != String(expected[index]):
			_issue(&"candidate_preview_variant_selector_invalid", "Candidate variant selector is missing or out of order.", asset_id)
			return
		var path := _normalized_path(String(variant.get("resource_path", "")))
		if not path.begins_with(normalized_root) or path.contains("..") or not FileAccess.file_exists(path):
			_issue(&"candidate_preview_variant_path_invalid", "Candidate variant PNG is missing or outside its root.", asset_id)
			return
		var declared_hash := String(variant.get("sha256", "")).to_upper()
		if declared_hash.length() != 64 or FileAccess.get_sha256(path).to_upper() != declared_hash:
			_issue(&"candidate_preview_variant_hash_mismatch", "Candidate variant PNG hash does not match.", asset_id)
			return
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
			_issue(&"candidate_preview_variant_texture_invalid", "Candidate variant is not a readable PNG.", asset_id)
			return
		var pixel_size := _pair_i(variant.get("pixel_size"))
		var display_size := _pair_i(variant.get("display_size_px"))
		var pivot := _pair_i(variant.get("pivot_px"))
		if pixel_size != image.get_size() or display_size != pixel_size:
			_issue(&"candidate_preview_variant_size_mismatch", "Candidate variant dimensions do not match the PNG.", asset_id)
			return
		if pivot.x < 0 or pivot.y < 0 or pivot.x >= display_size.x or pivot.y >= display_size.y:
			_issue(&"candidate_preview_variant_pivot_invalid", "Candidate variant pivot is outside its texture.", asset_id)
			return
		var anchors := _anchors(variant.get("anchors_px", {}), display_size, asset_id)
		if not last_errors.is_empty():
			return
		var texture := ImageTexture.create_from_image(image)
		var key := _asset_key(asset_id, role, selector)
		handles[key] = _handle(asset_id, role, texture, display_size, pivot, anchors, selector)
		if category == "ui_brand":
			global_bindings[_binding_key(&"global", &"", asset_id, selector)] = key


func _anchors(value: Variant, size: Vector2i, asset_id: StringName) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		_issue(&"candidate_preview_anchors_invalid", "Candidate preview anchors must be an object.", asset_id)
		return result
	for raw_name: Variant in (value as Dictionary).keys():
		var point := _pair_i((value as Dictionary)[raw_name])
		if point.x < 0 or point.y < 0 or point.x >= size.x or point.y >= size.y:
			_issue(&"candidate_preview_anchor_invalid", "Candidate preview anchor is outside its texture.", asset_id)
			return {}
		result[StringName(String(raw_name))] = point
	return result


static func _pair_i(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i(-1, -1)
	var pair := value as Array
	for component: Variant in pair:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or float(component) != floorf(float(component)):
			return Vector2i(-1, -1)
	return Vector2i(int(pair[0]), int(pair[1]))


static func _normalized_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path()


static func _normalized_root(path: String) -> String:
	var result := _normalized_path(path)
	return result if result.ends_with("/") else result + "/"


static func _asset_key(asset_id: StringName, role: StringName, selector: StringName = &"") -> String:
	return "%s|%s|%s" % [asset_id, role, selector]


static func _binding_key(
	kind: StringName,
	consumer_id: StringName,
	role: StringName,
	selector: StringName = &""
) -> String:
	return "%s|%s|%s|%s" % [kind, consumer_id, role, selector]


func _issue(code: StringName, message: String, asset_id: StringName = &"") -> void:
	last_errors.append({"code": code, "message": message, "asset_id": asset_id})
