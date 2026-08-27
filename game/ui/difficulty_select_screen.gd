extends GogoScreenBase


func _ready() -> void:
	build_screen_chrome("难度选择", "选择后立即开始第 1 波")
	_center_title()
	var app := AppContext.kernel(self)
	if app == null or app.content_snapshot == null:
		return
	_build_back_button(app)
	_build_niko_summary(_selected_niko(app))
	_build_weapon_summary(_selected_weapon(app))
	_build_difficulty_detail()
	_build_difficulty_strip(app)


func _build_back_button(app: AppKernel) -> void:
	var button := Button.new()
	button.name = "BackButton"
	button.position = Vector2(32, 28)
	button.size = Vector2(154, 48)
	button.z_index = 10
	configure_action_button(
		button,
		"← 返回",
		func() -> void: app.route(FlowRoute.WEAPON_SELECT)
	)
	_apply_back_style(button)
	add_child(button)


func _build_niko_summary(niko: CharacterDefinition) -> void:
	var summary := Control.new()
	summary.name = "NikoSummary"
	summary.position = Vector2(32, 110)
	summary.size = Vector2(390, 404)
	add_child(summary)
	_add_backing(summary)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.position = Vector2(20, 24)
	preview.size = Vector2(176, 242)
	preview.texture = _first_niko_frame(niko)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(preview)
	var name_label := _label(summary, "Name", Vector2(218, 34), Vector2(148, 48), 30)
	name_label.text = niko.display_name if niko != null else "Niko"
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var stats := _label(summary, "Traits", Vector2(220, 96), Vector2(146, 208), 17)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = _niko_text(niko)
	var caption := _label(summary, "Caption", Vector2(20, 350), Vector2(346, 30), 17)
	caption.text = "当前角色"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override(&"font_color", Color("f2a14a"))


