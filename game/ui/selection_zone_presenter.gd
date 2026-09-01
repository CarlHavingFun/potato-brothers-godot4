extends RefCounted


const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const OPTION_ICON_MAX_WIDTH := 48
const POPUP_ICON_MAX_WIDTH := 112
const POPUP_FONT_SIZE := 20
const POPUP_HORIZONTAL_SEPARATION := 12
const POPUP_VERTICAL_SEPARATION := 8
const POPUP_ITEM_PADDING := 12
const DETAIL_RECT := Rect2(584, 92, 344, 304)
const SUMMARY_ICON_RECT := Rect2(14, 14, 48, 27)

const POPUP_PANEL_COLOR := Color("090c0e")
const POPUP_PANEL_BORDER_COLOR := Color("f2a241")
const POPUP_HOVER_COLOR := Color("f1dfb5")
const POPUP_SEPARATOR_COLOR := Color("554731")

var _screen: GogoScreenBase
var _button: OptionButton
var _summary: Panel
var _summary_icon: TextureRect
var _summary_label: Label
var _on_selected: Callable
var _global_icon_handles: Dictionary = {}
var _definitions: Dictionary = {}
var _item_icons: Dictionary = {}
var _detail_panel: Panel
var _detail_thumbnail: TextureRect
var _detail_fallback: Control
var _detail_name: Label
var _detail_metadata: Label
var _detail_help: Label
var _focus_poll_timer: Timer


func build(
	screen: GogoScreenBase,
	app: AppKernel,
	parent: Node,
	rect: Rect2,
	on_selected: Callable
) -> OptionButton:
	_screen = screen
	_on_selected = on_selected
	_global_icon_handles.clear()
	_definitions.clear()
	_item_icons.clear()
	_button = OptionButton.new()
	_button.name = "TaskOptionButton"
	_button.position = rect.position
	_button.size = rect.size
	_button.custom_minimum_size = rect.size
	_button.fit_to_longest_item = false
	_button.allow_reselect = true
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HUD_SKIN.apply_action_button(_button, &"compact", false, true)
	_button.add_theme_constant_override(&"icon_max_width", OPTION_ICON_MAX_WIDTH)
	parent.add_child(_button)
	_build_current_summary(parent, rect)
	_apply_popup_skin(rect)
	_build_focus_detail(parent)
	for definition: GogoZoneDefinition in app.content_snapshot.all(&"zone"):
		# A task is a launchable wave graph, not merely a registered zone label.
		# Keep malformed installed/mod content out of the selector so it cannot
		# expose a Start action that GameSession must reject afterwards.
		if GogoWaveResolver.validate_zone(app.content_snapshot, definition) != OK:
			continue
		var icon := _screen.resolve_content_icon(definition)
		var global_handle: GogoStaticAssetHandle
		if icon == null and not definition.icon_asset_id.is_empty():
			global_handle = _screen.resolve_global_handle(definition.icon_asset_id)
			icon = global_handle.texture if global_handle != null else null
		if icon != null:
			_button.add_icon_item(icon, _item_text(definition))
		else:
			_button.add_item(_item_text(definition))
		var index := _button.item_count - 1
		_button.set_item_metadata(index, definition.content_id)
		_button.set_item_tooltip(index, _item_tooltip(definition))
		_definitions[index] = definition
		_item_icons[index] = icon
		_button.get_popup().set_item_as_radio_checkable(index, true)
		_button.get_popup().set_item_checked(index, false)
		if global_handle != null:
			_global_icon_handles[index] = global_handle
	if _button.item_count == 0:
		_button.text = "任务 · 无可用任务"
		_button.tooltip_text = "内容快照中没有可用区域"
	else:
		_button.select(-1)
		_sync_popup_selection(-1)
		_button.text = "任务 · 未选择"
		_button.tooltip_text = "请选择任务区域"
	if _button.item_count >= 2:
		_button.item_selected.connect(_activate)
	var popup := _button.get_popup()
	popup.about_to_popup.connect(_on_popup_about_to_show)
	popup.popup_hide.connect(_on_popup_hidden)
	popup.id_focused.connect(_on_popup_id_focused)
	set_enabled(true)
	return _button


