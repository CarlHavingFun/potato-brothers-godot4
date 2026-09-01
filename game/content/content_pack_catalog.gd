class_name ContentPackCatalog
extends RefCounted

signal pending_changes_changed(has_changes: bool)
signal active_packs_changed(pack_ids: Array[StringName])

var _installed: Dictionary = {}
var _enabled: Dictionary = {}
var _pending_enabled: Dictionary = {}


func install(pack: GogoContentPackDefinition, enabled: bool = true) -> Error:
	if pack == null or not pack.is_valid() or _installed.has(pack.pack_id):
		return ERR_INVALID_DATA
	_installed[pack.pack_id] = pack
	_enabled[pack.pack_id] = enabled
	_pending_enabled[pack.pack_id] = enabled
	return OK


func stage_enabled(pack_id: StringName, enabled: bool) -> Error:
	if not _installed.has(pack_id):
		return ERR_DOES_NOT_EXIST
	_pending_enabled[pack_id] = enabled
	pending_changes_changed.emit(has_pending_changes())
	return OK


func has_pending_changes() -> bool:
	return _pending_enabled != _enabled


func apply_at_main_menu(registry: GogoContentRegistry, current_route: StringName) -> ContentSnapshot:
	var prepared := prepare_at_main_menu(registry, current_route)
	if prepared.is_empty() or commit_prepared(prepared) != OK: return null
	return prepared.snapshot


# Builds the captured selection without publishing active state or commit signals.
func prepare_at_main_menu(registry: GogoContentRegistry, current_route: StringName) -> Dictionary:
	if current_route != FlowRoute.MAIN_MENU and not current_route.is_empty():
		return {}
	var enabled := _pending_enabled.duplicate()
	var packs: Array[GogoContentPackDefinition] = []
	for pack_id: StringName in _installed:
		if bool(enabled.get(pack_id, false)):
			packs.append(_installed[pack_id] as GogoContentPackDefinition)
	var snapshot := registry.build_snapshot(packs)
	if snapshot == null:
		return {}
	return {"snapshot": snapshot, "enabled": enabled}


func commit_prepared(prepared: Dictionary) -> Error:
	if not prepared.get("snapshot") is ContentSnapshot or not prepared.get("enabled") is Dictionary:
		return ERR_INVALID_DATA
	_enabled = prepared.enabled.duplicate()
	active_packs_changed.emit(active_pack_ids())
	# A synchronous observer can stage a newer selection. Do not erase or hide it.
	pending_changes_changed.emit(has_pending_changes())
	return OK


func active_pack_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for pack_id: StringName in _enabled:
		if bool(_enabled[pack_id]):
			result.append(pack_id)
	result.sort()
	return result


func installed_packs() -> Array[GogoContentPackDefinition]:
	var result: Array[GogoContentPackDefinition] = []
	for pack: GogoContentPackDefinition in _installed.values():
		result.append(pack)
	return result
