extends GogoScreenBase

var _app: AppKernel
var _shop := ShopRuntimeService.new()
var _status: Label


func _ready() -> void:
	_app = AppContext.kernel(self)
	_shop.open_shop(_app.current_session)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var player := _app.current_session.run_state.player()
	build_screen("商店 · 第 %d 波" % _app.current_session.run_state.current_wave, "材料：%d · 武器：%d/6" % [player.materials, player.weapon_ids.size()])
	_status = add_info("")
	for index in _shop.offers.size():
		var definition := _shop.offers[index]
		var price := _shop.item_pool.price_for(definition, _app.current_session.run_state.current_wave, _app.current_session.run_state.reroll_count)
		var locked := _app.current_session.run_state.locked_shop_offer_ids.has(definition.content_id)
		var row := HBoxContainer.new()
		body.add_child(row)
		var buy := GogoStaticCardPresenter.build_card(
			definition,
			"%d 材料" % price,
			_static_asset_snapshot()
		) as Button
		buy.pressed.connect(
			func() -> void: _buy(index),
		)
		var four_state_texture := _global_texture(&"four_state_button")
		if four_state_texture != null:
			buy.set_meta(&"static_four_state_texture", four_state_texture)
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(buy)
		var lock := Button.new()
		configure_action_button(
			lock,
			"解锁" if locked else "锁定",
			func() -> void: _toggle_lock(index)
		)
		row.add_child(lock)
	add_action("刷新商店", _reroll)
	if not player.weapon_ids.is_empty():
		add_action("出售最后一把武器", _sell_last)
		add_action("合成第一种重复武器", _combine_first_duplicate)
	add_action("进入下一波", _continue_run)


func _buy(index: int) -> void:
	var error := _shop.buy(_app.current_session, index)
	_rebuild()
	_status.text = "购买成功" if error == OK else "购买失败：%s" % error_string(error)


func _toggle_lock(index: int) -> void:
	_shop.toggle_lock(_app.current_session, index)
	_rebuild()


func _reroll() -> void:
	var error := _shop.reroll(_app.current_session)
	_rebuild()
	_status.text = "刷新完成" if error == OK else "材料不足"


func _sell_last() -> void:
	var player := _app.current_session.run_state.player()
	var error := _shop.sell_weapon(_app.current_session, player.weapon_ids.size() - 1)
	_rebuild()
	_status.text = "出售成功" if error == OK else "出售失败"


func _combine_first_duplicate() -> void:
	var player := _app.current_session.run_state.player()
	var counts: Dictionary = {}
	for id in player.weapon_ids: counts[id] = int(counts.get(id, 0)) + 1
	var error := ERR_UNAVAILABLE
	for id in counts:
		if int(counts[id]) >= 2:
			error = _shop.combine_weapon(_app.current_session, id)
			break
	_rebuild()
	_status.text = "合成成功" if error == OK else "没有可合成的重复武器"


func _continue_run() -> void:
	if _app.current_session.continue_after_shop():
		_app.save_checkpoint()
		_app.route(FlowRoute.COMBAT)
	else:
		_app.route(FlowRoute.SETTLEMENT)
