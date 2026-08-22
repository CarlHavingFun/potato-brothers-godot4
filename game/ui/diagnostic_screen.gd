extends GogoScreenBase

var _payload: Dictionary = {}


func receive_route_payload(payload: Dictionary) -> void:
	_payload = payload


func _ready() -> void:
	build_screen("启动诊断", String(_payload.get("message", "未知错误")))
	for detail in _payload.get("details", []):
		add_info(String(detail))
	add_action("返回主菜单", _return_to_menu)


func _return_to_menu() -> void:
	var app := AppContext.kernel(self)
	if app.boot_result != null and app.boot_result.is_ok():
		app.route(FlowRoute.MAIN_MENU)
