class_name PlatformService
extends RefCounted

var provider: StringName = &"offline"
var available := false


func initialize() -> Error:
	available = false
	provider = &"offline"
	return OK


func set_rich_presence(_key: String, _value: String) -> Error:
	return OK if available else ERR_UNAVAILABLE
