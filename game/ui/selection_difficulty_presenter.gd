extends RefCounted

const HUD_SKIN := preload("res://game/ui/hud_skin.gd")

var buttons: Array[Button] = []

func build(screen: GogoScreenBase, app: AppKernel, stage: Control, on_selected: Callable) -> void:
	var strip := HBoxContainer.new()
	strip.name = "DifficultyStrip"
	strip.position = Vector2(348, 648)
	strip.size = Vector2(900, 56)
	stage.add_child(strip)
	for definition: GogoDifficultyDefinition in app.content_snapshot.all(&"difficulty"):
		var button := Button.new()
		button.name = "DifficultyOption%d" % buttons.size()
		button.custom_minimum_size = Vector2(560, 56)
		button.size = Vector2(560, 56)
		button.tooltip_text = definition.display_name
		button.set_meta(&"content_id", definition.content_id)
		screen.configure_action_button(button, "", _activate.bind(button, on_selected, definition.content_id))
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.position = Vector2(6, 6)
		icon.size = Vector2(44, 44)
		var icon_texture := screen.resolve_content_icon(definition)
		if icon_texture == null:
			var badge_selector := GogoScreenBase.selector_from_content_id(definition.content_id)
			icon_texture = screen.resolve_global_icon(&"difficulty_badge_kit", badge_selector)
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var title := screen.ui_label(button, "Title", Vector2(60, 4), Vector2(92, 48), 22)
		title.text = definition.display_name
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var multipliers := screen.ui_label(button, "Multipliers", Vector2(156, 4), Vector2(292, 48), 18)
		multipliers.text = "生命 %s%% · 伤害 %s%%" % [
			_num(definition.enemy_health_multiplier * 100.0),
			_num(definition.enemy_damage_multiplier * 100.0),
		]
		multipliers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		multipliers.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var start_cue := screen.ui_label(button, "StartCue", Vector2(452, 4), Vector2(96, 48), 21)
		start_cue.text = "开始"
		start_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		start_cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		strip.add_child(button)
		buttons.append(button)
		button.focus_entered.connect(_sync_labels.bind(button))
		button.focus_exited.connect(_sync_labels.bind(button))
		button.mouse_entered.connect(_sync_labels.bind(button))
		button.mouse_exited.connect(_sync_labels.bind(button))
		_sync_labels(button)

func set_enabled(enabled: bool) -> void:
	for button in buttons:
		button.disabled = not enabled
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		_sync_labels(button)


func _activate(button: Button, on_selected: Callable, content_id: StringName) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return
	on_selected.call(content_id)


func _sync_labels(button: Button) -> void:
	if button == null:
		return
	var color := HUD_SKIN.COLOR_TEXT
	if button.disabled:
		color = HUD_SKIN.COLOR_TEXT_MUTED
	elif button.has_focus() or button.is_hovered():
		color = HUD_SKIN.COLOR_TEXT_FOCUS
	for node_name in [&"Title", &"Multipliers", &"StartCue"]:
		var label := button.get_node_or_null(NodePath(node_name)) as Label
		if label != null:
			label.add_theme_color_override(&"font_color", color)
			label.add_theme_constant_override(&"outline_size", 0 if color == HUD_SKIN.COLOR_TEXT_FOCUS else 1)

func _num(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 2).trim_suffix("0")
