extends AppKernel

const ROUTES := {
	FlowRoute.MAIN_MENU: preload("res://game/ui/main_menu_screen.tscn"),
	FlowRoute.CHARACTER_SELECT: preload("res://game/ui/character_select_screen.tscn"),
	FlowRoute.WEAPON_SELECT: preload("res://game/ui/weapon_select_screen.tscn"),
	FlowRoute.DIFFICULTY_SELECT: preload("res://game/ui/difficulty_select_screen.tscn"),
	FlowRoute.COMBAT: preload("res://game/ui/combat_screen.tscn"),
	FlowRoute.UPGRADE: preload("res://game/ui/upgrade_screen.tscn"),
	FlowRoute.SHOP: preload("res://game/ui/shop_screen.tscn"),
	FlowRoute.SETTLEMENT: preload("res://game/ui/settlement_screen.tscn"),
	FlowRoute.DIAGNOSTIC: preload("res://game/ui/diagnostic_screen.tscn"),
}
const RELEASE_SMOKE_ARGUMENT := "--gogobro-release-smoke"
const RELEASE_SMOKE_SUCCESS := (
	"GOGOBRO_EXPORTED_MAIN_MENU_READY route=main_menu ready=70 fallback=0 "
	+ "wordmark=1 buttons=1 release=1 preview=0"
)

@onready var _flow: SceneFlow = $SceneFlow
@onready var _audio: GogoAudioService = $AudioService
@onready var _host: Node = $SceneHost


func _ready() -> void:
	add_to_group(&"gogobro_app")
	_flow.configure(_host, ROUTES)
	configure(_flow, _audio)
	var result := boot()
	if result.is_ok():
		var route_error := route(FlowRoute.MAIN_MENU)
		if RELEASE_SMOKE_ARGUMENT in OS.get_cmdline_user_args():
			call_deferred("_finish_release_smoke", route_error)
	else:
		route(FlowRoute.DIAGNOSTIC, {"message": result.message, "details": result.details})
		if RELEASE_SMOKE_ARGUMENT in OS.get_cmdline_user_args():
			call_deferred("_fail_release_smoke", "boot=%s" % result.message)


func _finish_release_smoke(route_error: Error) -> void:
	await get_tree().process_frame
	var snapshot := static_asset_service.active_snapshot()
	var readiness := snapshot.release_readiness() if snapshot != null else {}
	var release_build := not OS.is_debug_build()
	var development_preview := snapshot != null and snapshot.is_development_preview()
	var route_ok := route_error == OK and _flow.current_route() == FlowRoute.MAIN_MENU
	var main_menu := _host.get_child(0) if _host.get_child_count() == 1 else null
	var wordmark := (
		main_menu.get_node_or_null("ContentRoot/Body/Wordmark") as TextureRect
		if main_menu != null
		else null
	)
	var start_button := (
		main_menu.get_node_or_null("ContentRoot/Body/MenuActions/StartButton") as Button
		if main_menu != null
		else null
	)
	var wordmark_ok := wordmark != null and wordmark.texture != null
	var button_ok := false
	if start_button != null:
		var style := start_button.get_theme_stylebox(&"normal")
		button_ok = style is StyleBoxTexture and (style as StyleBoxTexture).texture != null
	var ready_units := int(readiness.get("ready_units", -1))
	var fallback_units := int(readiness.get("fallback_units", -1))
	if (
		release_build
		and not development_preview
		and route_ok
		and main_menu != null
		and main_menu.name == &"MainMenuScreen"
		and bool(readiness.get("release_ready", false))
		and ready_units == 70
		and fallback_units == 0
		and wordmark_ok
		and button_ok
	):
		print(RELEASE_SMOKE_SUCCESS)
		get_tree().quit(0)
		return
	_fail_release_smoke(
		"route=%s ready=%d fallback=%d wordmark=%d buttons=%d release=%d preview=%d" % [
			_flow.current_route(),
			ready_units,
			fallback_units,
			int(wordmark_ok),
			int(button_ok),
			int(release_build),
			int(development_preview),
		]
	)


func _fail_release_smoke(details: String) -> void:
	push_error("GOGOBRO_EXPORTED_MAIN_MENU_FAILED " + details)
	get_tree().quit(1)
