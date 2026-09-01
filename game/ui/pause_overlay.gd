class_name GogoPauseOverlay
extends Control


signal continue_requested
signal restart_requested
signal end_run_requested
signal return_to_menu_requested

const VIEWPORT_SIZE := Vector2(1280, 720)
const TEXT_COLOR := Color("f3edd7")
const MUTED_COLOR := Color("b8b29f")
const DANGER_COLOR := Color("ef6a67")
const LOADOUT_PRESENTER := preload("res://game/ui/loadout_strip_presenter.gd")
const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")

var _pending_confirmation: StringName = &""
var _confirmation_source: Button
var _continue_button: Button
var _settings_button: Button
var _confirmation: Panel
var _confirmation_label: Label
var _settings_panel: Panel


func _init() -> void:
	name = "PauseOverlay"
	custom_minimum_size = VIEWPORT_SIZE
	size = VIEWPORT_SIZE
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_static_hierarchy()


func configure(
	player: SessionPlayerState,
	content: ContentSnapshot,
	static_assets: GogoStaticAssetSnapshot,
	current_wave: int,
	total_waves: int,
	seconds_remaining: float,
	endless: bool = false
) -> void:
	_build_loadout(player, content, static_assets)
	_build_stats(player, content)
	var wave_progress := get_node("WaveProgress") as Panel
	(wave_progress.get_node("Wave") as Label).text = "波次 %d / %d" % [
		maxi(current_wave, 0),
		maxi(total_waves, 1),
	]
	if endless:
		(wave_progress.get_node("Wave") as Label).text = "无尽 · 第 %d 波" % current_wave
	(wave_progress.get_node("Time") as Label).text = "剩余 %d 秒" % ceili(
		maxf(seconds_remaining, 0.0)
	)
	var progress := wave_progress.get_node("Progress") as ProgressBar
	progress.visible = not endless
	progress.max_value = maxi(total_waves, 1)
	progress.value = clampi(current_wave, 0, maxi(total_waves, 1))


func open() -> void:
	visible = true
	_confirmation.visible = false
	_settings_panel.visible = false
	_pending_confirmation = &""
	_confirmation_source = null
	_continue_button.call_deferred("grab_focus")


func close() -> void:
	visible = false
	_confirmation.visible = false
	_settings_panel.visible = false
	_pending_confirmation = &""
	_confirmation_source = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		continue_requested.emit()


