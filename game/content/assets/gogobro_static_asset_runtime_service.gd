class_name GogoStaticAssetRuntimeService
extends RefCounted

signal snapshot_activated(generation: int)
signal asset_quarantined(asset_id: StringName, reason: StringName)

const MANIFEST_PATH := "res://game/content/assets/gogobro_static_runtime_bindings_v1.json"
const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const DEFAULT_ASSET_ROOT := "res://game/assets/gogobro_static/"
const SCHEMA_VERSION := "gogobro-static-runtime-bindings-v1"
const MANIFEST_KIND := "shipping_runtime_bindings"
const EXPECTED_NONCHARACTER_UNITS := 70
const EXPECTED_CATEGORY_COUNTS := {
	"weapon": 12,
	"projectile_hit_kit": 1,
	"item": 30,
	"upgrade": 6,
	"world": 11,
	"ui_brand": 10,
}
const ALLOWED_DECLARED_STATES := ["inactive", "requested_active"]
const MAX_PIXEL_COMPONENT := 16384
const STATIC_ASSET_REGISTRY := preload("res://game/content/assets/static_asset_registry.gd")

var _manifest_path: String
var _registry_path: String
var _allowed_asset_root: String
var _allow_development_preview := false
var _active_snapshot: GogoStaticAssetSnapshot
var _staged_snapshot: GogoStaticAssetSnapshot


func _init(
	manifest_path: String = MANIFEST_PATH,
	registry_path: String = REGISTRY_PATH,
	allowed_asset_root: String = DEFAULT_ASSET_ROOT,
	allow_development_preview: bool = false
) -> void:
	_manifest_path = manifest_path
	_registry_path = registry_path
	_allowed_asset_root = _normalized_root(allowed_asset_root)
	_allow_development_preview = allow_development_preview
	_active_snapshot = _degraded_snapshot(0, &"shipping_manifest_not_staged", "Static shipping manifest has not been staged.")


func stage(content: ContentSnapshot) -> Error:
	if content == null:
		return ERR_INVALID_PARAMETER
	var next_generation := _active_snapshot.generation + 1
	if not FileAccess.file_exists(_manifest_path):
		_staged_snapshot = _degraded_snapshot(
			next_generation,
			&"shipping_manifest_missing",
			"Static shipping manifest is absent; all non-character visuals use fallback."
		)
		return OK
	if not FileAccess.file_exists(_registry_path):
		_staged_snapshot = _degraded_snapshot(
			next_generation,
			&"shipping_registry_missing",
			"Canonical static asset registry is absent; no shipping binding can be trusted."
		)
		return OK
	var raw_json := FileAccess.get_file_as_string(_manifest_path)
	var parsed: Variant = JSON.parse_string(raw_json)
	if not parsed is Dictionary:
		_staged_snapshot = _degraded_snapshot(
			next_generation,
			&"shipping_manifest_invalid_json",
			"Static shipping manifest is not valid JSON."
		)
		return OK
	var registry_bytes := FileAccess.get_file_as_bytes(_registry_path)
	var registry_variant: Variant = JSON.parse_string(registry_bytes.get_string_from_utf8())
	if not registry_variant is Dictionary:
		_staged_snapshot = _degraded_snapshot(
			next_generation,
			&"shipping_registry_invalid_json",
			"Canonical static asset registry is not valid JSON."
		)
		return OK
	var registry_sha256 := _sha256_bytes(registry_bytes)
	_staged_snapshot = _snapshot_from_manifest(
		parsed as Dictionary,
		registry_variant as Dictionary,
		registry_sha256,
		next_generation,
		content
	)
	return OK


func activate_staged(route: StringName, session: GameSession) -> Error:
	if _staged_snapshot == null:
		return ERR_UNCONFIGURED
	if session != null or (not route.is_empty() and route != FlowRoute.MAIN_MENU):
		return ERR_BUSY
	_active_snapshot = _staged_snapshot
	_staged_snapshot = null
	snapshot_activated.emit(_active_snapshot.generation)
	return OK


func active_snapshot() -> GogoStaticAssetSnapshot:
	return _active_snapshot


func activate_development_preview(
	preview_snapshot: GogoStaticAssetSnapshot,
	route: StringName,
	session: GameSession
) -> Error:
	if not _allow_development_preview:
		return ERR_UNAUTHORIZED
	if preview_snapshot == null or not preview_snapshot.is_development_preview():
		return ERR_INVALID_DATA
	if session != null or (not route.is_empty() and route != FlowRoute.MAIN_MENU):
		return ERR_BUSY
	_active_snapshot = preview_snapshot
	snapshot_activated.emit(_active_snapshot.generation)
	return OK


func discard_staged() -> void:
	_staged_snapshot = null


