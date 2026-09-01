extends RefCounted


const HUD_SKIN := preload("res://game/ui/hud_skin.gd")

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
	_button.add_theme_constant_override(&"icon_max_width", 40)
	_button.get_popup().add_theme_constant_override(&"icon_max_width", 64)
	parent.add_child(_button)
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
		if global_handle != null:
			_global_icon_handles[index] = global_handle
	if _button.item_count == 0:
		_button.text = "任务 · 无可用任务"
		_button.tooltip_text = "内容快照中没有可用区域"
	else:
		_button.select(-1)
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
			_sync_selected_tooltip(index)
			_observe_selected_icon(index)
			return true
	_button.select(-1)
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
	_on_selected.call(content_id)


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
