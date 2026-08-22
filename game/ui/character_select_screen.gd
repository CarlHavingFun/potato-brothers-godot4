extends GogoScreenBase


func _ready() -> void:
	build_screen("选择角色", "角色定义来自独立内容包")
	var app := AppContext.kernel(self)
	for raw in app.content_snapshot.all(&"character"):
		var definition := raw as CharacterDefinition
		add_action(definition.display_name, func() -> void: _select(definition.content_id))
	add_action("返回", func() -> void: app.route(FlowRoute.MAIN_MENU))


func _select(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["character_id"] = content_id
	app.route(FlowRoute.WEAPON_SELECT)
