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

@onready var _flow: SceneFlow = $SceneFlow
@onready var _audio: GogoAudioService = $AudioService
@onready var _host: Node = $SceneHost


func _ready() -> void:
	add_to_group(&"gogobro_app")
	_flow.configure(_host, ROUTES)
	configure(_flow, _audio)
	var result := boot()
	if result.is_ok():
		route(FlowRoute.MAIN_MENU)
	else:
		route(FlowRoute.DIAGNOSTIC, {"message": result.message, "details": result.details})