func set_enabled(enabled: bool) -> void:
	if _button == null:
		return
	var selectable := _button.item_count >= 2
	var available := enabled and selectable
	_button.visible = selectable
	_button.disabled = not available
	_button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP if available else Control.MOUSE_FILTER_IGNORE
	_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if available else Control.CURSOR_FORBIDDEN
	)
	if _summary != null:
		_summary.visible = not selectable


func single_content_id() -> StringName:
	if _button == null or _button.item_count != 1:
		return &""
	return StringName(_button.get_item_metadata(0))


func apply_selection(content_id: StringName) -> bool:
	if _button == null:
		return false
	if _button.item_count == 0:
		_button.text = "任务 · 无可用任务"
		_button.tooltip_text = "内容快照中没有可用区域"
		_sync_summary(-1, "当前任务 · 无可用任务")
		return false
	for index in _button.item_count:
		if StringName(_button.get_item_metadata(index)) == content_id:
			_button.select(index)
			_sync_popup_selection(index)
			_sync_selected_tooltip(index)
			_sync_summary(index)
			_observe_selected_icon(index)
			return true
	_button.select(-1)
	_sync_popup_selection(-1)
	_button.text = "任务 · 未选择"
	_button.tooltip_text = "请选择任务区域"
	_sync_summary(-1, "当前任务 · 未选择")
	return false


func _activate(index: int) -> void:
	if (
		_button == null
		or _button.disabled
		or index < 0
		or index >= _button.item_count
	):
		return
	var content_id := StringName(_button.get_item_metadata(index))
	if content_id.is_empty():
		return
	_sync_popup_selection(index)
	_sync_focus_detail(index)
	_on_selected.call(content_id)


func _build_current_summary(parent: Node, rect: Rect2) -> void:
	_summary = _screen.ui_panel(parent, "TaskCurrentSummary", rect)
	_summary.z_index = 10
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.focus_mode = Control.FOCUS_NONE
	_summary_icon = TextureRect.new()
	_summary_icon.name = "Icon"
	_summary_icon.position = SUMMARY_ICON_RECT.position
	_summary_icon.size = SUMMARY_ICON_RECT.size
	_summary_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_summary_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_summary_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_summary_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_child(_summary_icon)
	_summary_label = _screen.ui_label(
		_summary, "Label", Vector2(74, 8), Vector2(rect.size.x - 88, 40), 20
	)
	_summary_label.text = "当前任务 · 未选择"
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_label.clip_text = true


func _sync_summary(index: int, fallback_text := "") -> void:
	if _summary == null or _summary_icon == null or _summary_label == null:
		return
	var definition := _definitions.get(index) as GogoZoneDefinition
	if definition == null:
		_summary_icon.texture = null
		_summary_icon.visible = false
		_summary_label.position.x = 18.0
		_summary_label.size.x = _summary.size.x - 36.0
		_summary_label.text = fallback_text if not fallback_text.is_empty() else "当前任务 · 未选择"
		return
	_summary_icon.texture = _item_icons.get(index) as Texture2D
	_summary_icon.visible = _summary_icon.texture != null
	_summary_label.position.x = 74.0 if _summary_icon.visible else 18.0
	_summary_label.size.x = _summary.size.x - _summary_label.position.x - 14.0
	_summary_label.text = "当前任务 · %s" % definition.display_name


