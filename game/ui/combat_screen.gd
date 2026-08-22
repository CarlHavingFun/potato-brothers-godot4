extends Node2D

var world: CombatWorld
var health_label: Label
var wave_label: Label
var time_label: Label


func _ready() -> void:
	var app := AppContext.kernel(self)
	if app == null or app.current_session == null:
		return
	world = CombatWorld.new()
	add_child(world)
	_build_hud()
	world.hud_changed.connect(_on_hud_changed)
	world.wave_completed.connect(_on_wave_completed)
	world.run_failed.connect(_on_run_failed)
	var session := app.current_session
	var zone := session.content_snapshot.definition(session.run_state.zone_id, &"zone") as GogoZoneDefinition
	var wave_id := zone.wave_ids[session.run_state.current_wave - 1]
	var wave := session.content_snapshot.definition(wave_id, &"wave") as GogoWaveDefinition
	var error := world.start_wave(session, wave)
	if error != OK:
		app.route(FlowRoute.DIAGNOSTIC, {"message": "战斗启动失败", "details": [error_string(error)]})


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.position = Vector2(24.0, 20.0)
	bar.add_theme_constant_override("separation", 24)
	layer.add_child(bar)
	health_label = Label.new()
	wave_label = Label.new()
	time_label = Label.new()
	bar.add_child(health_label)
	bar.add_child(wave_label)
	bar.add_child(time_label)
	var hint := Label.new()
	hint.text = "WASD 移动 · 武器自动攻击"
	hint.position = Vector2(24.0, 58.0)
	layer.add_child(hint)


func _on_hud_changed(health: float, maximum: float, time_left: float, wave: int) -> void:
	health_label.text = "生命 %.0f / %.0f" % [health, maximum]
	wave_label.text = "第 %d / 5 波" % wave
	time_label.text = "剩余 %.1f 秒" % time_left


func _on_wave_completed() -> void:
	var app := AppContext.kernel(self)
	var save_error := app.save_checkpoint()
	if save_error != OK:
		app.route(FlowRoute.DIAGNOSTIC, {"message": "波次存档失败", "details": [app.profile_service.last_error]})
		return
	var route_id := FlowRoute.UPGRADE if app.current_session.run_state.phase == &"upgrade" else FlowRoute.SHOP
	app.route(route_id)


func _on_run_failed() -> void:
	AppContext.kernel(self).route(FlowRoute.SETTLEMENT)
