extends GogoScreenBase

var _app: AppKernel
var _offers: Array[GogoUpgradeDefinition] = []
var _build_service := PlayerBuildService.new()


func _ready() -> void:
	_app = AppContext.kernel(self)
	_show_offers()


func _show_offers() -> void:
	for child in get_children(): child.queue_free()
	build_screen("选择升级", "剩余 %d 次" % _app.current_session.run_state.pending_upgrade_count)
	_offers.clear()
	var pool := _app.content_snapshot.all(&"upgrade")
	var indices := range(pool.size())
	indices.shuffle()
	for index in indices.slice(0, mini(3, indices.size())):
		var definition := pool[index] as GogoUpgradeDefinition
		_offers.append(definition)
		add_action(
			definition.display_name + "  " + _modifier_text(definition.stat_modifiers),
			func() -> void: _choose(definition),
			false,
			resolve_content_icon(definition)
		)


func _choose(definition: GogoUpgradeDefinition) -> void:
	var session := _app.current_session
	_build_service.apply_upgrade(session, session.run_state.player(), definition.content_id)
	session.run_state.pending_upgrade_count = maxi(session.run_state.pending_upgrade_count - 1, 0)
	if session.run_state.pending_upgrade_count > 0:
		_show_offers()
		return
	session.transition(&"shop")
	_app.route(FlowRoute.SHOP)


func _modifier_text(modifiers: Dictionary) -> String:
	var parts: Array[String] = []
	for key in modifiers:
		parts.append("%s %+g" % [String(key), float(modifiers[key])])
	return ", ".join(parts)
