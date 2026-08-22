extends GogoScreenBase


func _ready() -> void:
	build_screen("GOGOBRO", "Godot 4 独立重写 · 内容与 Mod 仅在主菜单重载")
	add_action("开始新游戏", _start_new_run)
	add_action("退出", func() -> void: get_tree().quit())


func _start_new_run() -> void:
	var app := AppContext.kernel(self)
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
