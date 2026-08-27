extends GogoScreenBase


func _ready() -> void:
	build_screen("选择起始武器", "近战与远程使用同一运行时管线")
	var app := AppContext.kernel(self)
	var grid := GridContainer.new()
	grid.name = "WeaponCardGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for raw in app.content_snapshot.all(&"weapon"):
		var definition := raw as GogoWeaponDefinition
		var suffix := "近战" if definition.mode == GogoWeaponDefinition.Mode.MELEE else "远程"
		add_static_card(
			definition,
			suffix,
			func() -> void: _select(definition.content_id),
			false,
			grid
		)
	add_action("返回", func() -> void: app.route(FlowRoute.CHARACTER_SELECT))


func _select(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["weapon_id"] = content_id
	app.route(FlowRoute.DIFFICULTY_SELECT)
