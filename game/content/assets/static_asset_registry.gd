class_name StaticAssetRegistry
extends RefCounted


const REGISTRY_PATH := "res://game/content/assets/gogobro_static_assets_v1.json"
const EXPECTED_CATEGORY_COUNTS := {
	"character_creature": 5,
	"weapon": 13,
	"projectile_hit_kit": 1,
	"item": 30,
	"upgrade": 6,
	"world": 11,
	"ui_brand": 10,
}
const VALID_STATUSES := ["planned", "generated", "review", "approved", "integrated", "qa_passed"]
const REVIEW_ITEM_REQUIRED_ARTIFACT_ROLES := [
	"icon",
	"appearance",
	"anchors",
	"composite_atlas",
	"runtime_preview",
	"approval_card",
	"qa_report",
]
const REQUIRED_ENTRY_FIELDS := [
	"asset_id",
	"category",
	"content_id",
	"localization",
	"rarity",
	"max_count",
	"prompt_version",
	"output_spec",
	"intended_file_paths",
	"hashes",
	"approval_status",
]


static func load_registry(path: String = REGISTRY_PATH) -> Dictionary:
	var errors := PackedStringArray()
	if not FileAccess.file_exists(path):
		errors.append("registry not found: %s" % path)
		return {"registry": {}, "errors": errors}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("registry is not valid JSON: %s" % json.get_error_message())
		return {"registry": {}, "errors": errors}
	if not json.data is Dictionary:
		errors.append("registry root must be an object")
		return {"registry": {}, "errors": errors}
	var registry := json.data as Dictionary
	errors.append_array(validate_registry(registry))
	return {"registry": registry, "errors": errors}


