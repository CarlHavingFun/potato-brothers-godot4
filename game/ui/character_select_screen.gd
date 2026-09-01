extends GogoScreenBase

const NIKO_ID := NikoContentFactory.CHARACTER_ID
const ZONE_PRESENTER := preload("res://game/ui/selection_zone_presenter.gd")
const WEAPON_PRESENTER := preload("res://game/ui/selection_weapon_presenter.gd")
const DIFFICULTY_PRESENTER := preload("res://game/ui/selection_difficulty_presenter.gd")
const ROSTER_CAPTION_RECT := Rect2(348, 104, 900, 28)
const ROSTER_RECT := Rect2(348, 140, 900, 488)
const ROSTER_CELL_SIZE := Vector2(143, 116)
const ROSTER_CAPACITY := 24
const ROSTER_COLUMNS := 6
const PLACEHOLDER_STATUS := "未开放"
const CHANGE_CHARACTER_RECT := Rect2(32, 648, 300, 56)
const DETAIL_RECT := Rect2(32, 104, 300, 510)
const TASK_OPTION_RECT := Rect2(1010, 28, 238, 48)
var _zones := ZONE_PRESENTER.new()
var _weapons := WEAPON_PRESENTER.new()
var _difficulties := DIFFICULTY_PRESENTER.new()
var _starting := false
var _character_picker_open := true
var _difficulty_stage_open := false


func _ready() -> void:
	use_menu_background_v2 = true
	build_screen_chrome("出战配置", "依次选择任务、人物、武器与难度")
	selection_title()
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	var niko := app.content_snapshot.definition(NIKO_ID, &"character") as CharacterDefinition
	if niko == null:
		app.route(FlowRoute.DIAGNOSTIC, {
			"message": "角色内容不可用",
			"details": [String(NIKO_ID)],
		})
		return
	_build_progressive_back()
	_build_task_option(app)
	_build_niko_detail(niko)
	_build_roster(niko)
	_character_picker_open = _selected_character(app) == null
	var weapon_stage := Control.new()
	weapon_stage.name = "WeaponStage"
	weapon_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(weapon_stage)
	var difficulty_stage := Control.new()
	difficulty_stage.name = "DifficultyStage"
	difficulty_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(difficulty_stage)
	_weapons.build(self, app, _select_weapon, weapon_stage)
	_difficulties.build(self, app, difficulty_stage, _select_difficulty_and_start)
	_difficulty_stage_open = not _character_picker_open and _configuration_is_valid()
	_sync_selection()
	_focus_initial_control()


func _build_progressive_back() -> void:
	var button := ui_button(
		self,
		"BackButton",
		"← 返回",
		Rect2(32, 24, 168, 56),
		_go_back_one_stage
	)
	button.z_index = 10


func _build_task_option(app: AppKernel) -> void:
	var option := _zones.build(self, app, self, TASK_OPTION_RECT, _select_zone)
	option.z_index = 10


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back_one_stage()


func _go_back_one_stage() -> void:
	if _starting:
		return
	if _character_picker_open:
		var app := AppContext.kernel(self)
		if app != null:
			app.route(FlowRoute.MAIN_MENU)
		return
	if _difficulty_stage_open:
		_difficulty_stage_open = false
		_sync_selection()
		_focus_weapon_or_change()
		return
	_open_character_picker()


func _select_zone(content_id: StringName) -> void:
	if _starting:
		return
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	var definition := app.content_snapshot.definition(content_id, &"zone") as GogoZoneDefinition
	if definition == null:
		return
	app.selection_draft["zone_id"] = definition.content_id
	_zones.apply_selection(definition.content_id)
	_difficulty_stage_open = not _character_picker_open and _configuration_is_valid()
	_sync_selection()
	if _difficulty_stage_open and not _difficulties.buttons.is_empty():
		_difficulties.buttons[0].call_deferred(&"grab_focus")


func _build_niko_detail(niko: CharacterDefinition) -> void:
	var detail := ui_panel(self, "NikoDetail", DETAIL_RECT)
	var name_label := _detail_label(detail, "Name", Vector2(20, 8), Vector2(260, 36), 28)
	name_label.text = niko.display_name
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var role := _detail_label(detail, "Role", Vector2(20, 44), Vector2(260, 26), 18)
	role.text = "已解锁 · 均衡型"
	role.add_theme_color_override(&"font_color", Color("f2a14a"))
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.position = Vector2(70, 72)
	preview.size = Vector2(160, 210)
	preview.texture = _cropped_detail_frame(niko)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(preview)
	_detail_label(detail, "SectionTitle", Vector2(20, 286), Vector2(260, 30), 22).text = "基础属性"
	var traits := _detail_label(detail, "Traits", Vector2(20, 320), Vector2(260, 174), 19)
	traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	traits.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.text = _niko_summary(niko)


