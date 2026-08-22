class_name GogoModLoaderAdapter
extends RefCounted

const REQUIRED_API_MAJOR := 7

var available := false
var active_profile := GogoModProfile.new()


func initialize(current_route: StringName) -> Error:
	if current_route != FlowRoute.MAIN_MENU and not current_route.is_empty():
		return ERR_BUSY
	var tree := Engine.get_main_loop() as SceneTree
	available = tree != null and tree.root.has_node("ModLoader")
	return OK


func request_profile_change(profile: GogoModProfile, current_route: StringName) -> Error:
	if current_route != FlowRoute.MAIN_MENU:
		return ERR_BUSY
	if profile == null or profile.profile_id.is_empty():
		return ERR_INVALID_PARAMETER
	active_profile = profile.duplicate(true) as GogoModProfile
	return OK


func requires_restart() -> bool:
	return true
