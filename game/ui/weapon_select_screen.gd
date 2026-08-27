extends GogoScreenBase


func _ready() -> void:
	build_screen_chrome("选择起始武器", "选择后立即进入难度")
	_center_title()
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	_build_back_button(app)
	var niko := _selected_niko(app)
	_build_niko_summary(niko)
	_build_weapon_detail()
	_build_weapon_strip(app)


func _build_back_button(app: AppKernel) -> void:
	var button := Button.new()
	button.name = "BackButton"
	button.position = Vector2(40, 28)
	button.size = Vector2(154, 48)
	button.z_index = 10
	configure_action_button(
		button,
		"← 返回",
		func() -> void: app.route(FlowRoute.CHARACTER_SELECT)
	)
	_apply_back_style(button)
	add_child(button)


func _build_niko_summary(niko: CharacterDefinition) -> void:
	var summary := Control.new()
	summary.name = "NikoSummary"
	summary.position = Vector2(32, 110)
	summary.size = Vector2(470, 404)
	add_child(summary)
	_add_backing(summary)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.position = Vector2(24, 24)
	preview.size = Vector2(210, 250)
	preview.texture = _first_niko_frame(niko)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(preview)

	var name_label := _label(summary, "Name", Vector2(258, 36), Vector2(184, 48), 32)
	name_label.text = niko.display_name if niko != null else "Niko"
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var context := _label(summary, "Context", Vector2(260, 94), Vector2(180, 244), 18)
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.text = _niko_text(niko)
	var step := _label(summary, "Step", Vector2(24, 348), Vector2(418, 34), 17)
	step.text = "当前角色  ·  选择一件起始武器"
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	step.add_theme_color_override(&"font_color", Color("f2a14a"))


func _build_weapon_detail() -> void:
	var detail := Control.new()
	detail.name = "SelectedWeaponDetail"
	detail.position = Vector2(518, 110)
	detail.size = Vector2(730, 404)
	add_child(detail)
	_add_backing(detail)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(24, 36)
	icon.size = Vector2(260, 188)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(icon)
	_add_icon_fallback(detail, "IconFallback", icon.position, icon.size, "无图")

	var name_label := _label(detail, "Name", Vector2(310, 30), Vector2(380, 48), 32)
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var mode := _label(detail, "Mode", Vector2(312, 82), Vector2(180, 30), 19)
	mode.add_theme_color_override(&"font_color", Color("f2a14a"))
	_label(detail, "Damage", Vector2(312, 132), Vector2(190, 30), 21)
	_label(detail, "Cooldown", Vector2(506, 132), Vector2(190, 30), 21)
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.position = Vector2(310, 176)
	divider.size = Vector2(386, 1)
	divider.color = Color(0.55, 0.52, 0.45, 0.65)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(divider)
	var modifiers := _label(detail, "Modifiers", Vector2(312, 194), Vector2(384, 174), 19)
	modifiers.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_weapon_strip(app: AppKernel) -> void:
	var caption := _label(self, "WeaponStripCaption", Vector2(32, 550), Vector2(1216, 26), 17)
	caption.text = "武器库  ·  %d 件真实装备" % app.content_snapshot.all(&"weapon").size()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var strip := HBoxContainer.new()
	strip.name = "WeaponStrip"
	strip.position = Vector2(32, 592)
	strip.size = Vector2(1216, 78)
	strip.add_theme_constant_override(&"separation", 6)
	add_child(strip)

	var definitions := app.content_snapshot.all(&"weapon")
	var selected_id := app.selection_draft.get("weapon_id", &"") as StringName
	var selected_definition: GogoWeaponDefinition
	var selected_button: Button
	for option_index in definitions.size():
		var definition := definitions[option_index] as GogoWeaponDefinition
		var preview_selected := (
			selected_id == definition.content_id
			or (selected_id.is_empty() and option_index == 0)
		)
		var button := _weapon_option(definition, option_index, preview_selected)
		strip.add_child(button)
		if preview_selected:
			selected_definition = definition
			selected_button = button
	if selected_definition == null and not definitions.is_empty():
		selected_definition = definitions[0] as GogoWeaponDefinition
		selected_button = strip.get_child(0) as Button
	if selected_definition != null:
		_show_weapon(selected_definition)
	if selected_button != null:
		selected_button.call_deferred(&"grab_focus")


func _weapon_option(
	definition: GogoWeaponDefinition,
	option_index: int,
	selected: bool
) -> Button:
	var button := Button.new()
	button.name = "WeaponOption%d" % option_index
	button.custom_minimum_size = Vector2(95, 78)
	button.size = Vector2(95, 78)
	button.tooltip_text = definition.display_name
	button.set_meta(&"content_id", definition.content_id)
	button.set_meta(&"selected", selected)
	configure_action_button(
		button,
		"",
		Callable(self, "_select").bind(definition.content_id)
	)
	button.custom_minimum_size = Vector2(95, 78)
	if selected:
		_apply_selected_fill(button)
	button.focus_entered.connect(Callable(self, "_show_weapon").bind(definition))
	button.mouse_entered.connect(Callable(self, "_show_weapon").bind(definition))

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(4, 4)
	icon.size = Vector2(87, 50)
	icon.texture = resolve_content_icon(definition)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_add_icon_fallback(button, "IconFallback", icon.position, icon.size, definition.display_name)
	(button.get_node("IconFallback") as Control).visible = icon.texture == null

	var name_label := _label(button, "Name", Vector2(3, 56), Vector2(89, 18), 12)
	name_label.text = definition.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if selected:
		name_label.add_theme_color_override(&"font_color", Color("1a1c20"))
	return button


