extends GogoScreenBase


func _ready() -> void:
	build_screen("", "像素 CSGO 生存竞技 · 内容与 Mod 仅在主菜单重载")
	add_static_texture(&"gogobro_wordmark", "Wordmark", Vector2(460, 115))
	var actions := VBoxContainer.new()
	actions.name = "MenuActions"
	actions.custom_minimum_size = Vector2(320, 104)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override(&"separation", 8)
	body.add_child(actions)
	var start_button := Button.new()
	start_button.name = "StartButton"
	start_button.custom_minimum_size = Vector2(320, 48)
	configure_action_button(start_button, "开始新游戏", _start_new_run)
	actions.add_child(start_button)
	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.custom_minimum_size = Vector2(320, 48)
	configure_action_button(exit_button, "退出", func() -> void: get_tree().quit())
	actions.add_child(exit_button)


func _start_new_run() -> void:
	var app := AppContext.kernel(self)
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