func _build_weapon_summary(weapon: GogoWeaponDefinition) -> void:
	var summary := Control.new()
	summary.name = "WeaponSummary"
	summary.position = Vector2(438, 110)
	summary.size = Vector2(390, 404)
	add_child(summary)
	_add_backing(summary)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(28, 26)
	icon.size = Vector2(334, 154)
	icon.texture = resolve_content_icon(weapon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(icon)
	_add_icon_fallback(summary, "IconFallback", icon.position, icon.size, weapon.display_name if weapon != null else "无武器")
	(summary.get_node("IconFallback") as Control).visible = icon.texture == null

	var name_label := _label(summary, "Name", Vector2(24, 198), Vector2(342, 42), 28)
	name_label.text = weapon.display_name if weapon != null else "未选择武器"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var detail := _label(summary, "Stats", Vector2(24, 250), Vector2(342, 92), 18)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.text = _weapon_text(weapon)
	var caption := _label(summary, "Caption", Vector2(24, 350), Vector2(342, 30), 17)
	caption.text = "当前起始武器"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override(&"font_color", Color("f2a14a"))


func _build_difficulty_detail() -> void:
	var detail := Control.new()
	detail.name = "SelectedDifficultyDetail"
	detail.position = Vector2(844, 110)
	detail.size = Vector2(404, 404)
	add_child(detail)
	_add_backing(detail)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(126, 30)
	icon.size = Vector2(152, 152)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(icon)
	_add_icon_fallback(detail, "IconFallback", icon.position, icon.size, "标准")

	var name_label := _label(detail, "Name", Vector2(28, 198), Vector2(348, 46), 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override(&"font_color", Color("fff0bf"))
	var kind := _label(detail, "Kind", Vector2(28, 244), Vector2(348, 28), 17)
	kind.text = "难度"
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_color_override(&"font_color", Color("f2a14a"))
	var multipliers := _label(detail, "Multipliers", Vector2(54, 286), Vector2(296, 92), 18)
	multipliers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multipliers.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _build_difficulty_strip(app: AppKernel) -> void:
	var caption := _label(self, "DifficultyStripCaption", Vector2(32, 550), Vector2(1216, 26), 17)
	caption.text = "可用难度  ·  %d" % app.content_snapshot.all(&"difficulty").size()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var strip := HBoxContainer.new()
	strip.name = "DifficultyStrip"
	strip.position = Vector2(604, 592)
	strip.size = Vector2(72, 78)
	strip.add_theme_constant_override(&"separation", 6)
	add_child(strip)

	var definitions := app.content_snapshot.all(&"difficulty")
	var selected_id := app.selection_draft.get("difficulty_id", &"") as StringName
	var first_button: Button
	for option_index in definitions.size():
		var definition := definitions[option_index] as GogoDifficultyDefinition
		var selected := definition.content_id == selected_id
		var button := _difficulty_option(definition, option_index, selected)
		strip.add_child(button)
		if first_button == null or selected:
			first_button = button
		if selected or definitions.size() == 1:
			_show_difficulty(definition)
	if first_button != null:
		first_button.call_deferred(&"grab_focus")


func _difficulty_option(
	definition: GogoDifficultyDefinition,
	option_index: int,
	selected: bool
) -> Button:
	var button := Button.new()
	button.name = "DifficultyOption%d" % option_index
	button.custom_minimum_size = Vector2(72, 78)
	button.size = Vector2(72, 78)
	button.tooltip_text = definition.display_name
	button.set_meta(&"content_id", definition.content_id)
	button.set_meta(&"selected", selected)
	configure_action_button(
		button,
		"",
		Callable(self, "_select_and_start").bind(definition.content_id)
	)
	button.custom_minimum_size = Vector2(72, 78)
	if selected:
		_apply_selected_fill(button)
	button.focus_entered.connect(Callable(self, "_show_difficulty").bind(definition))
	button.mouse_entered.connect(Callable(self, "_show_difficulty").bind(definition))

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.position = Vector2(4, 4)
	icon.size = Vector2(64, 52)
	icon.texture = _difficulty_icon(definition)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_add_icon_fallback(button, "IconFallback", icon.position, icon.size, definition.display_name)
	(button.get_node("IconFallback") as Control).visible = icon.texture == null
	var name_label := _label(button, "Name", Vector2(3, 58), Vector2(66, 16), 12)
	name_label.text = definition.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if selected:
		name_label.add_theme_color_override(&"font_color", Color("1a1c20"))
	return button


func _show_difficulty(definition: GogoDifficultyDefinition) -> void:
	if definition == null or not has_node("SelectedDifficultyDetail"):
		return
	var detail := get_node("SelectedDifficultyDetail") as Control
	var icon := detail.get_node("Icon") as TextureRect
	icon.texture = _difficulty_icon(definition)
	(detail.get_node("IconFallback") as Control).visible = icon.texture == null
	(detail.get_node("IconFallback/Label") as Label).text = definition.display_name
	(detail.get_node("Name") as Label).text = definition.display_name
	(detail.get_node("Multipliers") as Label).text = (
		"生命 %s%%  ·  伤害 %s%%\n速度 %s%%  ·  生成 %s%%"
		% [
			_num(definition.enemy_health_multiplier * 100.0),
			_num(definition.enemy_damage_multiplier * 100.0),
			_num(definition.enemy_speed_multiplier * 100.0),
			_num(definition.spawn_multiplier * 100.0),
		]
	)


func _select_and_start(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["difficulty_id"] = content_id
	var error := app.create_session_from_draft()
	if error != OK:
		app.route(FlowRoute.DIAGNOSTIC, {"message": "无法创建游戏会话", "details": [error_string(error)]})
		return
	app.route(FlowRoute.COMBAT)


func _selected_niko(app: AppKernel) -> CharacterDefinition:
	var selected_id := app.selection_draft.get("character_id", NikoContentFactory.CHARACTER_ID) as StringName
	var definition := app.content_snapshot.definition(selected_id, &"character") as CharacterDefinition
	if definition == null:
		definition = app.content_snapshot.definition(
			NikoContentFactory.CHARACTER_ID,
			&"character"
		) as CharacterDefinition
	return definition


func _selected_weapon(app: AppKernel) -> GogoWeaponDefinition:
	var selected_id := app.selection_draft.get("weapon_id", &"") as StringName
	var definition := app.content_snapshot.definition(selected_id, &"weapon") as GogoWeaponDefinition
	if definition == null:
		var definitions := app.content_snapshot.all(&"weapon")
		if not definitions.is_empty():
			definition = definitions[0] as GogoWeaponDefinition
	return definition


func _difficulty_icon(definition: GogoDifficultyDefinition) -> Texture2D:
	var icon := resolve_content_icon(definition)
	if icon == null and definition != null:
		icon = resolve_global_icon(
			&"difficulty_badge_kit",
			selector_from_content_id(definition.content_id)
		)
	return icon


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
		return "资料不可用"
	var stats := niko.base_stats
	return (
		"生命 %s\n速度 %s\n伤害 %s%%\n护甲 %s\n闪避 %s%%"
		% [
			_num(float(stats.get(&"max_health", 0.0))),
			_num(float(stats.get(&"movement_speed", 0.0))),
			_num(float(stats.get(&"damage_multiplier", 1.0)) * 100.0),
			_num(float(stats.get(&"armor", 0.0))),
			_num(float(stats.get(&"dodge", 0.0)) * 100.0),
		]
	)


func _weapon_text(weapon: GogoWeaponDefinition) -> String:
	if weapon == null:
		return "武器资料不可用"
	return (
		"%s  ·  伤害 %s\n冷却 %s 秒  ·  范围 %s"
		% [
			"近战" if weapon.mode == GogoWeaponDefinition.Mode.MELEE else "远程",
			_num(weapon.damage),
			_num(weapon.cooldown_seconds),
			_num(weapon.attack_range),
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
