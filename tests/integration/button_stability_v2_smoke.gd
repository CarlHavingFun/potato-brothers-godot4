extends SceneTree


func _initialize() -> void:
	var screen := GogoScreenBase.new()
	get_root().add_child(screen)
	screen.build_screen("按钮稳定性")
	var button := screen.add_action("测试按钮", func() -> void: pass)
	await process_frame

	if not _require(screen.theme != null, "screen installs the shared stable UI theme"):
		return
	var normal := button.get_theme_stylebox(&"normal") as StyleBoxFlat
	var hover := button.get_theme_stylebox(&"hover") as StyleBoxFlat
	var pressed := button.get_theme_stylebox(&"pressed") as StyleBoxFlat
	if not _require(normal != null and hover != null and pressed != null, "button state styles exist"):
		return
	if not _require(_same_geometry(normal, hover) and _same_geometry(hover, pressed), "button state geometry matches"):
		return

	var position_before := button.position
	var size_before := button.size
	button.grab_focus()
	await process_frame
	if not _require(button.scale == Vector2.ONE, "focus never scales the button"):
		return
	if not _require(button.position == position_before and button.size == size_before, "focus keeps button bounds stationary"):
		return
	print("BUTTON_STABILITY_V2_SMOKE_OK position=%s size=%s" % [button.position, button.size])
	quit(0)


func _same_geometry(left: StyleBoxFlat, right: StyleBoxFlat) -> bool:
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		if left.get_border_width(side) != right.get_border_width(side):
			return false
		if not is_equal_approx(left.get_content_margin(side), right.get_content_margin(side)):
			return false
	return true


func _require(condition: bool, label: String) -> bool:
	if condition:
		return true
	push_error("BUTTON_STABILITY_V2_SMOKE_FAILED: " + label)
	quit(1)
	return false
