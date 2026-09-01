extends RefCounted


const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const CARD_SIZE := Vector2(290, 382)

var buttons: Array[Button] = []
var placeholders: Array[Button] = []
var _screen: GogoScreenBase
var _stage: Control
var _on_selected: Callable


func build(
	screen: GogoScreenBase,
	app: AppKernel,
	stage: Control,
	on_selected: Callable
) -> void:
	_screen = screen
	_stage = stage
	_on_selected = on_selected
	_build_detail(app)
	_build_grid(app)


func set_enabled(enabled: bool) -> void:
	for button in buttons:
		button.disabled = not enabled
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		_sync_card(button)
	for placeholder in placeholders:
		placeholder.disabled = true
		placeholder.focus_mode = Control.FOCUS_NONE


func apply_selection(content_id: StringName) -> void:
	for button in buttons:
		var selected: bool = button.get_meta(&"content_id", &"") == content_id
		button.set_meta(&"selected", selected)
		HUD_SKIN.apply_card(button, selected)
		_sync_card(button)


func selected_button(content_id: StringName) -> Button:
	for button in buttons:
		if button.get_meta(&"content_id", &"") == content_id:
			return button
	return buttons[0] if not buttons.is_empty() else null


func _build_detail(app: AppKernel) -> void:
	var panel := _screen.ui_panel(_stage, "SelectedZoneDetail", Rect2(32, 104, 300, 510))
	var heading := _screen.ui_label(panel, "SectionTitle", Vector2(20, 12), Vector2(260, 34), 27)
	heading.text = "任务选择"
	heading.add_theme_color_override(&"font_color", Color("fff0bf"))
	var rule := _screen.ui_label(panel, "Rule", Vector2(20, 47), Vector2(260, 28), 17)
	rule.text = "区域决定波表与战场"
	rule.add_theme_color_override(&"font_color", Color("f2a14a"))
	var preview := TextureRect.new()
	preview.name = "Thumbnail"
	preview.position = Vector2(20, 88)
	preview.size = Vector2(260, 146)
	preview.texture = _screen.resolve_global_icon(&"zone_thumbnail")
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(preview)
	_screen.icon_fallback(panel, "ThumbnailFallback", preview.position, preview.size, "训练场").visible = preview.texture == null
	var zones: Array = app.content_snapshot.all(&"zone")
	var zone := zones[0] as GogoZoneDefinition if not zones.is_empty() else null
	var zone_name := zone.display_name if zone != null else "无可用任务"
	var wave_count := zone.wave_ids.size() if zone != null else 0
	var name_label := _screen.ui_label(panel, "Name", Vector2(20, 250), Vector2(260, 38), 28)
	name_label.text = zone_name
	var summary := _screen.ui_label(panel, "Summary", Vector2(20, 298), Vector2(260, 92), 20)
	summary.text = "%d 波 · 从第 1 波开始\n标准经济与升级链\n区域内顺序推进" % wave_count
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reference := _screen.ui_label(panel, "Reference", Vector2(20, 416), Vector2(260, 70), 16)
	reference.text = "参考 Brotato 区域选择：\n选择区域，不跳过前置波次"
	reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT_MUTED)


func _build_grid(app: AppKernel) -> void:
	var caption := _screen.ui_label(_stage, "ZoneCaption", Vector2(348, 104), Vector2(900, 30), 20)
	var zones: Array = app.content_snapshot.all(&"zone")
	caption.text = "任务档案 · 可用 %d / 3" % zones.size()
	var grid := HBoxContainer.new()
	grid.name = "ZoneGrid"
	grid.position = Vector2(348, 146)
	grid.size = Vector2(900, 406)
	grid.add_theme_constant_override(&"separation", 15)
	_stage.add_child(grid)
	for definition: GogoZoneDefinition in zones:
		var button := _zone_option(definition, buttons.size())
		grid.add_child(button)
		buttons.append(button)
	for index in range(buttons.size(), 3):
		var placeholder := _placeholder(index)
		grid.add_child(placeholder)
		placeholders.append(placeholder)