func _build_roster(niko: CharacterDefinition) -> void:
	_detail_label(
		self,
		"RosterCaption",
		ROSTER_CAPTION_RECT.position,
		ROSTER_CAPTION_RECT.size,
		20
	).text = "角色档案 · 已解锁 1 / %d" % ROSTER_CAPACITY
	var roster := GridContainer.new()
	roster.name = "RosterStrip"
	roster.position = ROSTER_RECT.position
	roster.size = ROSTER_RECT.size
	roster.columns = ROSTER_COLUMNS
	roster.add_theme_constant_override(&"h_separation", 8)
	roster.add_theme_constant_override(&"v_separation", 8)
	add_child(roster)
	var cell := Button.new()
	cell.name = "NikoCell"
	cell.tooltip_text = niko.display_name
	cell.set_meta(&"content_id", niko.content_id)
	configure_action_button(cell, "", _select_character.bind(niko.content_id))
	cell.custom_minimum_size = ROSTER_CELL_SIZE
	cell.size = ROSTER_CELL_SIZE
	roster.add_child(cell)
	var portrait := TextureRect.new()
	portrait.name = "Preview"
	portrait.position = Vector2(10, 18)
	portrait.size = Vector2(60, 80)
	portrait.texture = _first_frame(niko)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(portrait)
	icon_fallback(cell, "Fallback", portrait.position, portrait.size, niko.display_name).visible = portrait.texture == null
	var slot_index := _detail_label(cell, "SlotIndex", Vector2(9, 4), Vector2(34, 18), 14)
	slot_index.text = "01"
	var availability := _detail_label(cell, "Availability", Vector2(99, 5), Vector2(36, 18), 12)
	availability.text = "可用"
	availability.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var cell_name := _detail_label(cell, "Name", Vector2(76, 29), Vector2(58, 30), 18)
	cell_name.text = niko.display_name
	cell_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var role_tag := _detail_label(cell, "RoleTag", Vector2(76, 65), Vector2(58, 22), 14)
	role_tag.text = "均衡"
	role_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.focus_entered.connect(_sync_character_label)
	cell.focus_exited.connect(_sync_character_label)
	cell.mouse_entered.connect(_sync_character_label)
	cell.mouse_exited.connect(_sync_character_label)
	for slot_number in range(2, ROSTER_CAPACITY + 1):
		var placeholder := Button.new()
		placeholder.name = "UnavailableCharacterSlot%02d" % slot_number
		placeholder.text = ""
		placeholder.tooltip_text = "角色槽位 %02d · %s" % [slot_number, PLACEHOLDER_STATUS]
		placeholder.custom_minimum_size = ROSTER_CELL_SIZE
		placeholder.size = ROSTER_CELL_SIZE
		placeholder.disabled = true
		placeholder.focus_mode = Control.FOCUS_NONE
		placeholder.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		placeholder.set_meta(&"roster_slot", slot_number)
		placeholder.set_meta(&"availability", &"unavailable")
		_apply_placeholder_fill(placeholder, slot_number)
		roster.add_child(placeholder)
		var placeholder_index := _detail_label(
			placeholder, "SlotIndex", Vector2(9, 6), Vector2(38, 18), 14
		)
		placeholder_index.text = "%02d" % slot_number
		placeholder_index.add_theme_color_override(&"font_color", Color("b4c0c8"))
		var lock := _detail_label(placeholder, "Lock", Vector2(93, 7), Vector2(42, 16), 11)
		lock.text = "LOCK"
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lock.add_theme_color_override(&"font_color", Color("d5aa72"))
		var glyph := _detail_label(placeholder, "Glyph", Vector2(0, 20), Vector2(143, 54), 38)
		glyph.text = "?"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_color_override(&"font_color", Color("9aa8b2"))
		glyph.add_theme_constant_override(&"outline_size", 0)
		var divider := ColorRect.new()
		divider.name = "Divider"
		divider.position = Vector2(12, 77)
		divider.size = Vector2(119, 1)
		divider.color = Color(0.42, 0.48, 0.52, 0.42)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder.add_child(divider)
		var status := _detail_label(placeholder, "Status", Vector2(0, 82), Vector2(143, 24), 15)
		status.text = PLACEHOLDER_STATUS
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status.add_theme_color_override(&"font_color", Color("c2cbd1"))
	ui_button(
		self,
		"ChangeCharacterButton",
		"%s · 更换角色" % niko.display_name,
		CHANGE_CHARACTER_RECT,
		_open_character_picker
	)


