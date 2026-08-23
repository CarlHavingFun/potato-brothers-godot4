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
const ACTIVE_ITEM_REQUIRED_ARTIFACT_ROLES := [
	"icon",
	"appearance",
	"anchors",
	"composite_frame",
	"composite_atlas",
	"runtime_preview",
	"harmony_overlay",
	"harmony_actual_size",
	"approval_card",
	"pixel_qa_report",
	"harmony_report",
	"visual_rubric",
]
const CANDIDATE_ARTIFACT_ROLE_SETS := {
	"candidate-001": [
		"icon", "appearance", "anchors", "composite_frame", "composite_atlas",
		"runtime_preview", "approval_card", "qa_report", "icon_request", "appearance_request",
	],
	"candidate-002": ACTIVE_ITEM_REQUIRED_ARTIFACT_ROLES,
}
const CANDIDATE_001_PROVENANCE := {
	"prompt_version": "gogobro-static-v1",
	"request_artifact_roles": ["icon_request", "appearance_request"],
}
const CANDIDATE_002_SOURCE_KEYS := [
	"appearance_source",
	"candidate_001_tree",
	"card_font_bold",
	"card_font_regular",
	"niko_atlas",
	"registry",
	"rig_profile",
]
const CANDIDATE_002_SOURCE_TREE_SIZE := 52
const CANDIDATE_002_SOURCE_FINGERPRINT := "0a4cceb86f1805c54ee01f4c04ee761bd7079e5b091cae3ac0a502e328832f4d"
const OBSOLETE_SINGLE_CANDIDATE_FIELDS := ["candidate_id", "candidate_provenance", "candidate_artifacts"]
const CANDIDATE_ARTIFACT_OUTPUT_SPEC_VARIANTS := {
	"icon": [{"format": "PNG", "width": 256, "height": 256, "alpha": true}],
	"appearance": [
		{"format": "PNG", "width": 128, "height": 128, "alpha": true},
		{"format": "PNG", "width": 128, "height": 128, "alpha": true, "appearance_mode": "RIGID"},
	],
	"anchors": [{"format": "JSON", "state": "walk_down", "anchor_count": 8}],
	"composite_frame": [{"format": "PNG", "width": 128, "height": 128, "alpha": true}],
	"composite_atlas": [
		{"format": "PNG", "width": 1024, "height": 128, "alpha": true},
		{"format": "PNG", "width": 1024, "height": 128, "alpha": true, "columns": 8, "frame_width": 128, "frame_height": 128},
	],
	"runtime_preview": [
		{"format": "PNG", "width": 1920, "height": 1080},
		{"format": "PNG", "width": 1920, "height": 1080, "alpha": true},
	],
	"harmony_overlay": [{"format": "PNG", "width": 1024, "height": 128, "alpha": true}],
	"harmony_actual_size": [{"format": "PNG", "width": 1920, "height": 1080, "alpha": true}],
	"approval_card": [
		{"format": "PNG", "width": 1800, "height": 1200},
		{"format": "PNG", "width": 1800, "height": 1200, "alpha": true},
	],
	"qa_report": [{"format": "JSON"}],
	"pixel_qa_report": [{"format": "JSON"}],
	"harmony_report": [{"format": "JSON"}],
	"visual_rubric": [{"format": "JSON"}],
	"icon_request": [{"format": "JSON", "purpose": "provenance"}],
	"appearance_request": [{"format": "JSON", "purpose": "provenance"}],
}
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
	var raw_json := FileAccess.get_file_as_string(path)
	if _has_invalid_byte_literals(raw_json):
		errors.append("candidate artifact has invalid byte size")
		return {"registry": {}, "errors": errors}
	var json := JSON.new()
	if json.parse(raw_json) != OK:
		errors.append("registry is not valid JSON: %s" % json.get_error_message())
		return {"registry": {}, "errors": errors}
	if not json.data is Dictionary:
		errors.append("registry root must be an object")
		return {"registry": {}, "errors": errors}
	var registry := json.data as Dictionary
	_normalize_candidate_artifact_byte_sizes(registry)
	errors.append_array(validate_registry(registry))
	return {"registry": registry, "errors": errors}


static func _has_invalid_byte_literals(raw_json: String) -> bool:
	var index := 0
	while index < raw_json.length():
		if raw_json[index] != "\"":
			index += 1
			continue
		var string_end := _json_string_end(raw_json, index)
		if string_end < 0:
			return false
		var decoded: Variant = JSON.parse_string(raw_json.substr(index, string_end - index + 1))
		var cursor := _skip_json_whitespace(raw_json, string_end + 1)
		if decoded == "bytes" and cursor < raw_json.length() and raw_json[cursor] == ":":
			cursor = _skip_json_whitespace(raw_json, cursor + 1)
			var literal_start := cursor
			if cursor >= raw_json.length() or raw_json[cursor] < "1" or raw_json[cursor] > "9":
				return true
			while cursor < raw_json.length() and raw_json[cursor] >= "0" and raw_json[cursor] <= "9":
				cursor += 1
			if not _is_positive_base_ten_integer_literal(raw_json.substr(literal_start, cursor - literal_start)):
				return true
			cursor = _skip_json_whitespace(raw_json, cursor)
			if cursor >= raw_json.length() or not [",", "}", "]"].has(raw_json[cursor]):
				return true
		index = string_end + 1
	return false