func _zone_option(definition: GogoZoneDefinition, index: int) -> Button:
	var button := Button.new()
	button.name = "ZoneOption%d" % index
	button.custom_minimum_size = CARD_SIZE
	button.size = CARD_SIZE
	button.tooltip_text = "%s · %d 波 · 从第 1 波开始" % [
		definition.display_name,
		definition.wave_ids.size(),
	]
	button.set_meta(&"content_id", definition.content_id)
	button.set_meta(&"definition", definition)
	button.set_meta(&"selected", false)
	_screen.configure_action_button(button, "", _activate.bind(button, definition.content_id))
	HUD_SKIN.apply_card(button, false)
	var slot := _screen.ui_label(button, "SlotIndex", Vector2(14, 7), Vector2(42, 20), 14)
	slot.text = "%02d" % (index + 1)
	var availability := _screen.ui_label(button, "Availability", Vector2(200, 7), Vector2(74, 20), 13)
	availability.text = "可用"
	availability.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	availability.add_theme_color_override(&"font_color", Color("f2a14a"))
	var preview := TextureRect.new()
	preview.name = "Thumbnail"
	preview.position = Vector2(16, 34)
	preview.size = Vector2(258, 145)
	preview.texture = _screen.resolve_global_icon(&"zone_thumbnail")
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(preview)
	_screen.icon_fallback(button, "ThumbnailFallback", preview.position, preview.size, definition.display_name).visible = preview.texture == null
	var name_label := _screen.ui_label(button, "Name", Vector2(16, 190), Vector2(258, 38), 26)
	name_label.text = definition.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wave_count := _screen.ui_label(button, "WaveCount", Vector2(16, 234), Vector2(104, 28), 19)
	wave_count.text = "%d 波" % definition.wave_ids.size()
	wave_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var start_wave := _screen.ui_label(button, "StartWave", Vector2(124, 234), Vector2(150, 28), 18)
	start_wave.text = "从第 1 波开始"
	start_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.position = Vector2(18, 274)
	divider.size = Vector2(254, 1)
	divider.color = Color(0.80, 0.65, 0.39, 0.52)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(divider)
	var action := _screen.ui_label(button, "Action", Vector2(16, 286), Vector2(258, 34), 21)
	action.text = "选择任务"
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _screen.ui_label(button, "Rule", Vector2(16, 326), Vector2(258, 42), 16)
	note.text = "顺序波次 · 不跳过经济与升级"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.add_theme_color_override(&"font_color", Color("6f5a42"))
	for signal_name in [&"focus_entered", &"focus_exited", &"mouse_entered", &"mouse_exited"]:
		button.connect(signal_name, _sync_card.bind(button))
	_sync_card(button)
	return button


func _placeholder(index: int) -> Button:
	var button := Button.new()
	button.name = "UnavailableZoneSlot%02d" % (index + 1)
	button.custom_minimum_size = CARD_SIZE
	button.size = CARD_SIZE
	button.text = ""
	button.tooltip_text = "任务槽位 %02d · 尚未开放" % (index + 1)
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	HUD_SKIN.apply_card(button, false)
	var slot := _screen.ui_label(button, "SlotIndex", Vector2(14, 8), Vector2(42, 20), 14)
	slot.text = "%02d" % (index + 1)
	slot.add_theme_color_override(&"font_color", Color("89949c"))
	var glyph := _screen.ui_label(button, "Glyph", Vector2(0, 74), Vector2(290, 108), 54)
	glyph.text = "?"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_color_override(&"font_color", Color("66737c"))
	glyph.add_theme_constant_override(&"outline_size", 0)
	var title := _screen.ui_label(button, "Name", Vector2(16, 202), Vector2(258, 42), 25)
	title.text = "待开放任务"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var divider := ColorRect.new()
	divider.name = "Divider"
	divider.position = Vector2(18, 274)
	divider.size = Vector2(254, 1)
	divider.color = Color(0.42, 0.48, 0.52, 0.42)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(divider)
	var status := _screen.ui_label(button, "Status", Vector2(16, 288), Vector2(258, 48), 19)
	status.text = "未开放"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT_MUTED)
	return button


func _activate(button: Button, content_id: StringName) -> void:
	if button == null or button.disabled or not button.is_visible_in_tree():
		return
	_on_selected.call(content_id)


func _sync_card(button: Button) -> void:
	if button == null:
		return
	var highlighted := (
		bool(button.get_meta(&"selected", false))
		or button.has_focus()
		or button.is_hovered()
	)
	var color := HUD_SKIN.COLOR_TEXT_FOCUS if highlighted else HUD_SKIN.COLOR_TEXT
	if button.disabled:
		color = HUD_SKIN.COLOR_TEXT_MUTED
	for node_name in [&"SlotIndex", &"Availability", &"Name", &"WaveCount", &"StartWave", &"Action"]:
		var label := button.get_node_or_null(NodePath(node_name)) as Label
		if label != null:
			label.add_theme_color_override(&"font_color", color)
			label.add_theme_constant_override(&"outline_size", 0 if highlighted else 1)