func release_readiness() -> Dictionary:
	return _active_snapshot.release_readiness()


func _snapshot_from_manifest(
	manifest: Dictionary,
	registry: Dictionary,
	actual_registry_sha256: String,
	generation: int,
	content: ContentSnapshot
) -> GogoStaticAssetSnapshot:
	var errors: Array[Dictionary] = []
	if String(manifest.get("schema_version", "")) != SCHEMA_VERSION:
		_append_issue(errors, &"shipping_manifest_schema_mismatch", "Unexpected static shipping manifest schema.")
	if String(manifest.get("kind", "")) != MANIFEST_KIND:
		_append_issue(errors, &"shipping_manifest_kind_mismatch", "Unexpected static shipping manifest kind.")
	if not _is_bounded_integer(
		manifest.get("expected_noncharacter_units", -1),
		EXPECTED_NONCHARACTER_UNITS,
		EXPECTED_NONCHARACTER_UNITS
	):
		_append_issue(errors, &"shipping_manifest_count_mismatch", "Static shipping manifest must declare exactly 70 non-character units.")
	var registry_sha256 := String(manifest.get("canonical_registry_sha256", "")).to_upper()
	if not _is_sha256(registry_sha256):
		_append_issue(errors, &"shipping_manifest_registry_hash_invalid", "Canonical registry SHA-256 is missing or invalid.")
	elif registry_sha256 != actual_registry_sha256:
		_append_issue(errors, &"shipping_manifest_registry_hash_mismatch", "Canonical registry SHA-256 does not match the registry on disk.")
	var registry_units := _registry_unit_map(registry, errors)
	var units_variant: Variant = manifest.get("units")
	if not units_variant is Array:
		_append_issue(errors, &"shipping_manifest_units_invalid", "Static shipping manifest units must be an array.")
		return _degraded_snapshot(generation, &"shipping_manifest_invalid", "Static shipping manifest structure is invalid.", errors)
	var units := units_variant as Array
	if units.size() != EXPECTED_NONCHARACTER_UNITS:
		_append_issue(errors, &"shipping_manifest_unit_count_invalid", "Static shipping manifest must contain exactly 70 units.")
	var states: Dictionary = {}
	var category_counts: Dictionary = {}
	var validated_units: Array[Dictionary] = []
	for unit_variant: Variant in units:
		if not unit_variant is Dictionary:
			_append_issue(errors, &"shipping_manifest_unit_invalid", "Static shipping manifest contains a non-object unit.")
			continue
		var unit := unit_variant as Dictionary
		var asset_id := StringName(String(unit.get("asset_id", "")))
		var category := String(unit.get("category", ""))
		var declared_state := String(unit.get("declared_runtime_state", ""))
		if asset_id.is_empty() or states.has(asset_id):
			_append_issue(errors, &"shipping_manifest_asset_id_invalid", "Static shipping asset IDs must be non-empty and unique.", asset_id)
			continue
		if not registry_units.has(asset_id):
			_append_issue(errors, &"shipping_manifest_unknown_asset", "Static shipping asset is not present in the canonical registry.", asset_id)
			states[asset_id] = &"quarantined"
			continue
		var registry_unit := registry_units[asset_id] as Dictionary
		if category != String(registry_unit.get("category", "")):
			_append_issue(errors, &"shipping_manifest_registry_category_mismatch", "Static shipping category disagrees with the canonical registry.", asset_id)
			states[asset_id] = &"quarantined"
			continue
		if String(unit.get("static_content_id", "")) != String(registry_unit.get("content_id", "")):
			_append_issue(errors, &"shipping_manifest_registry_content_id_mismatch", "Static content ID disagrees with the canonical registry.", asset_id)
			states[asset_id] = &"quarantined"
			continue
		if category == "character_creature" or not EXPECTED_CATEGORY_COUNTS.has(category):
			_append_issue(errors, &"shipping_manifest_category_invalid", "Character or unknown static category is forbidden.", asset_id)
			states[asset_id] = &"quarantined"
			continue
		category_counts[category] = int(category_counts.get(category, 0)) + 1
		if not ALLOWED_DECLARED_STATES.has(declared_state):
			_append_issue(errors, &"shipping_manifest_state_invalid", "Unknown declared static runtime state.", asset_id)
			states[asset_id] = &"quarantined"
		elif declared_state == "requested_active":
			states[asset_id] = &"requested_active"
		else:
			states[asset_id] = &"inactive"
		validated_units.append(unit)
	for category: String in EXPECTED_CATEGORY_COUNTS:
		if int(category_counts.get(category, 0)) != int(EXPECTED_CATEGORY_COUNTS[category]):
			_append_issue(errors, &"shipping_manifest_category_count_invalid", "Static shipping category counts do not match the canonical 70-unit scope.")

	var handles: Dictionary = {}
	var content_bindings: Dictionary = {}
	var zone_bindings: Dictionary = {}
	var global_bindings: Dictionary = {}
	var reserved_binding_keys: Dictionary = {}
	var reserved_consumer_keys: Dictionary = {}
	if errors.is_empty():
		for unit: Dictionary in validated_units:
			var asset_id := StringName(String(unit.get("asset_id", "")))
			if String(unit.get("declared_runtime_state", "")) != "requested_active":
				continue
			var install := _load_active_unit(
				unit,
				registry_units[asset_id] as Dictionary,
				reserved_binding_keys,
				reserved_consumer_keys,
				content
			)
			var unit_issues := install.get("issues", []) as Array[Dictionary]
			if not unit_issues.is_empty():
				states[asset_id] = &"quarantined"
				for issue: Dictionary in unit_issues:
					errors.append(issue)
				asset_quarantined.emit(asset_id, StringName(String(unit_issues[0].get("code", &"shipping_binding_not_installable"))))
				continue
			states[asset_id] = &"ready"
			_merge_unique(handles, install.get("handles", {}) as Dictionary)
			_merge_unique(content_bindings, install.get("content_bindings", {}) as Dictionary)
			_merge_unique(zone_bindings, install.get("zone_bindings", {}) as Dictionary)
			_merge_unique(global_bindings, install.get("global_bindings", {}) as Dictionary)
			_merge_unique(reserved_binding_keys, install.get("binding_keys", {}) as Dictionary)
			_merge_unique(reserved_consumer_keys, install.get("consumer_keys", {}) as Dictionary)
	else:
		for unit: Dictionary in validated_units:
			if String(unit.get("declared_runtime_state", "")) != "requested_active":
				continue
			var asset_id := StringName(String(unit.get("asset_id", "")))
			states[asset_id] = &"quarantined"
			asset_quarantined.emit(asset_id, &"shipping_manifest_invalid")
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		generation,
		registry_sha256,
		EXPECTED_NONCHARACTER_UNITS,
		states,
		handles,
		content_bindings,
		zone_bindings,
		global_bindings,
		errors
	)
	return snapshot