func _build_static_hierarchy() -> void:
	var dim := ColorRect.new()
	dim.name = "DimVeil"
	dim.color = Color(0.0, 0.0, 0.0, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var menu := _panel("PauseMenu", Vector2(32, 88), Vector2(260, 480))
	add_child(menu)
	var title := _label("Title", "暂停", Vector2(20, 14), Vector2(220, 48), 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	var button_specs := [
		["ContinueButton", "继续", Callable(self, "_request_continue"), false],
		["RestartButton", "重新开始本波", Callable(self, "_request_restart"), false],
		["EndRunButton", "结束本局", Callable(self, "_request_end_run"), true],
		["SettingsButton", "设置", Callable(self, "_open_settings"), false],
		["ReturnButton", "返回主菜单", Callable(self, "_request_return"), true],
	]
	for index in button_specs.size():
		var spec: Array = button_specs[index]
		var button := _button(
			String(spec[0]),
			String(spec[1]),
			Vector2(20, 78 + index * 68),
			Vector2(220, 56),
			bool(spec[3])
		)
		button.pressed.connect(spec[2] as Callable)
		menu.add_child(button)
		if button.name == "ContinueButton":
			_continue_button = button
		elif button.name == "SettingsButton":
			_settings_button = button

	var loadout_placeholder := Control.new()
	loadout_placeholder.name = "Loadout"
	loadout_placeholder.position = Vector2(316, 88)
	loadout_placeholder.size = Vector2(620, 480)
	add_child(loadout_placeholder)

	var stats := _panel("StatsColumn", Vector2(958, 88), Vector2(290, 480))
	stats.clip_contents = true
	add_child(stats)
	var stats_title := _label("Title", "当前属性", Vector2(16, 12), Vector2(258, 36), 24)
	stats.add_child(stats_title)
	var rows_placeholder := VBoxContainer.new()
	rows_placeholder.name = "Rows"
	rows_placeholder.position = Vector2(16, 54)
	rows_placeholder.size = Vector2(258, 410)
	stats.add_child(rows_placeholder)

	var wave_progress := _panel("WaveProgress", Vector2(316, 592), Vector2(932, 96))
	add_child(wave_progress)
	var wave := _label("Wave", "波次 0 / 1", Vector2(20, 8), Vector2(300, 38), 23)
	wave_progress.add_child(wave)
	var time := _label("Time", "剩余 0 秒", Vector2(652, 8), Vector2(260, 38), 21)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_progress.add_child(time)
	var progress := ProgressBar.new()
	progress.name = "Progress"
	progress.position = Vector2(20, 58)
	progress.size = Vector2(892, 12)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _flat_style(Color("171b1e"), Color.TRANSPARENT, 0))
	progress.add_theme_stylebox_override("fill", _flat_style(Color("f1a34a"), Color.TRANSPARENT, 0))
	wave_progress.add_child(progress)

	_settings_panel = _panel("SettingsPanel", Vector2(420, 218), Vector2(440, 260))
	_settings_panel.visible = false
	_settings_panel.z_index = 20
	add_child(_settings_panel)
	var settings_title := _label("Title", "设置", Vector2(24, 18), Vector2(392, 42), 28)
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_panel.add_child(settings_title)
	var settings_info := _label(
		"Info",
		"移动：WASD / 左摇杆\n自动开火：始终开启\n暂停：Esc / 手柄菜单键",
		Vector2(36, 74),
		Vector2(368, 90),
		18
	)
	settings_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_settings_panel.add_child(settings_info)
	var settings_close := _button("CloseButton", "返回暂停菜单", Vector2(100, 184), Vector2(240, 56), false)
	settings_close.pressed.connect(_close_settings)
	_settings_panel.add_child(settings_close)

	_confirmation = _panel("ExitConfirmation", Vector2(420, 232), Vector2(440, 220))
	_confirmation.visible = false
	_confirmation.z_index = 30
	add_child(_confirmation)
	_confirmation_label = _label(
		"Message",
		"确认？",
		Vector2(28, 24),
		Vector2(384, 86),
		22
	)
	_confirmation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirmation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirmation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation.add_child(_confirmation_label)
	var cancel := _button("CancelButton", "取消", Vector2(28, 138), Vector2(180, 56), false)
	cancel.pressed.connect(_cancel_confirmation)
	_confirmation.add_child(cancel)
	var confirm := _button("ConfirmButton", "确认", Vector2(232, 138), Vector2(180, 56), true)
	confirm.pressed.connect(_confirm_danger_action)
	_confirmation.add_child(confirm)


func _build_loadout(
	player: SessionPlayerState,
	content: ContentSnapshot,
	static_assets: GogoStaticAssetSnapshot
) -> void:
	var previous := get_node_or_null("Loadout") as Control
	var insertion_index := previous.get_index() if previous != null else 2
	if previous != null:
		remove_child(previous)
		previous.free()
	var loadout := LOADOUT_PRESENTER.build(
		player,
		content,
		static_assets,
		{"expanded": true}
	) as Control
	loadout.name = "Loadout"
	loadout.position = Vector2(316, 88)
	loadout.custom_minimum_size = Vector2(620, 480)
	loadout.size = Vector2(620, 480)
	loadout.clip_contents = true
	var items_scroll := loadout.get_node("ItemsScroll") as ScrollContainer
	items_scroll.position = Vector2(20, 202)
	items_scroll.size = Vector2(580, 258)
	var weapons := loadout.get_node("Weapons") as HBoxContainer
	weapons.position = Vector2(20, 54)
	weapons.size = Vector2(452, 72)
	for button: Button in loadout.find_children("*", "Button", true, false):
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var weapons_title := _label(
		"WeaponsTitle",
		"武器 %d/6" % player.weapon_ids.size(),
		Vector2(20, 8),
		Vector2(580, 34),
		22
	)
	loadout.add_child(weapons_title)
	loadout.add_child(_section_divider("WeaponsDivider", Vector2(20, 42)))
	var items_title := _label("ItemsTitle", "道具", Vector2(20, 154), Vector2(580, 34), 22)
	loadout.add_child(items_title)
	loadout.add_child(_section_divider("ItemsDivider", Vector2(20, 188)))
	add_child(loadout)
	move_child(loadout, insertion_index)


func _build_stats(player: SessionPlayerState, content: ContentSnapshot) -> void:
	var stats := get_node("StatsColumn") as Panel
	var previous := stats.get_node_or_null("Rows") as Control
	if previous != null:
		stats.remove_child(previous)
		previous.free()
	var rows := STAT_LIST_PRESENTER.build(player, content) as VBoxContainer
	rows.name = "Rows"
	rows.position = Vector2(16, 54)
	rows.size = Vector2(258, 410)
	stats.add_child(rows)


func _request_continue() -> void:
	continue_requested.emit()


func _request_restart() -> void:
	restart_requested.emit()


func _request_end_run() -> void:
	_show_confirmation(
		&"end_run",
		"确定结束本局并进入结算吗？",
		get_node("PauseMenu/EndRunButton") as Button
	)


func _request_return() -> void:
	_show_confirmation(
		&"return_to_menu",
		"确定放弃本局并返回主菜单吗？",
		get_node("PauseMenu/ReturnButton") as Button
	)


func _show_confirmation(mode: StringName, message: String, source: Button) -> void:
	_pending_confirmation = mode
	_confirmation_source = source
	_confirmation_label.text = message
	_confirmation.visible = true
	(_confirmation.get_node("CancelButton") as Button).call_deferred("grab_focus")


func _cancel_confirmation() -> void:
	_confirmation.visible = false
	_pending_confirmation = &""
	var source := _confirmation_source
	_confirmation_source = null
	if source != null and is_instance_valid(source):
		source.call_deferred("grab_focus")


func _confirm_danger_action() -> void:
	var confirmed := _pending_confirmation
	_confirmation.visible = false
	_pending_confirmation = &""
	_confirmation_source = null
	match confirmed:
		&"end_run":
			end_run_requested.emit()
		&"return_to_menu":
			return_to_menu_requested.emit()


func _open_settings() -> void:
	_settings_panel.visible = true
	(_settings_panel.get_node("CloseButton") as Button).call_deferred("grab_focus")


func _close_settings() -> void:
	_settings_panel.visible = false
	_settings_button.call_deferred("grab_focus")


func _panel(node_name: String, at: Vector2, rect_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = at
	panel.size = rect_size
	var variant: StringName = &"soft"
	if node_name == "StatsColumn":
		variant = &"stats"
	elif node_name in ["SettingsPanel", "ExitConfirmation"]:
		variant = &"dialog"
	HUD_SKIN.apply_panel(panel, variant)
	return panel


func _label(
	node_name: String,
	text: String,
	at: Vector2,
	rect_size: Vector2,
	font_size: int
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = at
	label.size = rect_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color("111416"))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(
	node_name: String,
	text: String,
	at: Vector2,
	rect_size: Vector2,
	danger: bool
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.position = at
	button.size = rect_size
	button.focus_mode = Control.FOCUS_ALL
	HUD_SKIN.apply_action_button(button, &"standard", danger, true)
	button.custom_minimum_size = rect_size
	return button


func _section_divider(node_name: String, at: Vector2) -> ColorRect:
	var divider := ColorRect.new()
	divider.name = node_name
	divider.position = at
	divider.size = Vector2(580, 2)
	divider.color = Color(0.74, 0.71, 0.64, 0.42)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


static func _flat_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style
