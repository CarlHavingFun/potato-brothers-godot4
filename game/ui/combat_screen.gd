extends Node2D

var world: CombatWorld
var health_label: Label
var wave_label: Label
var time_label: Label
var static_asset_snapshot_override: GogoStaticAssetSnapshot


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
	layer.name = "HUDCanvas"
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.name = "HUDMetrics"
	bar.position = Vector2(24.0, 20.0)
	bar.add_theme_constant_override("separation", 24)
	layer.add_child(bar)
	health_label = _add_hud_metric(bar, &"health", "HealthMetric")
	wave_label = _add_hud_metric(bar, &"wave", "WaveMetric")
	time_label = _add_hud_metric(bar, &"wave_timer", "WaveTimerMetric")
	_build_control_hint(layer)


func _add_hud_metric(parent: HBoxContainer, selector: StringName, node_name: String) -> Label:
	var metric := HBoxContainer.new()
	metric.name = node_name
	metric.custom_minimum_size.y = 64.0
	metric.add_theme_constant_override("separation", 8)
	parent.add_child(metric)
	var texture := _resolve_global_texture(&"hud_icon_kit", selector)
	if texture != null:
		metric.add_child(_make_icon(texture, "%sIcon" % selector))
	var label := Label.new()
	label.name = "%sLabel" % selector
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	metric.add_child(label)
	return label


func _build_control_hint(layer: CanvasLayer) -> void:
	var row := HBoxContainer.new()
	row.name = "ControlHint"
	row.position = Vector2(24.0, 100.0)
	row.add_theme_constant_override("separation", 12)
	layer.add_child(row)
	var entries := [
		{"selector": &"move_keyboard_wasd", "label": "WASD"},
		{"selector": &"move_gamepad_left_stick", "label": "左摇杆"},
		{"selector": &"auto_attack", "label": "自动攻击"},
	]
	var resolved := 0
	for entry: Dictionary in entries:
		var selector := entry.get("selector", &"") as StringName
		var texture := _resolve_global_texture(&"control_icon_kit", selector)
		if texture == null:
			continue
		var group := HBoxContainer.new()
		group.name = "%sControl" % selector
		group.add_theme_constant_override("separation", 6)
		group.add_child(_make_icon(texture, "%sIcon" % selector))
		var label := Label.new()
		label.text = String(entry.get("label", ""))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(label)
		row.add_child(group)
		resolved += 1
	if resolved == 0:
		var fallback := Label.new()
		fallback.name = "ControlHintFallback"
		fallback.text = "WASD 移动 · 武器自动攻击"
		row.add_child(fallback)


func _make_icon(texture: Texture2D, node_name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _resolve_global_texture(asset_id: StringName, selector: StringName) -> Texture2D:
	var snapshot := static_asset_snapshot_override
	if snapshot == null:
		var app := AppContext.kernel(self)
		if app == null or app.static_asset_service == null:
			return null
		snapshot = app.static_asset_service.active_snapshot()
	if snapshot == null:
		return null
	var handle := snapshot.resolve_global(asset_id, selector)
	return handle.texture if handle != null else null


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