func _build_focus_detail(parent: Node) -> void:
	_detail_panel = Panel.new()
	_detail_panel.name = "TaskFocusDetail"
	_detail_panel.position = DETAIL_RECT.position
	_detail_panel.size = DETAIL_RECT.size
	_detail_panel.z_index = 20
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_theme_stylebox_override(&"panel", _detail_panel_style())
	parent.add_child(_detail_panel)
	var eyebrow := _screen.ui_label(
		_detail_panel, "Eyebrow", Vector2(18, 10), Vector2(308, 24), 16
	)
	eyebrow.text = "任务情报"
	eyebrow.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_FOCUS)
	eyebrow.add_theme_constant_override(&"outline_size", 0)
	_detail_thumbnail = TextureRect.new()
	_detail_thumbnail.name = "Thumbnail"
	_detail_thumbnail.position = Vector2(44, 38)
	_detail_thumbnail.size = Vector2(256, 144)
	_detail_thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_panel.add_child(_detail_thumbnail)
	_detail_fallback = _screen.icon_fallback(
		_detail_panel, "ThumbnailFallback", _detail_thumbnail.position,
		_detail_thumbnail.size, "任务区域"
	)
	_detail_name = _screen.ui_label(
		_detail_panel, "Name", Vector2(18, 190), Vector2(308, 34), 26
	)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_metadata = _screen.ui_label(
		_detail_panel, "Metadata", Vector2(18, 224), Vector2(308, 42), 17
	)
	_detail_metadata.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_metadata.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_help = _screen.ui_label(
		_detail_panel, "Help", Vector2(18, 270), Vector2(308, 24), 13
	)
	_detail_help.text = "浏览任务预览，确认后保留当前配置"
	_detail_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_help.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT_MUTED)
	_detail_help.add_theme_constant_override(&"outline_size", 0)
	_detail_panel.visible = false
	_focus_poll_timer = Timer.new()
	_focus_poll_timer.name = "TaskFocusPoll"
	_focus_poll_timer.wait_time = 0.016
	_focus_poll_timer.one_shot = false
	_focus_poll_timer.autostart = false
	_focus_poll_timer.timeout.connect(_sync_from_popup_focus)
	parent.add_child(_focus_poll_timer)


func _on_popup_about_to_show() -> void:
	if _button == null or _button.item_count <= 0:
		return
	var index := _button.selected
	if index < 0 or index >= _button.item_count:
		index = 0
	_sync_focus_detail(index)
	_detail_panel.visible = true
	if _focus_poll_timer != null:
		_focus_poll_timer.start()


func _on_popup_hidden() -> void:
	if _focus_poll_timer != null:
		_focus_poll_timer.stop()
	if _detail_panel != null:
		_detail_panel.visible = false


func _on_popup_id_focused(item_id: int) -> void:
	if _button == null:
		return
	var index := _button.get_popup().get_item_index(item_id)
	if index >= 0:
		_sync_focus_detail(index)


func _sync_from_popup_focus() -> void:
	if _button == null:
		return
	var index := _button.get_popup().get_focused_item()
	if index >= 0 and index < _button.item_count:
		_sync_focus_detail(index)


func _sync_focus_detail(index: int) -> void:
	if _detail_panel == null:
		return
	var definition := _definitions.get(index) as GogoZoneDefinition
	if definition == null:
		return
	_detail_thumbnail.texture = _item_icons.get(index) as Texture2D
	_detail_fallback.visible = _detail_thumbnail.texture == null
	_detail_name.text = definition.display_name
	_detail_metadata.text = "%d 波   ·   %d × %d   ·   从第 1 波开始" % [
		definition.wave_ids.size(),
		roundi(definition.arena_size.x),
		roundi(definition.arena_size.y),
	]


func _apply_popup_skin(rect: Rect2) -> void:
	var popup := _button.get_popup()
	popup.min_size = Vector2i(maxi(int(ceil(rect.size.x)), 1), 0)
	popup.add_theme_font_override(&"font", _button.get_theme_font(&"font"))
	popup.add_theme_font_override(&"font_separator", _button.get_theme_font(&"font"))
	popup.add_theme_font_size_override(&"font_size", POPUP_FONT_SIZE)
	popup.add_theme_font_size_override(&"font_separator_size", POPUP_FONT_SIZE - 2)
	popup.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT)
	popup.add_theme_color_override(&"font_hover_color", HUD_SKIN.COLOR_TEXT_FOCUS)
	popup.add_theme_color_override(&"font_accelerator_color", HUD_SKIN.COLOR_TEXT_MUTED)
	popup.add_theme_color_override(
		&"font_disabled_color", Color(HUD_SKIN.COLOR_TEXT_MUTED, 0.42)
	)
	popup.add_theme_color_override(&"font_separator_color", HUD_SKIN.COLOR_FOCUS)
	popup.add_theme_color_override(&"font_outline_color", Color("050607"))
	popup.add_theme_constant_override(&"outline_size", 1)
	popup.add_theme_constant_override(&"icon_max_width", POPUP_ICON_MAX_WIDTH)
	popup.add_theme_constant_override(&"h_separation", POPUP_HORIZONTAL_SEPARATION)
	popup.add_theme_constant_override(&"v_separation", POPUP_VERTICAL_SEPARATION)
	popup.add_theme_constant_override(&"item_start_padding", POPUP_ITEM_PADDING)
	popup.add_theme_constant_override(&"item_end_padding", POPUP_ITEM_PADDING)
	var selected_marker := _popup_selection_marker(true)
	var unselected_marker := _popup_selection_marker(false)
	popup.add_theme_icon_override(&"radio_checked", selected_marker)
	popup.add_theme_icon_override(&"radio_unchecked", unselected_marker)
	popup.add_theme_icon_override(&"radio_checked_disabled", selected_marker)
	popup.add_theme_stylebox_override(&"panel", _popup_panel_style())
	popup.add_theme_stylebox_override(&"hover", _popup_hover_style())
	var separator := _popup_separator_style()
	popup.add_theme_stylebox_override(&"separator", separator)
	popup.add_theme_stylebox_override(&"labeled_separator_left", separator)
	popup.add_theme_stylebox_override(&"labeled_separator_right", separator)


