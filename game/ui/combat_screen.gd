extends Node2D

const PAUSE_OVERLAY := preload("res://game/ui/pause_overlay.gd")
const COMBAT_AUDIO_PRESENTER := preload("res://game/gameplay/feedback/combat_audio_presenter.gd")

var world: CombatWorld
var hud: GogoBrotatoCombatHud
var pause_overlay: Control
var audio_presenter: GogoCombatAudioPresenter
var latest_hud_snapshot: GogoCombatHudSnapshot
var static_asset_snapshot_override: GogoStaticAssetSnapshot


func _ready() -> void:
	var app := AppContext.kernel(self)
	if app == null or app.current_session == null:
		return
	world = CombatWorld.new()
	add_child(world)
	_build_hud()
	_build_pause_overlay()
	world.hud_snapshot_changed.connect(_on_hud_snapshot_changed)
	world.wave_completed.connect(_on_wave_completed)
	world.run_failed.connect(_on_run_failed)
	var session := app.current_session
	var wave := GogoWaveResolver.resolve(session)
	var error := world.start_wave(session, wave)
	if error != OK:
		# Routing inside _ready would race SceneFlow's current-scene commitment.
		app.call_deferred("route", FlowRoute.DIAGNOSTIC, {"message": "战斗启动失败", "details": [error_string(error)]})
		return
	_build_combat_audio(app.audio_service)


func _build_combat_audio(audio_service: GogoAudioService) -> void:
	audio_presenter = COMBAT_AUDIO_PRESENTER.new() as GogoCombatAudioPresenter
	audio_presenter.name = "CombatAudioPresenter"
	audio_presenter.configure(audio_service)
	add_child(audio_presenter)
	_route_combat_audio_events_once(world, audio_presenter)


func _route_combat_audio_events_once(
	next_world: CombatWorld,
	next_presenter: GogoCombatAudioPresenter
) -> void:
	if next_world == null or next_presenter == null:
		return
	_connect_once(next_world.weapon_fired, next_presenter.present_weapon_fired)
	_connect_once(next_world.melee_contact, next_presenter.present_melee_contact)
	_connect_once(next_world.projectile_contact, next_presenter.present_projectile_contact)
	_connect_once(next_world.enemy_defeated, next_presenter.present_enemy_defeated)
	_connect_once(next_world.pickup_collected, next_presenter.present_pickup_collected)
	if next_world.player_actor != null:
		_connect_once(next_world.player_actor.damage_taken, next_presenter.present_player_damage_taken)


func _connect_once(source_signal: Signal, receiver: Callable) -> void:
	if not source_signal.is_connected(receiver):
		source_signal.connect(receiver)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUDCanvas"
	add_child(layer)
	hud = GogoBrotatoCombatHud.new()
	hud.name = "BrotatoHUD"
	var app := AppContext.kernel(self)
	var content: ContentSnapshot
	if app != null and app.current_session != null:
		content = app.current_session.content_snapshot
	hud.configure(null, content, _static_asset_snapshot())
	layer.add_child(hud)


func _build_pause_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PauseCanvas"
	layer.layer = 100
	add_child(layer)
	pause_overlay = PAUSE_OVERLAY.new() as Control
	pause_overlay.name = "PauseOverlay"
	pause_overlay.connect("continue_requested", _resume_from_pause)
	pause_overlay.connect("restart_requested", _restart_wave)
	pause_overlay.connect("end_run_requested", _end_run_from_pause)
	pause_overlay.connect("return_to_menu_requested", _return_to_menu_from_pause)
	layer.add_child(pause_overlay)


func _process(_delta: float) -> void:
	if hud == null:
		return
	hud.note_movement(Input.get_vector("move_left", "move_right", "move_up", "move_down"))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and pause_overlay != null and not pause_overlay.visible:
		get_viewport().set_input_as_handled()
		_open_pause()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _static_asset_snapshot() -> GogoStaticAssetSnapshot:
	if static_asset_snapshot_override != null:
		return static_asset_snapshot_override
	var app := AppContext.kernel(self)
	if app == null or app.static_asset_service == null:
		return null
	return app.static_asset_service.active_snapshot()


func _on_hud_snapshot_changed(snapshot: GogoCombatHudSnapshot) -> void:
	latest_hud_snapshot = snapshot
	if hud != null:
		hud.apply_snapshot(snapshot)


func _open_pause() -> void:
	var app := AppContext.kernel(self)
	if app == null or app.current_session == null or pause_overlay == null:
		return
	var session := app.current_session
	var player := session.run_state.player()
	var total_waves := session.run_state.total_waves
	var seconds_remaining := latest_hud_snapshot.seconds if latest_hud_snapshot != null else 0.0
	pause_overlay.call(
		"configure",
		player,
		session.content_snapshot,
		_static_asset_snapshot(),
		session.run_state.current_wave,
		total_waves,
		seconds_remaining,
		session.run_state.endless
	)
	pause_overlay.call("open")
	get_tree().paused = true


func _resume_from_pause() -> void:
	get_tree().paused = false
	if pause_overlay != null:
		pause_overlay.call("close")


func _restart_wave() -> void:
	_resume_from_pause()
	var app := AppContext.kernel(self)
	if app != null:
		app.route(FlowRoute.COMBAT)


func _end_run_from_pause() -> void:
	_resume_from_pause()
	var app := AppContext.kernel(self)
	if app == null or app.current_session == null:
		return
	app.current_session.fail_run()
	app.route(FlowRoute.SETTLEMENT)


func _return_to_menu_from_pause() -> void:
	_resume_from_pause()
	var app := AppContext.kernel(self)
	if app == null:
		return
	if app.current_session != null:
		app.current_session.fail_run()
		app.close_session(true)
	app.route(FlowRoute.MAIN_MENU)


func _on_wave_completed() -> void:
	var app := AppContext.kernel(self)
	var battlefield_backdrop := _capture_battlefield_backdrop()
	var save_error := app.save_checkpoint()
	if save_error != OK:
		app.route(FlowRoute.DIAGNOSTIC, {"message": "波次存档失败", "details": [app.profile_service.last_error]})
		return
	var route_id := FlowRoute.UPGRADE if app.current_session.run_state.phase == &"upgrade" else FlowRoute.SHOP
	app.route(route_id, {"battlefield_backdrop": battlefield_backdrop})


func _capture_battlefield_backdrop() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var viewport := get_viewport()
	if viewport == null:
		return null
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _on_run_failed() -> void:
	AppContext.kernel(self).route(FlowRoute.SETTLEMENT)