static func validate_registry(registry: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var units_variant: Variant = registry.get("units")
	if not units_variant is Array:
		errors.append("registry units must be an array")
		return errors
	var units := units_variant as Array
	if units.size() != 76:
		errors.append("expected 76 units, found %d" % units.size())
	var declared_counts: Variant = registry.get("category_counts")
	if not declared_counts is Dictionary or not _counts_match(declared_counts as Dictionary):
		errors.append("category_counts must match the canonical category counts")

	var category_counts := {}
	var asset_ids := {}
	var content_ids := {}
	var snake_case := RegEx.new()
	snake_case.compile("^[a-z][a-z0-9_]*$")

	for index in units.size():
		var unit_variant: Variant = units[index]
		if not unit_variant is Dictionary:
			errors.append("unit %d must be an object" % index)
			continue
		var unit := unit_variant as Dictionary
		var label := "unit %d" % index
		for field in REQUIRED_ENTRY_FIELDS:
			if not unit.has(field):
				errors.append("%s missing %s" % [label, field])
		var asset_id := str(unit.get("asset_id", ""))
		if asset_id.is_empty() or snake_case.search(asset_id) == null:
			errors.append("%s asset_id must be stable lower-snake-case" % label)
		elif asset_ids.has(asset_id):
			errors.append("duplicate asset_id: %s" % asset_id)
		else:
			asset_ids[asset_id] = true
		var content_id := str(unit.get("content_id", ""))
		if content_id.is_empty() or snake_case.search(content_id) == null:
			errors.append("%s content_id must be stable lower-snake-case" % label)
		elif content_ids.has(content_id):
			errors.append("duplicate content_id: %s" % content_id)
		else:
			content_ids[content_id] = true
		var category := str(unit.get("category", ""))
		if not EXPECTED_CATEGORY_COUNTS.has(category):
			errors.append("unknown category: %s" % category)
		else:
			category_counts[category] = int(category_counts.get(category, 0)) + 1
		var approval_status := str(unit.get("approval_status", ""))
		if not VALID_STATUSES.has(approval_status):
			errors.append("unknown approval_status: %s" % approval_status)
		elif approval_status == "review":
			_validate_review_candidate(unit, label, category, errors)
		_validate_localization(
			unit.get("localization"),
			label,
			category in ["character_creature", "weapon", "item", "upgrade"],
			errors
		)
		if category == "item":
			_validate_item(unit, label, errors)
		elif category == "upgrade":
			_validate_upgrade(unit, label, errors)

	for category in EXPECTED_CATEGORY_COUNTS:
		if category_counts.get(category, 0) != EXPECTED_CATEGORY_COUNTS[category]:
			errors.append("category %s expected %d units, found %d" % [
				category,
				EXPECTED_CATEGORY_COUNTS[category],
				category_counts.get(category, 0),
			])
	return errors


static func _counts_match(counts: Dictionary) -> bool:
	if counts.size() != EXPECTED_CATEGORY_COUNTS.size():
		return false
	for category in EXPECTED_CATEGORY_COUNTS:
		if not counts.has(category) or int(counts[category]) != EXPECTED_CATEGORY_COUNTS[category]:
			return false
	return true


static func _validate_localization(localization: Variant, label: String, flavor_required: bool, errors: PackedStringArray) -> void:
	if not localization is Dictionary:
		errors.append("%s localization must be an object" % label)
		return
	var copies := localization as Dictionary
	for locale in ["zh_CN", "en"]:
		var copy: Variant = copies.get(locale)
		if not copy is Dictionary or str((copy as Dictionary).get("name", "")).strip_edges().is_empty():
			errors.append("%s missing %s copy" % [label, "English" if locale == "en" else "Chinese"])
			continue
		var description: Variant = (copy as Dictionary).get("description")
		if not description is String or (description as String).strip_edges().is_empty():
			errors.append("%s missing %s description" % [label, "English" if locale == "en" else "Chinese"])
		elif _contains_numeric_effect_text(description as String):
			errors.append("%s contains handwritten numeric effect text" % label)
		if flavor_required:
			var flavor: Variant = (copy as Dictionary).get("flavor")
			if not flavor is String or (flavor as String).strip_edges().is_empty():
				errors.append("%s missing %s flavor" % [label, "English" if locale == "en" else "Chinese"])
			elif _contains_numeric_effect_text(flavor as String):
				errors.append("%s contains handwritten numeric effect text" % label)


static func _contains_numeric_effect_text(description: String) -> bool:
	for character in description:
		if character >= "0" and character <= "9":
			return true
	return false


static func _validate_review_candidate(unit: Dictionary, label: String, category: String, errors: PackedStringArray) -> void:
	if str(unit.get("candidate_id", "")).strip_edges().is_empty():
		errors.append("%s review unit missing candidate_id" % label)
	var provenance: Variant = unit.get("candidate_provenance")
	if not provenance is Dictionary or str((provenance as Dictionary).get("prompt_version", "")).strip_edges().is_empty():
		errors.append("%s review unit missing candidate prompt provenance" % label)
	var artifacts: Variant = unit.get("candidate_artifacts")
	if not artifacts is Array or (artifacts as Array).is_empty():
		errors.append("%s review unit missing candidate_artifacts" % label)
		return
	var roles := {}
	var sha256_pattern := RegEx.new()
	sha256_pattern.compile("^[A-Fa-f0-9]{64}$")
	for artifact_variant in artifacts as Array:
		if not artifact_variant is Dictionary:
			errors.append("%s candidate artifact must be an object" % label)
			continue
		var artifact := artifact_variant as Dictionary
		var role := str(artifact.get("role", "")).strip_edges()
		if role.is_empty():
			errors.append("%s candidate artifact missing role" % label)
			continue
		roles[role] = true
		var path := str(artifact.get("path", "")).strip_edges()
		if path.is_empty():
			errors.append("candidate artifact %s missing path" % role)
		elif path.begins_with("res://"):
			errors.append("candidate artifact %s path must stay outside runtime res://" % role)
		elif path.to_lower().contains("/curated/"):
			errors.append("candidate artifact %s path must not contain /curated/" % role)
		elif not path.begins_with("workspace://") or path.contains("\\"):
			errors.append("candidate artifact %s path must use a workspace:// forward-slash path" % role)
		var sha256 := str(artifact.get("sha256", "")).strip_edges()
		if sha256_pattern.search(sha256) == null:
			errors.append("candidate artifact %s has invalid sha256" % role)
		var bytes: Variant = artifact.get("bytes")
		if not bytes is int and not bytes is float:
			errors.append("candidate artifact %s has invalid byte size" % role)
		elif int(bytes) <= 0 or float(bytes) != floor(float(bytes)):
			errors.append("candidate artifact %s has invalid byte size" % role)
		var output_spec: Variant = artifact.get("output_spec")
		if not output_spec is Dictionary or (output_spec as Dictionary).is_empty() or str((output_spec as Dictionary).get("format", "")).strip_edges().is_empty():
			errors.append("candidate artifact %s missing structured output_spec" % role)
	if category == "item":
		for required_role in REVIEW_ITEM_REQUIRED_ARTIFACT_ROLES:
			if not roles.has(required_role):
				errors.append("review item missing required candidate artifact role: %s" % required_role)


static func _validate_item(unit: Dictionary, label: String, errors: PackedStringArray) -> void:
	if not unit.get("effects") is Array or (unit.get("effects") as Array).is_empty():
		errors.append("%s item missing effects" % label)
	if not unit.get("rarity") is String or str(unit.get("rarity")).is_empty():
		errors.append("%s item missing rarity" % label)
	if not unit.has("max_count"):
		errors.append("%s item missing max_count" % label)
	var appearance: Variant = unit.get("appearance")
	if not appearance is Dictionary:
		errors.append("%s item missing appearance" % label)
		return
	for field in ["slot", "mode", "depth"]:
		if not (appearance as Dictionary).has(field):
			errors.append("%s item appearance missing %s" % [label, field])


static func _validate_upgrade(unit: Dictionary, label: String, errors: PackedStringArray) -> void:
	var effects: Variant = unit.get("effects")
	if not effects is Array or (effects as Array).is_empty():
		errors.append("%s upgrade missing effects" % label)
		return
	for effect_variant in effects as Array:
		if not effect_variant is Dictionary or not (effect_variant as Dictionary).get("tiers") is Array or ((effect_variant as Dictionary).get("tiers") as Array).size() != 4:
			errors.append("%s upgrade effects must define four structured tiers" % label)
			return