static func _json_string_end(raw_json: String, start: int) -> int:
	var index := start + 1
	while index < raw_json.length():
		if raw_json[index] == "\\":
			index += 2
			continue
		if raw_json[index] == "\"":
			return index
		index += 1
	return -1


static func _skip_json_whitespace(raw_json: String, start: int) -> int:
	var index := start
	while index < raw_json.length() and [" ", "\t", "\r", "\n"].has(raw_json[index]):
		index += 1
	return index


static func _is_positive_base_ten_integer_literal(literal: String) -> bool:
	if literal.is_empty() or not literal.is_valid_int():
		return false
	var value := literal.to_int()
	return value > 0 and literal == str(value)


static func _normalize_candidate_artifact_byte_sizes(registry: Dictionary) -> void:
	var units: Variant = registry.get("units")
	if not units is Array:
		return
	for unit_variant in units as Array:
		if not unit_variant is Dictionary:
			continue
		var history: Variant = (unit_variant as Dictionary).get("candidate_history")
		if not history is Array:
			continue
		for candidate_variant in history as Array:
			if not candidate_variant is Dictionary:
				continue
			var artifacts: Variant = (candidate_variant as Dictionary).get("artifacts")
			if not artifacts is Array:
				continue
			for artifact_variant in artifacts as Array:
				if artifact_variant is Dictionary and (artifact_variant as Dictionary).get("bytes") is float:
					(artifact_variant as Dictionary)["bytes"] = int((artifact_variant as Dictionary).get("bytes"))


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
		if approval_status == "review" or unit.has("active_candidate_id") or unit.has("candidate_history"):
			_validate_candidate_history(unit, label, category, errors)
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


static func _validate_candidate_history(unit: Dictionary, label: String, category: String, errors: PackedStringArray) -> void:
	if str(unit.get("approval_status", "")) != "review":
		errors.append("candidate history unit approval_status must remain review")
	for obsolete_field in OBSOLETE_SINGLE_CANDIDATE_FIELDS:
		if unit.has(obsolete_field):
			errors.append("candidate history unit must not contain obsolete field: %s" % obsolete_field)
	var active_candidate_id := str(unit.get("active_candidate_id", "")).strip_edges()
	if active_candidate_id.is_empty():
		errors.append("%s review unit missing active_candidate_id" % label)
	var history_variant: Variant = unit.get("candidate_history")
	if not history_variant is Array or (history_variant as Array).is_empty():
		errors.append("%s review unit missing candidate_history" % label)
		return
	var candidate_ids := {}
	var review_count := 0
	var active_matches := 0
	var active_candidate := {}
	for candidate_variant in history_variant as Array:
		if not candidate_variant is Dictionary:
			errors.append("candidate history entry must be an object")
			continue
		var candidate := candidate_variant as Dictionary
		var candidate_id := str(candidate.get("candidate_id", "")).strip_edges()
		if candidate_id.is_empty():
			errors.append("candidate history entry missing candidate_id")
		elif candidate_ids.has(candidate_id):
			errors.append("duplicate candidate_id: %s" % candidate_id)
		else:
			candidate_ids[candidate_id] = true
		var decision := str(candidate.get("decision", "")).strip_edges()
		if decision == "review":
			review_count += 1
		elif decision == "revision_requested":
			var reasons: Variant = candidate.get("reasons")
			if not reasons is Array or (reasons as Array).is_empty():
				errors.append("revision_requested candidate missing reasons")
			var provenance: Variant = candidate.get("provenance")
			if not provenance is Dictionary or str((provenance as Dictionary).get("prompt_version", "")).strip_edges().is_empty():
				errors.append("revision_requested candidate missing prompt provenance")
			if candidate_id == "candidate-001" and provenance != CANDIDATE_001_PROVENANCE:
				errors.append("candidate-001 provenance must match preserved canonical record")
		else:
			errors.append("candidate history entry has invalid decision: %s" % decision)
		var artifacts: Variant = candidate.get("artifacts")
		if not artifacts is Array or (artifacts as Array).is_empty():
			if decision == "revision_requested":
				errors.append("revision_requested candidate missing artifacts")
			else:
				errors.append("candidate %s missing artifacts" % candidate_id)
		else:
			_validate_candidate_artifacts(artifacts as Array, candidate_id, str(unit.get("asset_id", "")), errors)
		if candidate_id == active_candidate_id:
			active_matches += 1
			active_candidate = candidate
	if active_matches != 1:
		errors.append("active_candidate_id must resolve exactly once")
	if review_count != 1:
		errors.append("candidate history must contain exactly one review decision")
	if candidate_ids.size() != CANDIDATE_ARTIFACT_ROLE_SETS.size():
		errors.append("candidate history must contain the exact canonical candidate ids")
	else:
		for expected_candidate_id in CANDIDATE_ARTIFACT_ROLE_SETS:
			if not candidate_ids.has(expected_candidate_id):
				errors.append("candidate history must contain the exact canonical candidate ids")
				break
	if active_matches == 1:
		if str(active_candidate.get("decision", "")) != "review":
			errors.append("active candidate decision must be review")
		_validate_active_candidate(active_candidate, category, errors)


