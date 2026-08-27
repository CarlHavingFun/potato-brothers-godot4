class_name GogoStaticAssetSnapshot
extends RefCounted

const DEFAULT_EXPECTED_NONCHARACTER_UNITS := 70

var generation: int = 0
var registry_sha256: String = ""
var _expected_count: int = DEFAULT_EXPECTED_NONCHARACTER_UNITS
var _states: Dictionary = {}
var _handles: Dictionary = {}
var _content_bindings: Dictionary = {}
var _zone_bindings: Dictionary = {}
var _global_bindings: Dictionary = {}
var _issues: Array[Dictionary] = []
var _development_preview := false


func _configure(
	next_generation: int,
	next_registry_sha256: String,
	next_expected_count: int,
	next_states: Dictionary,
	next_handles: Dictionary,
	next_content_bindings: Dictionary,
	next_zone_bindings: Dictionary,
	next_global_bindings: Dictionary,
	next_issues: Array[Dictionary]
) -> void:
	generation = next_generation
	registry_sha256 = next_registry_sha256
	_expected_count = next_expected_count
	_states = next_states.duplicate(true)
	_handles = next_handles.duplicate()
	_content_bindings = next_content_bindings.duplicate(true)
	_zone_bindings = next_zone_bindings.duplicate(true)
	_global_bindings = next_global_bindings.duplicate(true)
	_issues = next_issues.duplicate(true)


func resolve_asset(asset_id: StringName, role: StringName, selector: StringName = &"") -> GogoStaticAssetHandle:
	return _handles.get(_asset_key(asset_id, role, selector)) as GogoStaticAssetHandle


func resolve_content(kind: StringName, content_id: StringName, role: StringName) -> GogoStaticAssetHandle:
	var asset_key: String = _content_bindings.get(_binding_key(kind, content_id, role), "")
	return _handles.get(asset_key) as GogoStaticAssetHandle


func resolve_zone(zone_id: StringName, role: StringName, selector: StringName = &"") -> GogoStaticAssetHandle:
	var asset_key: String = _zone_bindings.get(_binding_key(&"zone", zone_id, role, selector), "")
	return _handles.get(asset_key) as GogoStaticAssetHandle


func resolve_global(role: StringName, selector: StringName = &"") -> GogoStaticAssetHandle:
	var asset_key: String = _global_bindings.get(_binding_key(&"global", &"", role, selector), "")
	return _handles.get(asset_key) as GogoStaticAssetHandle


func state_for_asset(asset_id: StringName) -> StringName:
	return _states.get(asset_id, &"inactive")


func issues() -> Array[Dictionary]:
	return _issues.duplicate(true)


func ready_count() -> int:
	var count := 0
	for state: Variant in _states.values():
		if state == &"ready":
			count += 1
	return count


func expected_count() -> int:
	return _expected_count


func fallback_count() -> int:
	return maxi(_expected_count - ready_count(), 0)


func release_readiness() -> Dictionary:
	return {
		"generation": generation,
		"expected_noncharacter_units": _expected_count,
		"ready_units": ready_count(),
		"fallback_units": fallback_count(),
		"release_ready": ready_count() == _expected_count and _issues.is_empty(),
		"issues": issues(),
	}


func is_development_preview() -> bool:
	return _development_preview


func with_development_overlay(
	overlay_states: Dictionary,
	overlay_handles: Dictionary,
	overlay_content_bindings: Dictionary,
	overlay_zone_bindings: Dictionary,
	overlay_global_bindings: Dictionary,
	overlay_issues: Array[Dictionary] = []
) -> GogoStaticAssetSnapshot:
	var states := _states.duplicate(true)
	var handles := _handles.duplicate()
	var content_bindings := _content_bindings.duplicate(true)
	var zone_bindings := _zone_bindings.duplicate(true)
	var global_bindings := _global_bindings.duplicate(true)
	states.merge(overlay_states, true)
	handles.merge(overlay_handles, true)
	content_bindings.merge(overlay_content_bindings, true)
	zone_bindings.merge(overlay_zone_bindings, true)
	global_bindings.merge(overlay_global_bindings, true)
	var issues := _issues.duplicate(true)
	issues.append_array(overlay_issues)
	var snapshot := GogoStaticAssetSnapshot.new()
	snapshot._configure(
		generation + 1,
		registry_sha256,
		_expected_count,
		states,
		handles,
		content_bindings,
		zone_bindings,
		global_bindings,
		issues
	)
	snapshot._development_preview = true
	return snapshot


static func _asset_key(asset_id: StringName, role: StringName, selector: StringName) -> String:
	return "%s|%s|%s" % [asset_id, role, selector]


static func _binding_key(
	kind: StringName,
	consumer_id: StringName,
	role: StringName,
	selector: StringName = &""
) -> String:
	return "%s|%s|%s|%s" % [kind, consumer_id, role, selector]
