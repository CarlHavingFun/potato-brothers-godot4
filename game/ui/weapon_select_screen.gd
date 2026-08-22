extends GogoScreenBase


func _ready() -> void:
	build_screen("选择起始武器", "近战与远程使用同一运行时管线")
	var app := AppContext.kernel(self)
	for raw in app.content_snapshot.all(&"weapon"):
		var definition := raw as GogoWeaponDefinition
		var suffix := "近战" if definition.mode == GogoWeaponDefinition.Mode.MELEE else "远程"
		add_action("%s · %s" % [definition.display_name, suffix], func() -> void: _select(definition.content_id))
	add_action("返回", func() -> void: app.route(FlowRoute.CHARACTER_SELECT))


func _select(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["weapon_id"] = content_id
	app.route(FlowRoute.DIFFICULTY_SELECT)