static func _validate_candidate_artifacts(artifacts: Array, candidate_id: String, asset_id: String, errors: PackedStringArray) -> void:
	var roles := {}
	for artifact_variant in artifacts:
		if not artifact_variant is Dictionary:
			errors.append("candidate artifact must be an object")
			continue
		var artifact := artifact_variant as Dictionary
		var role := str(artifact.get("role", "")).strip_edges()
		if role.is_empty():
			errors.append("candidate artifact missing role")
			continue
		if roles.has(role):
			errors.append("duplicate candidate artifact role: %s" % role)
		else:
			roles[role] = true
		var path := str(artifact.get("path", ""))
		if path != path.strip_edges():
			errors.append("candidate artifact %s path must stay within exact candidate root" % role)
		elif path.is_empty():
			errors.append("candidate artifact %s missing path" % role)
		elif path.begins_with("res://"):
			errors.append("candidate artifact %s path must stay outside runtime res://" % role)
		elif path.to_lower().contains("/curated/"):
			errors.append("candidate artifact %s path must not contain /curated/" % role)
		elif not path.begins_with("workspace://") or path.contains("\\"):
			errors.append("candidate artifact %s path must use a workspace:// forward-slash path" % role)
		elif not _is_exact_candidate_artifact_path(path, asset_id, candidate_id):
			errors.append("candidate artifact %s path must stay within exact candidate root" % role)
		var sha256 := str(artifact.get("sha256", "")).strip_edges()
		if not _is_valid_sha256(sha256):
			errors.append("candidate artifact %s has invalid sha256" % role)
		var bytes: Variant = artifact.get("bytes")
		if not bytes is int:
			errors.append("candidate artifact %s has invalid byte size" % role)
		elif bytes <= 0:
			errors.append("candidate artifact %s has invalid byte size" % role)
		var output_spec: Variant = artifact.get("output_spec")
		if not output_spec is Dictionary or (output_spec as Dictionary).is_empty() or str((output_spec as Dictionary).get("format", "")).strip_edges().is_empty():
			errors.append("candidate artifact %s missing structured output_spec" % role)
		elif CANDIDATE_ARTIFACT_OUTPUT_SPEC_VARIANTS.has(role) and not _output_spec_matches_any(output_spec as Dictionary, CANDIDATE_ARTIFACT_OUTPUT_SPEC_VARIANTS[role] as Array):
			errors.append("candidate artifact %s output_spec must match required specification" % role)
	var expected_roles: Array = CANDIDATE_ARTIFACT_ROLE_SETS.get(candidate_id, []) as Array
	if roles.size() != expected_roles.size():
		errors.append("candidate %s artifact roles must match exact required set" % candidate_id)
	else:
		for expected_role in expected_roles:
			if not roles.has(expected_role):
				errors.append("candidate %s artifact roles must match exact required set" % candidate_id)
				break


