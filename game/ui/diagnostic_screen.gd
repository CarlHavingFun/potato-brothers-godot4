extends GogoScreenBase

var _payload: Dictionary = {}


func receive_route_payload(payload: Dictionary) -> void:
	_payload = payload


func _ready() -> void:
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
	surface.add_child(body)
	for detail in _payload.get("details", []):
		add_info(String(detail))
	add_action("返回主菜单", _return_to_menu)


func _return_to_menu() -> void:
	var app := AppContext.kernel(self)
	if app.boot_result != null and app.boot_result.is_ok():
		app.route(FlowRoute.MAIN_MENU)
