extends GogoScreenBase

var _payload: Dictionary = {}


func receive_route_payload(payload: Dictionary) -> void:
	_payload = payload


func _ready() -> void:
	name = "Diagnostic"
	build_screen_chrome("启动诊断", String(_payload.get("message", "未知错误")))
	var surface := add_principal_surface(
		Rect2(272, 184, 736, 352),
		"res://game/ui/diagnostic_screen.gd",
		"Diagnostic/PrincipalSurface"
	)
	body = VBoxContainer.new()
	body.name = "DiagnosticContent"
	body.position = Vector2(16, 16)
	body.size = Vector2(704, 320)
	body.add_theme_constant_override(&"separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.clip_contents = true
	surface.add_child(body)

	var details_scroll := ScrollContainer.new()
	details_scroll.name = "DetailsScroll"
	details_scroll.custom_minimum_size = Vector2(704, 0)
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(details_scroll)

	var details_list := VBoxContainer.new()
	details_list.name = "DetailsList"
	details_list.custom_minimum_size.x = 680
	details_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_list.add_theme_constant_override(&"separation", 8)
	details_scroll.add_child(details_list)
	var details := _payload.get("details", []) as Array
	if details.is_empty():
		_add_detail(details_list, "无更多诊断详情")
	else:
		for detail in details:
			_add_detail(details_list, String(detail))

	var return_button := Button.new()
	return_button.name = "ReturnButton"
	configure_action_button(return_button, "返回主菜单", _return_to_menu)
	body.add_child(return_button)


func _add_detail(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(672, 24)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _return_to_menu() -> void:
	var app := AppContext.kernel(self)
	if app.boot_result != null and app.boot_result.is_ok():
		app.route(FlowRoute.MAIN_MENU)
