extends GogoScreenBase


const NIKO_ID := NikoContentFactory.CHARACTER_ID


func _ready() -> void:
	build_screen_chrome("角色选择", "选择后立即进入起始武器")
	_center_title()
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
	_build_back_button(app)
	_build_niko_detail(niko)
	_build_roster(app, niko)


func _build_back_button(app: AppKernel) -> void:
	var button := Button.new()
	button.name = "BackButton"
	button.position = Vector2(40, 28)
	button.size = Vector2(154, 48)
	button.z_index = 10
	configure_action_button(
		button,
		"← 返回",
		func() -> void: app.route(FlowRoute.MAIN_MENU)
	)
	_apply_back_style(button)
	add_child(button)


func _build_niko_detail(niko: CharacterDefinition) -> void:
	var detail := Control.new()
	detail.name = "NikoDetail"
	detail.position = Vector2(270, 116)
	detail.size = Vector2(740, 416)
	add_child(detail)

	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.color = Color(0.035, 0.04, 0.05, 0.88)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail.add_child(backing)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.position = Vector2(28, 28)
	preview.size = Vector2(310, 344)
	preview.texture = _first_frame(niko)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(preview)

	var name_label := _detail_label(detail, "Name", Vector2(374, 42), Vector2(320, 54), 38)
	name_label.text = niko.display_name
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))

	var role := _detail_label(detail, "Role", Vector2(376, 98), Vector2(318, 30), 20)
	role.text = "唯一可用角色 · 均衡型"
	role.add_theme_color_override(&"font_color", Color("f2a14a"))

	var traits := _detail_label(detail, "Traits", Vector2(376, 144), Vector2(318, 204), 20)
	traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	traits.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	traits.text = _niko_summary(niko)

	var prompt := _detail_label(detail, "Prompt", Vector2(376, 368), Vector2(318, 30), 16)
	prompt.text = "从下方角色格选择并继续"
	prompt.add_theme_color_override(&"font_color", Color("c9c3b1"))


func _build_roster(app: AppKernel, niko: CharacterDefinition) -> void:
	var roster_caption := _detail_label(self, "RosterCaption", Vector2(32, 570), Vector2(1216, 26), 18)
	roster_caption.text = "角色名单  1 / 1"
	roster_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var roster := HBoxContainer.new()
	roster.name = "RosterStrip"
	roster.position = Vector2(604, 604)
	roster.size = Vector2(72, 72)
	roster.add_theme_constant_override(&"separation", 6)
	add_child(roster)

	var cell := Button.new()
	cell.name = "NikoCell"
	cell.custom_minimum_size = Vector2(72, 72)
	cell.size = Vector2(72, 72)
	cell.tooltip_text = niko.display_name
	cell.set_meta(&"content_id", niko.content_id)
	var committed: bool = (
		app.selection_draft.get("character_id", &"") as StringName
	) == niko.content_id
	cell.set_meta(&"selected", true)
	cell.set_meta(&"committed", committed)
	configure_action_button(
		cell,
		"",
		func() -> void: _select(niko.content_id)
	)
	cell.custom_minimum_size = Vector2(72, 72)
	_apply_selected_fill(cell)
	roster.add_child(cell)

	var portrait := TextureRect.new()
	portrait.name = "Preview"
	portrait.position = Vector2(4, 4)
	portrait.size = Vector2(64, 64)
	portrait.texture = _first_frame(niko)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(portrait)
	if portrait.texture == null:
		var fallback := _detail_label(cell, "Fallback", Vector2(4, 4), Vector2(64, 64), 16)
		fallback.text = niko.display_name
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.call_deferred(&"grab_focus")


func _select(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["character_id"] = content_id
	app.route(FlowRoute.WEAPON_SELECT)


func _center_title() -> void:
	var heading := get_node("TitleBand/Title") as Label
	heading.size.x = TITLE_BAND_RECT.size.x
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := get_node("TitleBand/Subtitle") as Label
	subtitle.size.x = TITLE_BAND_RECT.size.x
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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


func _niko_summary(niko: CharacterDefinition) -> String:
	var stats := niko.base_stats
	var tags: Array[String] = []
	for tag: StringName in niko.tags:
		tags.append(String(tag))
	return (
		"标签  %s\n初始生命  %s\n移动速度  %s\n伤害倍率  %s%%\n护甲  %s\n闪避  %s%%\n初始道具  %s"
		% [
			" · ".join(tags),
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
	var label := Label.new()
	label.name = node_name
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color("f3edd7"))
	label.add_theme_color_override(&"font_outline_color", Color("111416"))
	label.add_theme_constant_override(&"outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _apply_selected_fill(button: Button) -> void:
	var normal := _selection_style(Color("ddd7c8"), Color("25282c"))
	var hover := _selection_style(Color("f0ead8"), Color("f2a14a"))
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"focus", hover)
	button.add_theme_stylebox_override(&"pressed", hover)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color"]:
		button.add_theme_color_override(color_name, Color("1a1c20"))


func _apply_back_style(button: Button) -> void:
	button.text = ""
	for state: StringName in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var visual := Panel.new()
	visual.name = "BackButtonVisual"
	visual.position = button.position
	visual.size = button.size
	visual.z_index = 9
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_theme_stylebox_override(
		&"panel",
		_selection_style(Color(0.03, 0.035, 0.04, 0.96), Color("81724f"))
	)
	add_child(visual)
	var label := _detail_label(visual, "Label", Vector2.ZERO, button.size, 24)
	label.text = "← 返回"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _selection_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


func _num(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2).trim_suffix("0")
