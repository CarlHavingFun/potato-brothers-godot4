extends GogoScreenBase


func _ready() -> void:
	build_screen("", "像素 CSGO 生存竞技 · 内容与 Mod 仅在主菜单重载")
	add_static_texture(&"gogobro_wordmark", "Wordmark", Vector2(460, 115))
	add_action("开始新游戏", _start_new_run, false, null, "StartButton")
	add_action("退出", func() -> void: get_tree().quit(), false, null, "ExitButton")


func _start_new_run() -> void:
	var app := AppContext.kernel(self)
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