func _sync_popup_selection(selected_index: int) -> void:
	if _button == null:
		return
	var popup := _button.get_popup()
	for index in popup.item_count:
		popup.set_item_as_radio_checkable(index, true)
		popup.set_item_checked(index, index == selected_index)


static func _popup_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = POPUP_PANEL_COLOR
	style.border_color = POPUP_PANEL_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin(SIDE_LEFT, 8.0)
	style.set_content_margin(SIDE_TOP, 8.0)
	style.set_content_margin(SIDE_RIGHT, 8.0)
	style.set_content_margin(SIDE_BOTTOM, 8.0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _detail_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.047, 0.055, 0.97)
	style.border_color = POPUP_PANEL_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _popup_hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = POPUP_HOVER_COLOR
	style.border_color = HUD_SKIN.COLOR_FOCUS
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin(SIDE_LEFT, 8.0)
	style.set_content_margin(SIDE_TOP, 5.0)
	style.set_content_margin(SIDE_RIGHT, 8.0)
	style.set_content_margin(SIDE_BOTTOM, 5.0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _popup_separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = POPUP_SEPARATOR_COLOR
	style.border_width_top = 1
	style.set_content_margin(SIDE_TOP, 4.0)
	style.set_content_margin(SIDE_BOTTOM, 4.0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _popup_selection_marker(checked: bool) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2, 14):
		for x in range(2, 14):
			var border := x <= 3 or x >= 12 or y <= 3 or y >= 12
			if border:
				image.set_pixel(x, y, HUD_SKIN.COLOR_FOCUS)
			elif checked and x >= 5 and x <= 10 and y >= 5 and y <= 10:
				image.set_pixel(x, y, HUD_SKIN.COLOR_FOCUS)
	return ImageTexture.create_from_image(image)


func _sync_selected_tooltip(index: int) -> void:
	if _button == null or index < 0 or index >= _button.item_count:
		return
	_button.tooltip_text = _button.get_item_tooltip(index)


func _observe_selected_icon(index: int) -> void:
	var handle := _global_icon_handles.get(index) as GogoStaticAssetHandle
	if _screen == null:
		return
	var screen_script := _screen.get_script() as Script
	if handle == null or screen_script == null:
		return
	if _button.is_visible_in_tree():
		GogoStaticConsumerRegistry.observe_visible_option_icon(
			handle,
			_button,
			String(screen_script.resource_path),
			String(_screen.get_path_to(_button))
		)
	elif _summary_icon != null and _summary_icon.is_visible_in_tree():
		GogoStaticConsumerRegistry.observe_visible_scaled_texture(
			handle,
			_summary_icon,
			String(screen_script.resource_path),
			String(_screen.get_path_to(_summary_icon)),
			SUMMARY_ICON_RECT.size
		)


func _item_text(definition: GogoZoneDefinition) -> String:
	return "任务 · %s" % definition.display_name


func _item_tooltip(definition: GogoZoneDefinition) -> String:
	return "%s · %d 波 · 从第 1 波开始" % [
		definition.display_name,
		definition.wave_ids.size(),
	]