func _load_active_unit(
	unit: Dictionary,
	registry_unit: Dictionary,
	reserved_binding_keys: Dictionary,
	reserved_consumer_keys: Dictionary,
	content: ContentSnapshot
) -> Dictionary:
	var issues: Array[Dictionary] = []
	var asset_id := StringName(String(unit.get("asset_id", "")))
	var shipping_variant: Variant = unit.get("shipping")
	if not shipping_variant is Dictionary:
		_append_issue(issues, &"shipping_binding_missing", "Requested active unit has no shipping object.", asset_id)
		return {"issues": issues}
	var shipping := shipping_variant as Dictionary
	if String(unit.get("approval_status", "")) != "approved":
		_append_issue(issues, &"shipping_binding_unit_not_approved", "Requested active unit is not explicitly approved by the shipping manifest.", asset_id)
	if String(registry_unit.get("approval_status", "")) != "approved":
		_append_issue(issues, &"shipping_binding_registry_not_approved", "Canonical registry unit is not approved for shipping.", asset_id)

	var resource_path := _normalized_path(String(shipping.get("resource_path", "")))
	if not _path_is_within_allowed_root(resource_path):
		_append_issue(issues, &"shipping_binding_path_outside_allowed_root", "Shipping texture path is outside the configured static asset root.", asset_id)
	var intended_paths := registry_unit.get("intended_file_paths", []) as Array
	if not intended_paths.has(resource_path):
		_append_issue(issues, &"shipping_binding_registry_path_mismatch", "Shipping texture path is not an intended canonical registry path.", asset_id)
	var declared_sha256 := String(shipping.get("sha256", "")).to_upper()
	if not _is_sha256(declared_sha256):
		_append_issue(issues, &"shipping_binding_hash_invalid", "Shipping texture SHA-256 is missing or invalid.", asset_id)
	var registry_hashes := registry_unit.get("hashes", {}) as Dictionary
	var registry_sha256 := String(registry_hashes.get("sha256", "")).to_upper()
	if declared_sha256 != registry_sha256:
		_append_issue(issues, &"shipping_binding_registry_hash_mismatch", "Shipping texture SHA-256 disagrees with the canonical registry.", asset_id)
	var declared_rgba8_sha256 := String(shipping.get("rgba8_sha256", "")).to_upper()
	if not _is_sha256(declared_rgba8_sha256):
		_append_issue(issues, &"shipping_binding_pixel_hash_invalid", "Shipping RGBA8 pixel SHA-256 is missing or invalid.", asset_id)
	var registry_rgba8_sha256 := String(registry_hashes.get("rgba8_sha256", "")).to_upper()
	if declared_rgba8_sha256 != registry_rgba8_sha256:
		_append_issue(issues, &"shipping_binding_registry_pixel_hash_mismatch", "Shipping RGBA8 pixel SHA-256 disagrees with the canonical registry.", asset_id)
	if String(shipping.get("texture_filter", "")) != "nearest" or bool(shipping.get("mipmaps", true)):
		_append_issue(issues, &"shipping_binding_sampling_invalid", "Shipping texture must declare nearest filtering and no mipmaps.", asset_id)

	var declared_size := _vector2i_from_json(shipping.get("pixel_size"))
	var output_spec := registry_unit.get("output_spec", {}) as Dictionary
	var registry_size := _vector2i_from_json([
		output_spec.get("width", -1),
		output_spec.get("height", -1),
	])
	if declared_size.x <= 0 or declared_size.y <= 0 or declared_size != registry_size:
		_append_issue(issues, &"shipping_binding_size_mismatch", "Shipping texture size disagrees with the canonical registry output specification.", asset_id)

	var bindings_variant: Variant = unit.get("bindings")
	if not bindings_variant is Array or (bindings_variant as Array).is_empty():
		_append_issue(issues, &"shipping_binding_entries_missing", "Requested active unit must provide at least one binding entry.", asset_id)
	var registry_bindings_variant: Variant = registry_unit.get("runtime_bindings")
	if not registry_bindings_variant is Array or registry_bindings_variant != bindings_variant:
		_append_issue(issues, &"shipping_binding_registry_metadata_mismatch", "Shipping bindings must exactly match the authorized canonical runtime metadata.", asset_id)
	if (
		bindings_variant is Array
		and not _has_authorized_approval_evidence(
			registry_unit,
			declared_sha256,
			declared_rgba8_sha256,
			declared_size,
			bindings_variant as Array
		)
	):
		_append_issue(issues, &"shipping_binding_approval_evidence_invalid", "Canonical registry lacks authorized approval tied to these exact bytes, pixels, dimensions, and runtime bindings.", asset_id)
	if not issues.is_empty():
		return {"issues": issues}

	var image: Image
	if _path_is_within_allowed_root(resource_path):
		if FileAccess.file_exists(resource_path):
			var image_bytes := FileAccess.get_file_as_bytes(resource_path)
			var actual_sha256 := _sha256_bytes(image_bytes)
			if actual_sha256 != declared_sha256:
				_append_issue(issues, &"shipping_binding_hash_mismatch", "Shipping texture bytes do not match the declared SHA-256.", asset_id)
				return {"issues": issues}
			image = Image.new()
			var image_error := image.load_png_from_buffer(image_bytes)
			if image_error != OK:
				image = null
		elif resource_path.begins_with("res://") and ResourceLoader.exists(resource_path, "Texture2D"):
			var resource := ResourceLoader.load(resource_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
			if resource is Texture2D:
				image = (resource as Texture2D).get_image()
		if image == null or image.is_empty():
			_append_issue(issues, &"shipping_binding_file_missing", "Shipping texture is unavailable as raw PNG or an imported Godot texture.", asset_id)
		elif Vector2i(image.get_size()) != declared_size:
			_append_issue(issues, &"shipping_binding_size_mismatch", "Shipping texture pixels do not match the declared size.", asset_id)
		elif image.has_mipmaps():
			_append_issue(issues, &"shipping_binding_sampling_invalid", "Shipping source image unexpectedly contains mipmaps.", asset_id)
		else:
			var actual_rgba8_sha256 := _sha256_image_rgba8(image)
			if actual_rgba8_sha256 != declared_rgba8_sha256:
				_append_issue(issues, &"shipping_binding_pixel_hash_mismatch", "Shipping decoded RGBA8 pixels do not match the declared SHA-256.", asset_id)
			if not _image_has_binary_clean_alpha(image):
				_append_issue(issues, &"shipping_binding_alpha_invalid", "Shipping texture must use binary alpha with zero RGB in transparent pixels.", asset_id)

	var bindings := bindings_variant as Array
	var parsed_bindings: Array[Dictionary] = []
	var local_binding_keys: Dictionary = {}
	var local_consumer_keys: Dictionary = {}
	for binding_variant: Variant in bindings:
		if not binding_variant is Dictionary:
			_append_issue(issues, &"shipping_binding_entry_invalid", "Shipping binding entry must be an object.", asset_id)
			continue
		var parsed := _validate_binding_entry(
			binding_variant as Dictionary,
			asset_id,
			declared_size,
			reserved_binding_keys,
			reserved_consumer_keys,
			local_binding_keys,
			local_consumer_keys,
			issues,
			content
		)
		if not parsed.is_empty():
			parsed_bindings.append(parsed)
	if not issues.is_empty() or image == null or image.is_empty():
		return {"issues": issues}

	var handles: Dictionary = {}
	var content_bindings: Dictionary = {}
	var zone_bindings: Dictionary = {}
	var global_bindings: Dictionary = {}
	for binding: Dictionary in parsed_bindings:
		var texture := _texture_for_binding(image, binding)
		if texture == null:
			_append_issue(issues, &"shipping_binding_texture_derivation_failed", "Validated atlas binding could not be converted into its exact display texture.", asset_id)
			return {"issues": issues}
		var handle := GogoStaticAssetHandle.new()
		handle._configure(binding, texture)
		var asset_key := String(binding.get("asset_key", ""))
		handles[asset_key] = handle
		for consumer: Dictionary in binding.get("consumers", []) as Array[Dictionary]:
			var consumer_key := String(consumer.get("consumer_key", ""))
			match String(consumer.get("kind", "")):
				"content": content_bindings[consumer_key] = asset_key
				"zone": zone_bindings[consumer_key] = asset_key
				"global": global_bindings[consumer_key] = asset_key
	return {
		"issues": issues,
		"handles": handles,
		"content_bindings": content_bindings,
		"zone_bindings": zone_bindings,
		"global_bindings": global_bindings,
		"binding_keys": local_binding_keys,
		"consumer_keys": local_consumer_keys,
	}


static func _texture_for_binding(source: Image, binding: Dictionary) -> Texture2D:
	if source == null or source.is_empty():
		return null
	var atlas_rect: Rect2i = binding.get("atlas_rect_px", Rect2i(0, 0, -1, -1))
	var display_size: Vector2i = binding.get("display_size_px", Vector2i(-1, -1))
	if not _rect_fits(atlas_rect, source.get_size()) or display_size.x <= 0 or display_size.y <= 0:
		return null
	var slice := source.get_region(atlas_rect)
	if slice == null or slice.is_empty():
		return null
	slice.convert(Image.FORMAT_RGBA8)
	if slice.get_size() != display_size:
		slice.resize(display_size.x, display_size.y, Image.INTERPOLATE_NEAREST)
	if slice.get_size() != display_size:
		return null
	return ImageTexture.create_from_image(slice)


func _validate_binding_entry(
	binding: Dictionary,
	asset_id: StringName,
	source_size: Vector2i,
	reserved_binding_keys: Dictionary,
	reserved_consumer_keys: Dictionary,
	local_binding_keys: Dictionary,
	local_consumer_keys: Dictionary,
	issues: Array[Dictionary],
	content: ContentSnapshot
) -> Dictionary:
	var role := StringName(String(binding.get("role", "")))
	var selector := StringName(String(binding.get("selector", "")))
	var binding_key := String(binding.get("binding_key", ""))
	var expected_key := _asset_key(asset_id, role, selector)
	if role.is_empty() or binding_key != expected_key:
		_append_issue(issues, &"shipping_binding_key_invalid", "Binding key must exactly match asset_id|role|selector and use a non-empty role.", asset_id)
		return {}
	if reserved_binding_keys.has(binding_key) or local_binding_keys.has(binding_key):
		_append_issue(issues, &"shipping_binding_key_duplicate", "Static shipping binding key is duplicated.", asset_id)
		return {}
	local_binding_keys[binding_key] = true

	var atlas_rect := _rect2i_from_json(binding.get("atlas_rect_px"))
	if atlas_rect.size.x <= 0 or atlas_rect.size.y <= 0 or not _rect_fits(atlas_rect, source_size):
		_append_issue(issues, &"shipping_binding_atlas_rect_invalid", "Binding atlas rectangle is empty or outside the shipping texture.", asset_id)
		return {}
	var display_size := _vector2i_from_json(binding.get("display_size_px"))
	var display_scale := _vector2_from_json(binding.get("display_scale"))
	# JSON numbers arrive as doubles, while Vector2 components are stored at the
	# engine's real_t precision. Quantize the expected ratio through Vector2 too,
	# then keep the exact comparison. This accepts an exact 1254→418 one-third
	# mapping without relaxing the rejection of merely approximate scales.
	var expected_display_scale := Vector2.ZERO
	if atlas_rect.size.x > 0 and atlas_rect.size.y > 0:
		expected_display_scale = Vector2(
			float(display_size.x) / float(atlas_rect.size.x),
			float(display_size.y) / float(atlas_rect.size.y)
		)
	if (
		display_size.x <= 0
		or display_size.y <= 0
		or not display_scale.is_finite()
		or display_scale.x <= 0.0
		or display_scale.y <= 0.0
		or not _has_exact_integer_ratio(atlas_rect.size, display_size)
		or display_scale != expected_display_scale
	):
		_append_issue(issues, &"shipping_binding_display_mapping_invalid", "Binding display mapping must be an exact integer up/down ratio with an explicit matching scale.", asset_id)
		return {}
	var pivot := _vector2i_from_json(binding.get("pivot_px"))
	if pivot.x < 0 or pivot.y < 0 or pivot.x >= display_size.x or pivot.y >= display_size.y:
		_append_issue(issues, &"shipping_binding_pivot_invalid", "Binding pivot must be an integer point inside the display rectangle.", asset_id)
		return {}
	var anchors := _anchors_from_json(binding.get("anchors_px"), display_size, asset_id, issues)
	var consumers := _consumers_from_json(
		binding.get("consumers", []),
		role,
		selector,
		asset_id,
		reserved_consumer_keys,
		local_consumer_keys,
		issues,
		content
	)
	return {
		"binding_key": StringName(binding_key),
		"asset_key": binding_key,
		"asset_id": asset_id,
		"role": role,
		"selector": selector,
		"display_size_px": display_size,
		"display_scale": display_scale,
		"pivot_px": pivot,
		"anchors_px": anchors,
		"atlas_rect_px": atlas_rect,
		"consumers": consumers,
	}


func _consumers_from_json(
	value: Variant,
	default_role: StringName,
	default_selector: StringName,
	asset_id: StringName,
	reserved_consumer_keys: Dictionary,
	local_consumer_keys: Dictionary,
	issues: Array[Dictionary],
	content: ContentSnapshot
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		_append_issue(issues, &"shipping_binding_consumers_invalid", "Binding consumers must be an array.", asset_id)
		return result
	for consumer_variant: Variant in value as Array:
		if not consumer_variant is Dictionary:
			_append_issue(issues, &"shipping_binding_consumer_invalid", "Binding consumer must be an object.", asset_id)
			continue
		var consumer := consumer_variant as Dictionary
		var kind := StringName(String(consumer.get("kind", "")))
		var role := StringName(String(consumer.get("role", default_role)))
		var selector := StringName(String(consumer.get("selector", default_selector)))
		var consumer_key := ""
		match kind:
			&"content":
				var content_kind := StringName(String(consumer.get("content_kind", "")))
				var content_id := StringName(String(consumer.get("content_id", "")))
				if content_kind.is_empty() or content_id.is_empty() or role != &"icon" or not selector.is_empty():
					_append_issue(issues, &"shipping_binding_consumer_invalid", "Content consumer requires a kind, ID, icon role, and no selector.", asset_id)
					continue
				if not content.has_definition(content_id, content_kind):
					_append_issue(issues, &"shipping_binding_consumer_unresolved", "Content consumer does not exist in the staged content snapshot.", asset_id)
					continue
				var definition := content.definition(content_id, content_kind)
				if definition == null or definition.icon_asset_id != asset_id:
					_append_issue(issues, &"shipping_binding_consumer_asset_mismatch", "Content consumer does not explicitly name this asset as its icon.", asset_id)
					continue
				consumer_key = _binding_key(content_kind, content_id, role)
			&"zone":
				var zone_id := StringName(String(consumer.get("zone_id", "")))
				if zone_id.is_empty() or role != asset_id:
					_append_issue(issues, &"shipping_binding_consumer_asset_mismatch", "Zone consumer role must exactly equal the bound asset ID.", asset_id)
					continue
				if not content.has_definition(zone_id, &"zone"):
					_append_issue(issues, &"shipping_binding_consumer_unresolved", "Zone consumer does not exist in the staged content snapshot.", asset_id)
					continue
				consumer_key = _binding_key(&"zone", zone_id, role, selector)
			&"global":
				if role != asset_id:
					_append_issue(issues, &"shipping_binding_consumer_asset_mismatch", "Global consumer role must exactly equal the bound asset ID.", asset_id)
					continue
				consumer_key = _binding_key(&"global", &"", role, selector)
			_:
				_append_issue(issues, &"shipping_binding_consumer_invalid", "Unknown binding consumer kind.", asset_id)
				continue
		if reserved_consumer_keys.has(consumer_key) or local_consumer_keys.has(consumer_key):
			_append_issue(issues, &"shipping_binding_consumer_duplicate", "Static shipping consumer key is duplicated.", asset_id)
			continue
		local_consumer_keys[consumer_key] = true
		result.append({"kind": kind, "consumer_key": consumer_key})
	return result


func _registry_unit_map(registry: Dictionary, issues: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	if String(registry.get("schema_version", "")) != "gogobro-static-assets-v1":
		_append_issue(issues, &"shipping_registry_schema_mismatch", "Canonical static registry schema is unexpected.")
	var units_variant: Variant = registry.get("units")
	if not units_variant is Array:
		_append_issue(issues, &"shipping_registry_units_invalid", "Canonical static registry units must be an array.")
		return result
	for unit_variant: Variant in units_variant as Array:
		if not unit_variant is Dictionary:
			continue
		var unit := unit_variant as Dictionary
		if String(unit.get("category", "")) == "character_creature":
			continue
		var asset_id := StringName(String(unit.get("asset_id", "")))
		if asset_id.is_empty() or result.has(asset_id):
			_append_issue(issues, &"shipping_registry_asset_id_invalid", "Canonical non-character registry IDs must be unique and non-empty.", asset_id)
			continue
		result[asset_id] = unit
	if result.size() != EXPECTED_NONCHARACTER_UNITS:
		_append_issue(issues, &"shipping_registry_count_invalid", "Canonical static registry must contain exactly 70 non-character units.")
	return result


static func _has_authorized_approval_evidence(
	registry_unit: Dictionary,
	shipping_sha256: String,
	rgba8_sha256: String,
	pixel_size: Vector2i,
	runtime_bindings: Array
) -> bool:
	if STATIC_ASSET_REGISTRY.has_authorized_shipping_approval_evidence(
		registry_unit,
		shipping_sha256,
		rgba8_sha256,
		pixel_size,
		runtime_bindings
	):
		return true
	var active_candidate_id := String(registry_unit.get("active_candidate_id", ""))
	if active_candidate_id.is_empty():
		return false
	var history_variant: Variant = registry_unit.get("candidate_history")
	if not history_variant is Array:
		return false
	var active_candidate: Dictionary = {}
	var active_matches := 0
	for candidate_variant: Variant in history_variant as Array:
		if not candidate_variant is Dictionary:
			continue
		var candidate := candidate_variant as Dictionary
		if String(candidate.get("candidate_id", "")) != active_candidate_id:
			continue
		active_matches += 1
		active_candidate = candidate
	if (
		active_matches != 1
		or String(active_candidate.get("decision", "")) != "review"
		or String(active_candidate.get("harmony_verdict", "")) != "harmony_pass"
		or String(active_candidate.get("runtime_bindings_sha256", "")).to_upper()
		!= _canonical_variant_sha256(runtime_bindings)
	):
		return false
	var artifact_match := false
	var artifacts_variant: Variant = active_candidate.get("artifacts")
	if artifacts_variant is Array:
		for artifact_variant: Variant in artifacts_variant as Array:
			if not artifact_variant is Dictionary:
				continue
			var artifact := artifact_variant as Dictionary
			var output_spec_variant: Variant = artifact.get("output_spec")
			var artifact_output_size := Vector2i(-1, -1)
			if output_spec_variant is Dictionary:
				artifact_output_size = _vector2i_from_json([
					(output_spec_variant as Dictionary).get("width", -1),
					(output_spec_variant as Dictionary).get("height", -1),
				])
			if (
				String(artifact.get("sha256", "")).to_upper() == shipping_sha256
				and String(artifact.get("rgba8_sha256", "")).to_upper() == rgba8_sha256
				and _vector2i_from_json(artifact.get("pixel_size")) == pixel_size
				and output_spec_variant is Dictionary
				and String((output_spec_variant as Dictionary).get("format", "")).to_upper() == "PNG"
				and artifact_output_size == pixel_size
			):
				artifact_match = true
				break
	if not artifact_match:
		return false
	var approval_variant: Variant = registry_unit.get("approval_history")
	if not approval_variant is Array or (approval_variant as Array).size() != 1:
		return false
	var event_variant: Variant = (approval_variant as Array)[0]
	if not event_variant is Dictionary:
		return false
	var event := event_variant as Dictionary
	if event.size() != 4:
		return false
	for field: String in ["candidate_id", "decision", "authority", "approved_at_utc"]:
		if not event.has(field):
			return false
	if (
		String(event.get("candidate_id", "")) != active_candidate_id
		or String(event.get("decision", "")) != "approved"
		or not STATIC_ASSET_REGISTRY.is_allowed_candidate_approval_authority(
			String(event.get("authority", ""))
		)
	):
		return false
	var timestamp_pattern := RegEx.new()
	if timestamp_pattern.compile("^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$") != OK:
		return false
	return timestamp_pattern.search(String(event.get("approved_at_utc", ""))) != null


static func _canonical_variant_sha256(value: Variant) -> String:
	return JSON.stringify(value, "", true).sha256_text().to_upper()


func _degraded_snapshot(
	generation: int,
	code: StringName,
	message: String,
	extra_issues: Array[Dictionary] = []
) -> GogoStaticAssetSnapshot:
	var issues := extra_issues.duplicate(true)
	_append_issue(issues, code, message)
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(generation, "", EXPECTED_NONCHARACTER_UNITS, {}, {}, {}, {}, {}, issues)
	return snapshot


static func _append_issue(
	issues: Array[Dictionary],
	code: StringName,
	message: String,
	asset_id: StringName = &""
) -> void:
	issues.append({"code": code, "message": message, "asset_id": asset_id})


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode().to_upper()


static func _sha256_image_rgba8(source: Image) -> String:
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	return _sha256_bytes(image.get_data())


static func _asset_key(asset_id: StringName, role: StringName, selector: StringName) -> String:
	return "%s|%s|%s" % [asset_id, role, selector]


static func _binding_key(
	kind: StringName,
	consumer_id: StringName,
	role: StringName,
	selector: StringName = &""
) -> String:
	return "%s|%s|%s|%s" % [kind, consumer_id, role, selector]


static func _normalized_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path()


static func _normalized_root(path: String) -> String:
	var result := _normalized_path(path)
	if not result.ends_with("/"):
		result += "/"
	return result


func _path_is_within_allowed_root(path: String) -> bool:
	return not path.is_empty() and path.begins_with(_allowed_asset_root)


static func _vector2i_from_json(value: Variant) -> Vector2i:
	if not value is Array:
		return Vector2i(-1, -1)
	var values := value as Array
	if (
		values.size() != 2
		or not _is_bounded_integer(values[0], 0, MAX_PIXEL_COMPONENT)
		or not _is_bounded_integer(values[1], 0, MAX_PIXEL_COMPONENT)
	):
		return Vector2i(-1, -1)
	return Vector2i(int(values[0]), int(values[1]))


static func _vector2_from_json(value: Variant) -> Vector2:
	if not value is Array:
		return Vector2(-1.0, -1.0)
	var values := value as Array
	if values.size() != 2 or not _is_finite_number(values[0]) or not _is_finite_number(values[1]):
		return Vector2(-1.0, -1.0)
	return Vector2(float(values[0]), float(values[1]))


static func _rect2i_from_json(value: Variant) -> Rect2i:
	if not value is Array:
		return Rect2i(0, 0, -1, -1)
	var values := value as Array
	if values.size() != 4:
		return Rect2i(0, 0, -1, -1)
	for component: Variant in values:
		if not _is_bounded_integer(component, 0, MAX_PIXEL_COMPONENT):
			return Rect2i(0, 0, -1, -1)
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


static func _is_integral_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var number := float(value)
		return is_finite(number) and number == roundf(number)
	return false


static func _is_bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not _is_integral_number(value):
		return false
	if value is int:
		return int(value) >= minimum and int(value) <= maximum
	var number := float(value)
	return number >= float(minimum) and number <= float(maximum)


static func _is_finite_number(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(float(value)))


static func _rect_fits(rect: Rect2i, source_size: Vector2i) -> bool:
	return (
		rect.position.x >= 0
		and rect.position.y >= 0
		and rect.size.x > 0
		and rect.size.y > 0
		and rect.size.x <= source_size.x
		and rect.size.y <= source_size.y
		and rect.position.x <= source_size.x - rect.size.x
		and rect.position.y <= source_size.y - rect.size.y
	)


static func _has_exact_integer_ratio(source_size: Vector2i, display_size: Vector2i) -> bool:
	if source_size.x <= 0 or source_size.y <= 0 or display_size.x <= 0 or display_size.y <= 0:
		return false
	return (
		(source_size.x % display_size.x == 0 or display_size.x % source_size.x == 0)
		and (source_size.y % display_size.y == 0 or display_size.y % source_size.y == 0)
	)


static func _anchors_from_json(
	value: Variant,
	display_size: Vector2i,
	asset_id: StringName,
	issues: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		_append_issue(issues, &"shipping_binding_anchors_invalid", "Binding anchors must be an object.", asset_id)
		return result
	for anchor_name: Variant in (value as Dictionary).keys():
		var name := StringName(String(anchor_name))
		var point := _vector2i_from_json((value as Dictionary)[anchor_name])
		if (
			name.is_empty()
			or point.x < 0
			or point.y < 0
			or point.x >= display_size.x
			or point.y >= display_size.y
		):
			_append_issue(issues, &"shipping_binding_anchor_invalid", "Binding anchor must be a named integer point inside the display rectangle.", asset_id)
			continue
		result[name] = point
	return result


static func _image_has_binary_clean_alpha(source: Image) -> bool:
	var image := source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var color: Color = image.get_pixel(x, y)
			var alpha := int(roundf(color.a * 255.0))
			if alpha != 0 and alpha != 255:
				return false
			if alpha == 0 and (
				int(roundf(color.r * 255.0)) != 0
				or int(roundf(color.g * 255.0)) != 0
				or int(roundf(color.b * 255.0)) != 0
			):
				return false
	return true


static func _merge_unique(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		target[key] = source[key]
