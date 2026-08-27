extends GogoScreenBase


func _ready() -> void:
	build_screen("选择难度", "验证内容：5 波 · 单人")
	add_static_texture(&"zone_thumbnail", "ZoneThumbnail", Vector2(320, 180))
	var app := AppContext.kernel(self)
	for raw in app.content_snapshot.all(&"difficulty"):
		var definition := raw as GogoDifficultyDefinition
		var icon := resolve_content_icon(definition)
		if icon == null:
			icon = resolve_global_icon(
				&"difficulty_badge_kit",
				selector_from_content_id(definition.content_id)
			)
		add_action(
			definition.display_name,
			func() -> void: _select_and_start(definition.content_id),
			false,
			icon
		)
	add_action("返回", func() -> void: app.route(FlowRoute.WEAPON_SELECT))


func _select_and_start(content_id: StringName) -> void:
	var app := AppContext.kernel(self)
	app.selection_draft["difficulty_id"] = content_id
	var error := app.create_session_from_draft()
	if error != OK:
		app.route(FlowRoute.DIAGNOSTIC, {"message": "无法创建游戏会话", "details": [error_string(error)]})
		return
	app.route(FlowRoute.COMBAT)
