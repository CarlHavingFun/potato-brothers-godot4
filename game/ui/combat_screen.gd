extends Node2D

var world: CombatWorld
var hud: GogoBrotatoCombatHud
var static_asset_snapshot_override: GogoStaticAssetSnapshot


func _ready() -> void:
	var app := AppContext.kernel(self)
	if app == null or app.current_session == null:
		return
	world = CombatWorld.new()
	add_child(world)
	_build_hud()
	world.hud_snapshot_changed.connect(_on_hud_snapshot_changed)
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
	layer.name = "HUDCanvas"
	add_child(layer)
	hud = GogoBrotatoCombatHud.new()
	hud.name = "BrotatoHUD"
	hud.scale = Vector2(4.0, 4.0)
	var app := AppContext.kernel(self)
	var content: ContentSnapshot
	if app != null and app.current_session != null:
		content = app.current_session.content_snapshot
	hud.configure(null, content, _static_asset_snapshot())
	layer.add_child(hud)


func _process(_delta: float) -> void:
	if hud == null:
		return
	hud.note_movement(Input.get_vector("move_left", "move_right", "move_up", "move_down"))


func _static_asset_snapshot() -> GogoStaticAssetSnapshot:
	if static_asset_snapshot_override != null:
		return static_asset_snapshot_override
	var app := AppContext.kernel(self)
	if app == null or app.static_asset_service == null:
		return null
	return app.static_asset_service.active_snapshot()


func _on_hud_snapshot_changed(snapshot: GogoCombatHudSnapshot) -> void:
	if hud != null:
		hud.apply_snapshot(snapshot)


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