func _selected_character(app: AppKernel) -> CharacterDefinition:
	if app == null or app.content_snapshot == null:
		return null
	if app.selection_draft.get("character_id", &"") != NIKO_ID:
		return null
	return app.content_snapshot.definition(NIKO_ID, &"character") as CharacterDefinition


func _open_character_picker() -> void:
	var app := AppContext.kernel(self)
	if _selected_character(app) == null:
		return
	_character_picker_open = true
	_difficulty_stage_open = false
	_sync_selection()
	(get_node("RosterStrip/NikoCell") as Button).call_deferred(&"grab_focus")


func _select_character(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	if (
		not _character_picker_open
		or app == null
		or app.content_snapshot == null
		or content_id != NIKO_ID
	):
		return
	if not app.content_snapshot.definition(content_id, &"character") is CharacterDefinition:
		return
	app.selection_draft["character_id"] = content_id
	var weapon := app.content_snapshot.definition(app.selection_draft.get("weapon_id", &""), &"weapon") as GogoWeaponDefinition
	if weapon == null or not (app.content_snapshot.definition(content_id, &"character") as CharacterDefinition).allows_weapon(weapon):
		app.selection_draft["weapon_id"] = &""
	_character_picker_open = false
	_difficulty_stage_open = false
	_sync_selection()
	_focus_weapon_or_change()


func _select_weapon(content_id: StringName) -> void:
	if _character_picker_open:
		return
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	var character := _selected_character(app)
	if character == null:
		return
	for button in _weapons.buttons:
		if button.get_meta(&"content_id") == content_id:
			if not button.visible or button.disabled:
				return
			var weapon := app.content_snapshot.definition(content_id, &"weapon") as GogoWeaponDefinition
			if weapon != null and character.allows_weapon(weapon):
				app.selection_draft["weapon_id"] = content_id
				# A weapon alone is not a launchable configuration. Keep the final
				# action hidden when a content snapshot has no real task/zone instead
				# of presenting a Start button that can only reject the click.
				_difficulty_stage_open = _configuration_is_valid()
				_sync_selection()
				if _difficulty_stage_open and not _difficulties.buttons.is_empty():
					_difficulties.buttons[0].call_deferred(&"grab_focus")
			return


func _configuration_is_valid() -> bool:
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return false
	var character := _selected_character(app)
	var weapon := app.content_snapshot.definition(app.selection_draft.get("weapon_id", &""), &"weapon") as GogoWeaponDefinition
	var zone := app.content_snapshot.definition(app.selection_draft.get("zone_id", &""), &"zone") as GogoZoneDefinition
	return character != null and weapon != null and zone != null and character.allows_weapon(weapon)


func _sync_selection() -> void:
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	var niko_detail := get_node("NikoDetail") as Control
	var weapon_stage := get_node("WeaponStage") as Control
	var difficulty_stage := get_node("DifficultyStage") as Control
	var change := get_node("ChangeCharacterButton") as Button
	var selected_zone_id := app.selection_draft.get("zone_id", &"") as StringName
	_zones.apply_selection(selected_zone_id)
	_zones.set_enabled(not _starting)
	niko_detail.visible = true
	var cell := get_node("RosterStrip/NikoCell") as Button
	var character := _selected_character(app)
	if character == null:
		_character_picker_open = true
		_difficulty_stage_open = false
	var selected := character != null
	cell.set_meta(&"selected", selected)
	cell.set_meta(&"committed", selected)
	if selected:
		_apply_selected_fill(cell)
	else:
		HUD_SKIN.apply_card(cell, false)
	_sync_character_label()
	var weapon := app.content_snapshot.definition(app.selection_draft.get("weapon_id", &""), &"weapon") as GogoWeaponDefinition
	if character == null or weapon == null or not character.allows_weapon(weapon):
		app.selection_draft["weapon_id"] = &""
		weapon = null
		_difficulty_stage_open = false
	_set_character_picker_visible(_character_picker_open)
	change.visible = character != null and not _character_picker_open
	change.disabled = not change.visible
	change.focus_mode = Control.FOCUS_ALL if change.visible else Control.FOCUS_NONE
	var weapon_stage_ready := character != null and not _character_picker_open
	weapon_stage.visible = weapon_stage_ready
	difficulty_stage.visible = (
		weapon_stage_ready
		and weapon != null
		and _difficulty_stage_open
		and _configuration_is_valid()
	)
	for button in _weapons.buttons:
		var option := button.get_meta(&"definition") as GogoWeaponDefinition
		button.visible = weapon_stage_ready and option != null and character.allows_weapon(option)
		button.disabled = not button.visible
		button.focus_mode = Control.FOCUS_ALL if button.visible else Control.FOCUS_NONE
	_difficulties.set_enabled(difficulty_stage.visible)
	_weapons.apply_selection(app.selection_draft.get("weapon_id", &""))
	_rebuild_focus()


func _set_character_picker_visible(visible_value: bool) -> void:
	var caption := get_node("RosterCaption") as Control
	var roster := get_node("RosterStrip") as GridContainer
	caption.visible = visible_value
	roster.visible = visible_value
	for child in roster.get_children():
		if child is Control:
			(child as Control).visible = visible_value
	var niko := roster.get_node("NikoCell") as Button
	niko.disabled = not visible_value
	niko.focus_mode = Control.FOCUS_ALL if visible_value else Control.FOCUS_NONE


func _sync_character_label() -> void:
	var cell := get_node("RosterStrip/NikoCell") as Button
	var highlighted := bool(cell.get_meta(&"selected", false)) or cell.has_focus() or cell.is_hovered()
	for node_name in [&"Name", &"SlotIndex", &"Availability", &"RoleTag"]:
		var label := cell.get_node(NodePath(node_name)) as Label
		label.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT_FOCUS if highlighted else HUD_SKIN.COLOR_TEXT)
		label.add_theme_constant_override(&"outline_size", 0 if highlighted else 1)


