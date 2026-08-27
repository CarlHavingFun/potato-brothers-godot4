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

	var app_scene := load("res://game/app/app_root.tscn") as PackedScene
	var app := app_scene.instantiate() as AppKernel
	get_root().add_child(app)
	await process_frame
	await process_frame
	if not _require(app.boot_result != null and app.boot_result.is_ok(), "application boot"):
		return
	var main_menu := (app.get_node("SceneHost") as Node).get_child(0) as Control
	var menu_actions := main_menu.get_node_or_null("ContentRoot/Body/MenuActions") as VBoxContainer
	var start_button := main_menu.get_node_or_null(
		"ContentRoot/Body/MenuActions/StartButton"
	) as Button
	var exit_button := main_menu.get_node_or_null(
		"ContentRoot/Body/MenuActions/ExitButton"
	) as Button
	if not _require(
		menu_actions != null
		and start_button != null
		and exit_button != null
		and menu_actions.size.x <= 320.0
		and start_button.size == Vector2(320, 48)
		and exit_button.size == Vector2(320, 48),
		"real main-menu buttons remain compact"
	):
		return
	var start_position := start_button.position
	var start_size := start_button.size
	start_button.grab_focus()
	await process_frame
	if not _require(
		start_button.position == start_position
		and start_button.size == start_size
		and Rect2(Vector2.ZERO, menu_actions.size).encloses(
			Rect2(start_button.position, start_button.size)
		)
		and Rect2(Vector2.ZERO, menu_actions.size).encloses(
			Rect2(exit_button.position, exit_button.size)
		),
		"real main-menu focus keeps both buttons within MenuActions"
	):
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
