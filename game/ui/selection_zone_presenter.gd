extends RefCounted


const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const OPTION_ICON_MAX_WIDTH := 40
const POPUP_ICON_MAX_WIDTH := 64
const POPUP_FONT_SIZE := 20
const POPUP_HORIZONTAL_SEPARATION := 12
const POPUP_VERTICAL_SEPARATION := 8
const POPUP_ITEM_PADDING := 12

const POPUP_PANEL_COLOR := Color("090c0e")
const POPUP_PANEL_BORDER_COLOR := Color("f2a241")
const POPUP_HOVER_COLOR := Color("f1dfb5")
const POPUP_SEPARATOR_COLOR := Color("554731")

var _screen: GogoScreenBase
var _button: OptionButton
var _on_selected: Callable
var _global_icon_handles: Dictionary = {}


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
	_apply_popup_skin(rect)
	for definition: GogoZoneDefinition in app.content_snapshot.all(&"zone"):
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
	_button.item_selected.connect(_activate)
	set_enabled(true)
	return _button


func set_enabled(enabled: bool) -> void:
	if _button == null:
		return
	var available := enabled and _button.item_count > 0
	_button.disabled = not available
	_button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if available else Control.CURSOR_FORBIDDEN
	)


func apply_selection(content_id: StringName) -> bool:
	if _button == null:
		return false
	if _button.item_count == 0:
		_button.text = "任务 · 无可用任务"
		_button.tooltip_text = "内容快照中没有可用区域"
		return false
	for index in _button.item_count:
		if StringName(_button.get_item_metadata(index)) == content_id:
			_button.select(index)
			_sync_popup_selection(index)
			_sync_selected_tooltip(index)
			_observe_selected_icon(index)
			return true
	_button.select(-1)
	_sync_popup_selection(-1)
	_button.text = "任务 · 未选择"
	_button.tooltip_text = "请选择任务区域"
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
	_on_selected.call(content_id)


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
	GogoStaticConsumerRegistry.observe_visible_option_icon(
		handle,
		_button,
		String(screen_script.resource_path),
		String(_screen.get_path_to(_button))
	)


func _item_text(definition: GogoZoneDefinition) -> String:
	return "任务 · %s" % definition.display_name


func _item_tooltip(definition: GogoZoneDefinition) -> String:
	return "%s · %d 波 · 从第 1 波开始" % [
		definition.display_name,
		definition.wave_ids.size(),
	]