func _show_weapon(definition: GogoWeaponDefinition) -> void:
	if definition == null or not has_node("SelectedWeaponDetail"):
		return
	var detail := get_node("SelectedWeaponDetail") as Control
	var icon := detail.get_node("Icon") as TextureRect
	icon.texture = resolve_content_icon(definition)
	(detail.get_node("IconFallback") as Control).visible = icon.texture == null
	(detail.get_node("IconFallback/Label") as Label).text = definition.display_name
	(detail.get_node("Name") as Label).text = definition.display_name
	(detail.get_node("Mode") as Label).text = (
		"近战" if definition.mode == GogoWeaponDefinition.Mode.MELEE else "远程"
	)
	(detail.get_node("Damage") as Label).text = "伤害  %s" % _num(definition.damage)
	(detail.get_node("Cooldown") as Label).text = "冷却  %s 秒" % _num(definition.cooldown_seconds)
	(detail.get_node("Modifiers") as Label).text = (
		"攻击范围  %s\n弹体速度  %s\n击退  %s\n伤害类型  %s\n命中反馈  %s"
		% [
			_num(definition.attack_range),
			"—" if definition.mode == GogoWeaponDefinition.Mode.MELEE else _num(definition.projectile_speed),
			_num(definition.knockback),
			_damage_kind_label(definition.damage_kind),
			_impact_kind_label(definition.impact_kind),
		]
	)


func _select(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["weapon_id"] = content_id
	app.route(FlowRoute.DIFFICULTY_SELECT)


func _selected_niko(app: AppKernel) -> CharacterDefinition:
	var selected_id := app.selection_draft.get("character_id", NikoContentFactory.CHARACTER_ID) as StringName
	var definition := app.content_snapshot.definition(selected_id, &"character") as CharacterDefinition
	if definition == null:
		definition = app.content_snapshot.definition(
			NikoContentFactory.CHARACTER_ID,
			&"character"
		) as CharacterDefinition
	return definition


func _first_niko_frame(niko: CharacterDefinition) -> Texture2D:
	if (
		niko == null
		or niko.sprite_frames == null
		or niko.default_animation.is_empty()
		or not niko.sprite_frames.has_animation(niko.default_animation)
		or niko.sprite_frames.get_frame_count(niko.default_animation) <= 0
	):
		return null
	return niko.sprite_frames.get_frame_texture(niko.default_animation, 0)


func _niko_text(niko: CharacterDefinition) -> String:
	if niko == null:
		return "角色资料不可用"
	var stats := niko.base_stats
	return (
		"均衡型\n\n生命  %s\n移动速度  %s\n伤害倍率  %s%%\n护甲  %s\n闪避  %s%%"
		% [
			_num(float(stats.get(&"max_health", 0.0))),
			_num(float(stats.get(&"movement_speed", 0.0))),
			_num(float(stats.get(&"damage_multiplier", 1.0)) * 100.0),
			_num(float(stats.get(&"armor", 0.0))),
			_num(float(stats.get(&"dodge", 0.0)) * 100.0),
		]
	)


func _add_backing(parent: Control) -> void:
	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.color = Color(0.035, 0.04, 0.05, 0.88)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(backing)


func _add_icon_fallback(
	parent: Node,
	node_name: String,
	position_value: Vector2,
	size_value: Vector2,
	text: String
) -> Control:
	var fallback := ColorRect.new()
	fallback.name = node_name
	fallback.position = position_value
	fallback.size = size_value
	fallback.color = Color(0.12, 0.13, 0.15, 0.94)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fallback)
	var label := _label(fallback, "Label", Vector2(4, 4), size_value - Vector2(8, 8), 14)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return fallback


func _label(
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


func _center_title() -> void:
	for node_name in ["Title", "Subtitle"]:
		var label := get_node("TitleBand/%s" % node_name) as Label
		label.size.x = TITLE_BAND_RECT.size.x
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _apply_selected_fill(button: Button) -> void:
	var normal := _selection_style(Color("ddd7c8"), Color("25282c"))
	var hover := _selection_style(Color("f0ead8"), Color("f2a14a"))
	button.add_theme_stylebox_override(&"normal", normal)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"focus", hover)
	button.add_theme_stylebox_override(&"pressed", hover)


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
	var label := _label(visual, "Label", Vector2.ZERO, button.size, 24)
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


func _damage_kind_label(kind: StringName) -> String:
	return "近战" if kind == &"melee" else "弹道"


func _impact_kind_label(kind: StringName) -> String:
	return {
		&"critical": "暴击",
		&"pierce_exit": "穿透",
		&"normal": "普通",
	}.get(kind, "普通") as String
