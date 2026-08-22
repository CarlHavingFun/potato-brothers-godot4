class_name WorkshopService
extends RefCounted


func installed_mod_paths() -> PackedStringArray:
	return PackedStringArray()


func request_refresh(current_route: StringName) -> Error:
	return OK if current_route == FlowRoute.MAIN_MENU else ERR_BUSY
