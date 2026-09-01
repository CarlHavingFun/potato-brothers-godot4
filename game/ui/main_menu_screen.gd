extends GogoScreenBase

var _return_button: Button
var _page: Panel


func _ready() -> void:
	use_menu_background_v2 = true
	build_screen("", "")
	body.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	body.position = Vector2(32, -24)
	body.size = Vector2(480, 604)
	body.add_theme_constant_override(&"separation", 24)
	var wordmark := add_static_texture(&"gogobro_wordmark", "Wordmark", Vector2(440, 132))
	wordmark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var actions := VBoxContainer.new()
	actions.name = "MenuActions"
	actions.custom_minimum_size = Vector2(360, 360)
	actions.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	actions.add_theme_constant_override(&"separation", 10)
	body.add_child(actions)
	var buttons: Array[Control] = []
	buttons.append(ui_button(actions, "StartButton", "开始新游戏", Rect2(0, 0, 360, 64), _start_new_run))
	for spec in [["ProfileButton", "档案"], ["CodexButton", "图鉴"], ["SettingsButton", "设置"]]:
		buttons.append(ui_button(actions, spec[0], spec[1], Rect2(0, 0, 360, 64), _open_page.bind(spec[0])))
	buttons.append(ui_button(actions, "ExitButton", "退出", Rect2(0, 0, 360, 64), func() -> void: get_tree().quit()))
	link_focus_cycle(buttons)
	buttons[0].call_deferred("grab_focus")


func _open_page(origin: String) -> void:
	var app := AppContext.kernel(self)
	if app == null or _page != null:
		return
	_return_button = body.get_node("MenuActions/" + origin) as Button
	body.hide()
	_page = ui_panel(self, "MenuPage", Rect2(160, 100, 960, 584))
	var title := ui_label(_page, "Title", Vector2(32, 20), Vector2(880, 48), 32)
	title.text = _return_button.text
	var back := ui_button(_page, "BackButton", "← 返回", Rect2(32, 492, 224, 64), _close_page)
	match origin:
		"ProfileButton":
			ui_label(_page, "CompletedRuns", Vector2(48, 136), Vector2(850, 48), 30).text = "已记录局数  %d" % int(app.profile_service.profile_data.get("completed_runs", 0))
			ui_label(_page, "BestWave", Vector2(48, 216), Vector2(850, 48), 30).text = "最高波次  %d" % int(app.profile_service.profile_data.get("best_wave", 0))
			ui_label(_page, "Note", Vector2(48, 340), Vector2(850, 60), 22).text = "来自本机真实记录；游戏结算后更新。"
			back.call_deferred("grab_focus")
		"CodexButton":
			_build_codex(app, back)
		"SettingsButton":
			_build_settings(app, back)


func _close_page() -> void:
	if _page == null:
		return
	remove_child(_page)
	_page.queue_free()
	_page = null
	body.show()
	_return_button.grab_focus()


func _build_codex(app: AppKernel, back: Button) -> void:
	ui_label(_page, "SnapshotNote", Vector2(32, 72), Vector2(896, 30), 19).text = "当前内容快照 · 可浏览实际内容，不代表解锁记录"
	var categories := OptionButton.new()
	categories.name = "Categories"
	categories.position = Vector2(32, 116)
	categories.size = Vector2(340, 48)
	HUD_SKIN.apply_action_button(categories, &"compact", false, true)
	_page.add_child(categories)
	for spec in [["角色", "character"], ["武器", "weapon"], ["道具", "item"], ["升级", "upgrade"], ["难度", "difficulty"]]:
		categories.add_item(spec[0])
		categories.set_item_metadata(categories.item_count - 1, spec[1])
	var entries := ItemList.new()
	entries.name = "Entries"
	entries.position = Vector2(32, 180)
	entries.size = Vector2(340, 288)
	entries.add_theme_font_size_override("font_size", 22)
	entries.add_theme_constant_override("v_separation", 12)
	_page.add_child(entries)
	var detail := ui_label(_page, "EntryDetail", Vector2(400, 124), Vector2(520, 336), 22)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entries.item_selected.connect(func(index: int) -> void:
		var id := StringName(entries.get_item_metadata(index))
		var definition := app.content_snapshot.definition(id, StringName(categories.get_item_metadata(categories.selected)))
		detail.text = "%s\n\n%s\n\n%s" % [definition.display_name, id, definition.get_meta(&"description", "当前快照中的实际内容。")])
	categories.item_selected.connect(func(index: int) -> void:
		entries.clear()
		for definition in app.content_snapshot.all(StringName(categories.get_item_metadata(index))):
			entries.add_item(definition.display_name)
			entries.set_item_metadata(entries.item_count - 1, definition.content_id)
		if entries.item_count > 0:
			entries.select(0)
			entries.item_selected.emit(0)
		else:
			detail.text = "当前快照无此类内容。")
	categories.item_selected.emit(0)
	link_focus_cycle([categories, entries, back])
	categories.call_deferred("grab_focus")


func _build_settings(app: AppKernel, back: Button) -> void:
	var controls: Array[Control] = []
	var specs := [["master_volume", "主音量"], ["music_volume", "音乐音量"], ["effects_volume", "音效音量"]]
	for index in specs.size():
		var key: String = specs[index][0]
		var y := 124 + index * 84
		ui_label(_page, key + "Label", Vector2(48, y), Vector2(240, 40), 24).text = specs[index][1]
		var slider := HSlider.new()
		slider.name = key
		slider.position = Vector2(294, y + 4)
		slider.size = Vector2(448, 36)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(app.settings_service.values[key])
		_page.add_child(slider)
		var amount := ui_label(_page, key + "Value", Vector2(778, y), Vector2(120, 40), 24)
		amount.text = "%d%%" % roundi(slider.value * 100)
		slider.value_changed.connect(func(value: float) -> void: amount.text = "%d%%" % roundi(value * 100))
		controls.append(slider)
	var fullscreen := CheckButton.new()
	fullscreen.name = "Fullscreen"
	fullscreen.position = Vector2(48, 380)
	fullscreen.size = Vector2(320, 64)
	fullscreen.text = "全屏显示"
	fullscreen.add_theme_font_size_override("font_size", 24)
	fullscreen.button_pressed = bool(app.settings_service.values["fullscreen"])
	_page.add_child(fullscreen)
	controls.append(fullscreen)
	var status := ui_label(_page, "Status", Vector2(400, 396), Vector2(496, 40), 20)
	var save := ui_button(_page, "SaveButton", "应用并保存", Rect2(648, 492, 280, 64), func() -> void:
		for spec in specs:
			app.settings_service.values[spec[0]] = (_page.get_node(spec[0]) as HSlider).value
		app.settings_service.values["fullscreen"] = fullscreen.button_pressed
		app.settings_service.apply_display_settings()
		if app.audio_service != null:
			app.audio_service.apply_settings(app.settings_service)
		var error := app.settings_service.save_settings()
		status.text = "已应用并保存" if error == OK else "保存失败：" + error_string(error))
	controls.append(save)
	controls.append(back)
	link_focus_cycle(controls)
	controls[0].call_deferred("grab_focus")


func _unhandled_key_input(event: InputEvent) -> void:
	if _page != null and event.is_action_pressed("ui_cancel"):
		_close_page()
		get_viewport().set_input_as_handled()


func _start_new_run() -> void:
	var app := AppContext.kernel(self)
	app.begin_selection()
	app.route(FlowRoute.CHARACTER_SELECT)
