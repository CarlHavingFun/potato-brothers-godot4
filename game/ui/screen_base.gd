class_name GogoScreenBase
extends Control

static var _stable_ui_theme: Theme

var body: VBoxContainer


func build_screen(title: String, subtitle: String = "") -> VBoxContainer:
	theme = _shared_stable_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("151922")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 360.0)
	center.add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	panel.add_child(body)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	body.add_child(heading)
	if not subtitle.is_empty():
		var description := Label.new()
		description.text = subtitle
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(description)
	return body


func add_action(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.disabled = disabled
	button.pressed.connect(callback)
	body.add_child(button)
	return button


func add_info(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label


static func _shared_stable_ui_theme() -> Theme:
	if _stable_ui_theme != null:
		return _stable_ui_theme
	var result := Theme.new()
	var normal := _button_style(Color(0.025, 0.025, 0.025, 0.96), Color(0.18, 0.18, 0.18, 0.96))
	var hover := _button_style(Color(0.085, 0.085, 0.085, 0.98), Color(0.46, 0.46, 0.46, 1.0))
	var pressed := _button_style(Color(0.12, 0.08, 0.035, 0.98), Color(1.0, 0.63, 0.22, 1.0))
	result.set_color(&"font_color", &"Button", Color(0.93, 0.90, 0.77, 1.0))
	result.set_color(&"font_disabled_color", &"Button", Color(0.42, 0.43, 0.38, 0.75))
	result.set_color(&"font_hover_color", &"Button", Color(1.0, 0.88, 0.48, 1.0))
	result.set_color(&"font_focus_color", &"Button", Color(1.0, 0.88, 0.48, 1.0))
	result.set_font_size(&"font_size", &"Button", 24)
	result.set_stylebox(&"normal", &"Button", normal)
	result.set_stylebox(&"hover", &"Button", hover)
	result.set_stylebox(&"focus", &"Button", hover)
	result.set_stylebox(&"pressed", &"Button", pressed)
	result.set_stylebox(&"disabled", &"Button", normal)
	_stable_ui_theme = result
	return _stable_ui_theme


static func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.25
	style.border_blend = true
	style.corner_detail = 12
	style.content_margin_left = 24.0
	style.content_margin_top = 12.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 12.0
	return style
