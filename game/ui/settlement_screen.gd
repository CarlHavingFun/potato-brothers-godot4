extends GogoScreenBase


func _ready() -> void:
	var app := AppContext.kernel(self)
	var state := app.current_session.run_state if app.current_session != null else null
	var victory := state != null and state.won
	var progress := "到达第 %d 波" % (state.current_wave if state != null else 0)
	if state != null and state.endless:
		progress = "无尽 · 到达第 %d 波（常规 %d 波已完成）" % [state.current_wave, state.total_waves]
	build_screen("胜利" if victory else "本局结束", progress)
	if state != null:
		var player := state.player()
		add_info("等级 %d · 金币 %d · 武器 %d · 物品 %d" % [player.level, player.materials, player.weapon_ids.size(), player.item_ids.size()])
	add_action("返回主菜单", _return_to_menu)


func _return_to_menu() -> void:
	var app := AppContext.kernel(self)
	app.close_session(true)
	app.route(FlowRoute.MAIN_MENU)
