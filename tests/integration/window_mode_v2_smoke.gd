extends SceneTree


func _initialize() -> void:
	if not _require(
		int(ProjectSettings.get_setting("display/window/size/mode", -1)) == DisplayServer.WINDOW_MODE_WINDOWED,
		"the project starts in windowed mode"
	):
		return
	if not _require(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)) == 1280
		and int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)) == 720,
		"the initial window is 1280x720"
	):
		return
	if not _require(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1280
		and int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 720,
		"the logical viewport matches the 1280x720 window at exact 1:1 scale"
	):
		return
	if not _require(
		String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "integer"
		and String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep",
		"window resizing preserves aspect ratio and integer pixel scaling"
	):
		return
	if not _require(
		int(ProjectSettings.get_setting("display/window/size/initial_position_type", -1)) == 1,
		"the initial window is centered on the primary screen"
	):
		return

	var settings := GogoSettingsService.new()
	if not _require(settings.has_method("apply_display_settings"), "saved display settings can be applied"):
		return
	if not _require(settings.has_method("resolved_window_mode"), "saved display mode can be resolved"):
		return
	settings.values["fullscreen"] = false
	if not _require(
		int(settings.call("resolved_window_mode")) == DisplayServer.WINDOW_MODE_WINDOWED,
		"the default setting keeps the game windowed"
	):
		return
	settings.values["fullscreen"] = true
	if not _require(
		int(settings.call("resolved_window_mode")) == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"a saved fullscreen preference is preserved"
	):
		return
	print("WINDOW_MODE_V2_SMOKE_OK")
	quit(0)


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	push_error("WINDOW_MODE_V2_SMOKE_FAILED: " + label)
	quit(1)
	return false