static func _is_exact_candidate_artifact_path(path: String, asset_id: String, candidate_id: String) -> bool:
	if path.contains("?") or path.contains("#") or path.contains("%") or path.contains("\\"):
		return false
	var candidate_root := "workspace://GOGOBRO_ASSET_INBOX/02_static_assets/items/%s/%s/" % [asset_id, candidate_id]
	if not path.begins_with(candidate_root):
		return false
	var relative_path := path.substr(candidate_root.length())
	if relative_path.is_empty():
		return false
	for segment in relative_path.split("/", true):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _validate_active_candidate(candidate: Dictionary, category: String, errors: PackedStringArray) -> void:
	var harmony_verdict := str(candidate.get("harmony_verdict", "")).strip_edges()
	if not ["harmony_pass", "review"].has(harmony_verdict):
		errors.append("active candidate harmony_verdict must be harmony_pass or review")
	var roles := {}
	for artifact_variant in candidate.get("artifacts", []) as Array:
		if artifact_variant is Dictionary:
			roles[str((artifact_variant as Dictionary).get("role", ""))] = true
	if category == "item":
		for required_role in ACTIVE_ITEM_REQUIRED_ARTIFACT_ROLES:
			if not roles.has(required_role):
				errors.append("active candidate missing required artifact role: %s" % required_role)
	var report_verdicts: Variant = candidate.get("report_verdicts")
	if not report_verdicts is Dictionary:
		errors.append("active candidate missing report verdicts")
	else:
		if (report_verdicts as Dictionary).get("pixel_qa_passed") != true:
			errors.append("active candidate pixel QA report must pass")
		if not ["harmony_pass", "review"].has(str((report_verdicts as Dictionary).get("harmony", ""))):
			errors.append("active candidate harmony report has invalid verdict")
	var visual_rubric_sha256 := str(candidate.get("visual_rubric_sha256", "")).strip_edges()
	if not _is_valid_sha256(visual_rubric_sha256):
		errors.append("active candidate has invalid visual rubric sha256")
	var metrics: Variant = candidate.get("metrics")
	if not metrics is Dictionary or (metrics as Dictionary).is_empty():
		errors.append("active candidate missing harmony metrics")
	elif str((metrics as Dictionary).get("visual_rubric_sha256", "")) != visual_rubric_sha256:
		errors.append("active candidate metrics visual rubric sha256 mismatch")
	var font_provenance: Variant = candidate.get("font_provenance")
	if not font_provenance is Dictionary:
		errors.append("active candidate missing font provenance")
	else:
		for font_role in ["regular", "bold"]:
			var font_variant: Variant = (font_provenance as Dictionary).get(font_role)
			if not font_variant is Dictionary or str((font_variant as Dictionary).get("path", "")).strip_edges().is_empty() or not _is_valid_sha256(str((font_variant as Dictionary).get("sha256", ""))):
				errors.append("active candidate has invalid %s font provenance" % font_role)
	var source_sha256: Variant = candidate.get("source_sha256")
	if not source_sha256 is Dictionary or (source_sha256 as Dictionary).is_empty():
		errors.append("active candidate missing source sha256 provenance")
	else:
		_validate_active_candidate_source(source_sha256 as Dictionary, errors)


static func _validate_active_candidate_source(source: Dictionary, errors: PackedStringArray) -> void:
	var exact_shape := source.size() == CANDIDATE_002_SOURCE_KEYS.size()
	for source_key in CANDIDATE_002_SOURCE_KEYS:
		if not source.has(source_key):
			exact_shape = false
	var tree_variant: Variant = source.get("candidate_001_tree")
	if not tree_variant is Dictionary or (tree_variant as Dictionary).size() != CANDIDATE_002_SOURCE_TREE_SIZE:
		exact_shape = false
	else:
		for tree_path in tree_variant as Dictionary:
			if str(tree_path).is_empty() or str(tree_path).contains("\\") or str(tree_path).begins_with("/") or not _is_valid_sha256(str((tree_variant as Dictionary)[tree_path])):
				exact_shape = false
	for source_key in CANDIDATE_002_SOURCE_KEYS:
		if source_key != "candidate_001_tree" and not _is_valid_sha256(str(source.get(source_key, ""))):
			exact_shape = false
	if not exact_shape or _source_provenance_fingerprint(source) != CANDIDATE_002_SOURCE_FINGERPRINT:
		errors.append("active candidate source provenance must match exact generated metadata")


static func _source_provenance_fingerprint(source: Dictionary) -> String:
	var lines := PackedStringArray()
	var source_keys := source.keys()
	source_keys.sort()
	for source_key in source_keys:
		var value: Variant = source[source_key]
		if value is Dictionary:
			var tree_keys := (value as Dictionary).keys()
			tree_keys.sort()
			for tree_key in tree_keys:
				lines.append("%s\t%s\t%s" % [source_key, tree_key, (value as Dictionary)[tree_key]])
		else:
			lines.append("%s\t%s" % [source_key, value])
	return "\n".join(lines).sha256_text()


static func _is_valid_sha256(value: String) -> bool:
	var sha256_pattern := RegEx.new()
	sha256_pattern.compile("^[A-Fa-f0-9]{64}$")
	return sha256_pattern.search(value) != null


static func _output_spec_matches_any(actual: Dictionary, expected_variants: Array) -> bool:
	for expected_variant in expected_variants:
		if expected_variant is Dictionary and _output_spec_matches(actual, expected_variant as Dictionary):
			return true
	return false


static func _output_spec_matches(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for field in expected:
		if not actual.has(field):
			return false
		var expected_value: Variant = expected[field]
		var actual_value: Variant = actual[field]
		if expected_value is int:
			if not actual_value is int and not actual_value is float:
				return false
			if float(actual_value) != float(expected_value):
				return false
		elif actual_value != expected_value:
			return false
	return true


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