func _rebuild_focus() -> void:
	var roster := get_node("RosterStrip") as GridContainer
	var niko := get_node("RosterStrip/NikoCell") as Button
	var change := get_node("ChangeCharacterButton") as Button
	var task := get_node("TaskOptionButton") as OptionButton
	var reset: Array[Control] = [change, task]
	for child in roster.get_children():
		if child is Control:
			reset.append(child as Control)
	reset.append_array(_weapons.buttons)
	reset.append_array(_difficulties.buttons)
	for control in reset:
		control.focus_neighbor_left = NodePath()
		control.focus_neighbor_right = NodePath()
		control.focus_neighbor_top = NodePath()
		control.focus_neighbor_bottom = NodePath()
		control.focus_next = NodePath()
		control.focus_previous = NodePath()
	var controls: Array[Control] = [get_node("BackButton") as Control]
	if task.visible and not task.disabled:
		controls.append(task)
	if _character_picker_open:
		controls.append(niko)
	else:
		if change.visible and not change.disabled:
			controls.append(change)
	var selected_weapon: Button
	for button in _weapons.buttons:
		if not button.visible:
			continue
		controls.append(button)
		if bool(button.get_meta(&"selected", false)):
			selected_weapon = button
	if not _difficulties.buttons.is_empty():
		var difficulty := _difficulties.buttons[0]
		if difficulty.visible and not difficulty.disabled:
			controls.append(difficulty)
	link_focus_cycle(controls)
	var columns: Array[Array] = []
	for group in _weapons.column_buttons:
		var visible_group: Array = []
		for candidate in group:
			if (candidate as Button).visible:
				visible_group.append(candidate)
		if not visible_group.is_empty():
			columns.append(visible_group)
	for column_index in columns.size():
		var group: Array = columns[column_index]
		for row in group.size():
			var button := group[row] as Button
			for direction in [-1, 1]:
				var neighbor: Array = columns[posmod(column_index + direction, columns.size())]
				var target := neighbor[mini(row, neighbor.size() - 1)] as Button
				button.set("focus_neighbor_left" if direction < 0 else "focus_neighbor_right", button.get_path_to(target))
	if not _character_picker_open and not _weapons.buttons.is_empty() and _weapons.buttons[0].visible:
		change.focus_neighbor_right = change.get_path_to(_weapons.buttons[0])
	if selected_weapon != null and not _difficulties.buttons.is_empty():
		var difficulty := _difficulties.buttons[0]
		if difficulty.visible and not difficulty.disabled:
			selected_weapon.focus_neighbor_bottom = selected_weapon.get_path_to(difficulty)


func _focus_initial_control() -> void:
	if _character_picker_open:
		(get_node("RosterStrip/NikoCell") as Button).call_deferred(&"grab_focus")
	else:
		_focus_weapon_or_change()


func _focus_weapon_or_change() -> void:
	var first_visible: Button
	for button in _weapons.buttons:
		if not button.visible or button.disabled:
			continue
		if first_visible == null:
			first_visible = button
		if bool(button.get_meta(&"selected", false)):
			button.call_deferred(&"grab_focus")
			return
	if first_visible != null:
		first_visible.call_deferred(&"grab_focus")
		return
	var change := get_node("ChangeCharacterButton") as Button
	if change.visible and not change.disabled:
		change.call_deferred(&"grab_focus")


func _select_difficulty_and_start(content_id: StringName) -> void:
	if (
		_starting
		or _character_picker_open
		or not (get_node("DifficultyStage") as Control).visible
		or not _configuration_is_valid()
	):
		return
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	if app.content_snapshot.definition(content_id, &"difficulty") == null:
		return
	_starting = true
	app.selection_draft["difficulty_id"] = content_id
	var error := app.create_session_from_draft()
	if error != OK:
		_starting = false
		app.route(FlowRoute.DIAGNOSTIC, {"message": "无法创建游戏会话", "details": [error_string(error)]})
		return
	app.route(FlowRoute.COMBAT)


func _first_frame(niko: CharacterDefinition) -> Texture2D:
	if (
		niko == null
		or niko.sprite_frames == null
		or niko.default_animation.is_empty()
		or not niko.sprite_frames.has_animation(niko.default_animation)
		or niko.sprite_frames.get_frame_count(niko.default_animation) <= 0
	):
		return null
	return niko.sprite_frames.get_frame_texture(niko.default_animation, 0)


func _cropped_detail_frame(niko: CharacterDefinition) -> Texture2D:
	var frame := _first_frame(niko)
	if frame == null:
		return null
	var image := frame.get_image()
	if image == null:
		return frame
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return frame
	var padded_position := Vector2i(
		maxi(used.position.x - 4, 0),
		maxi(used.position.y - 4, 0)
	)
	var padded_end := Vector2i(
		mini(used.end.x + 4, image.get_width()),
		mini(used.end.y + 4, image.get_height())
	)
	var cropped := AtlasTexture.new()
	cropped.atlas = frame
	cropped.region = Rect2(padded_position, padded_end - padded_position)
	return cropped


func _niko_summary(niko: CharacterDefinition) -> String:
	var stats := niko.base_stats
	return (
		"初始生命  %s\n移动速度  %s\n伤害倍率  %s%%\n护甲  %s\n闪避  %s%%\n初始道具  %s"
		% [
			_num(float(stats.get(&"max_health", 0.0))),
			_num(float(stats.get(&"movement_speed", 0.0))),
			_num(float(stats.get(&"damage_multiplier", 1.0)) * 100.0),
			_num(float(stats.get(&"armor", 0.0))),
			_num(float(stats.get(&"dodge", 0.0)) * 100.0),
			"无" if niko.starting_item_ids.is_empty() else str(niko.starting_item_ids.size()),
		]
	)


func _detail_label(
	parent: Node,
	node_name: String,
	position_value: Vector2,
	size_value: Vector2,
	font_size: int
) -> Label:
	return ui_label(parent, node_name, position_value, size_value, font_size)


func _apply_selected_fill(button: Button) -> void:
	var normal := _selection_style(Color("eee8d9"), GogoHudSkin.COLOR_FOCUS, 3)
	var hover := _selection_style(Color("fffaf0"), GogoHudSkin.COLOR_FOCUS, 3)
	var pressed := _selection_style(Color("ddd7ca"), GogoHudSkin.COLOR_FOCUS, 3)
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"focus", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	button.add_theme_stylebox_override(&"disabled", normal)
	for color_name: StringName in [
		&"font_color",
		&"font_hover_color",
		&"font_focus_color",
		&"font_pressed_color",
	]:
		button.add_theme_color_override(color_name, GogoHudSkin.COLOR_TEXT_FOCUS)


func _apply_placeholder_fill(button: Button, index: int) -> void:
	var background := Color("1b252c") if index % 2 == 0 else Color("202c34")
	var style := _selection_style(background, Color("71818c"), 2)
	button.add_theme_stylebox_override(&"normal", style)
	button.add_theme_stylebox_override(&"hover", style)
	button.add_theme_stylebox_override(&"focus", style)
	button.add_theme_stylebox_override(&"pressed", style)
	button.add_theme_stylebox_override(&"disabled", style)


func _apply_selected_label_style(label: Label) -> void:
	label.add_theme_color_override(&"font_color", GogoHudSkin.COLOR_TEXT_FOCUS)
	label.add_theme_color_override(&"font_outline_color", Color.TRANSPARENT)
	label.add_theme_constant_override(&"outline_size", 0)


func _selection_style(background: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.anti_aliasing = false
	style.border_blend = false
	return style


func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2).trim_suffix("0")
