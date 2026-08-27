extends GogoScreenBase

const SHOP_CARD_PRESENTER := preload("res://game/ui/static_card_presenter.gd")
const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const LOADOUT_STRIP_PRESENTER := preload("res://game/ui/loadout_strip_presenter.gd")
const OFFER_SLOT_COUNT := 4
const OFFER_ROW_RECT := Rect2(32, 100, 927, 372)
const STATS_COLUMN_RECT := Rect2(983, 100, 265, 394)
const LOADOUT_BAR_RECT := Rect2(32, 570, 1216, 118)

var _app: AppKernel
var _shop := ShopRuntimeService.new()
var _status: Label
var _selected_weapon_slot := -1


func _ready() -> void:
	_app = AppContext.kernel(self)
	if _app == null or _app.current_session == null:
		return
	_shop.open_shop(_app.current_session)
	_rebuild(_focus_request(&"buy", &"", 0))


func _rebuild(focus_request: Dictionary = {}, status_text: String = "") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body = null
	var player := _app.current_session.run_state.player()
	_clamp_selected_weapon_slot(player)
	_build_top_band(player)
	_build_offer_row()
	_build_stats_column(player)
	_build_status(status_text)
	_build_continue_button()
	_build_loadout(player)
	if not focus_request.is_empty():
		call_deferred("_restore_focus", focus_request)


func _build_top_band(player: SessionPlayerState) -> void:
	build_screen_chrome("", "")
	var top_band := get_node("TitleBand") as Control
	top_band.name = "TopBand"
	var wave := top_band.get_node("Title") as Label
	wave.name = "Wave"
	wave.position = Vector2.ZERO
	wave.size = Vector2(430, 64)
	wave.text = "第 %d 波 · 商店" % _app.current_session.run_state.current_wave
	wave.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var materials := top_band.get_node("Subtitle") as Label
	materials.name = "Materials"
	materials.position = Vector2(470, 10)
	materials.size = Vector2(450, 44)
	materials.text = "材料 %d   武器 %d/6" % [player.materials, player.weapon_ids.size()]
	materials.add_theme_font_size_override(&"font_size", 22)
	materials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var reroll_cost := _shop.item_pool.reroll_price(
		_app.current_session.run_state.current_wave,
		_app.current_session.run_state.reroll_count
	)
	var reroll := _shop_button(
		"Reroll",
		"刷新 %d" % reroll_cost,
		_reroll,
		Vector2(216, 48)
	)
	reroll.position = Vector2(1000, 8)
	reroll.set_meta(&"focus_role", &"reroll")
	top_band.add_child(reroll)


func _build_offer_row() -> void:
	var offer_row := HBoxContainer.new()
	offer_row.name = "OfferRow"
	offer_row.position = OFFER_ROW_RECT.position
	offer_row.size = OFFER_ROW_RECT.size
	offer_row.add_theme_constant_override(&"separation", 8)
	offer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(offer_row)
	for slot_index in OFFER_SLOT_COUNT:
		var slot := VBoxContainer.new()
		slot.name = "OfferSlot%d" % slot_index
		slot.custom_minimum_size = Vector2(216, OFFER_ROW_RECT.size.y)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_theme_constant_override(&"separation", 8)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		offer_row.add_child(slot)
		_build_offer_slot(slot, slot_index)


func _build_offer_slot(
	slot: VBoxContainer,
	offer_index: int
) -> void:
	var definition: GogoContentDefinition = null
	if offer_index < _shop.offers.size():
		definition = _shop.offers[offer_index]
	var price_text := "已售出"
	if definition != null:
		price_text = "%d 材料" % _shop.item_pool.price_for(
			definition,
			_app.current_session.run_state.current_wave,
			_app.current_session.run_state.reroll_count
		)
	var card := SHOP_CARD_PRESENTER.build_card(
		definition,
		price_text,
		_static_asset_snapshot(),
		&"shop_offer"
	) as Button
	card.name = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = definition == null
	card.focus_mode = Control.FOCUS_NONE if definition == null else Control.FOCUS_ALL
	card.set_meta(&"focus_role", &"buy")
	card.set_meta(&"offer_index", offer_index)
	if definition != null:
		var buy_index := offer_index
		card.pressed.connect(func() -> void: _buy(buy_index))
	slot.add_child(card)

	var content_id := definition.content_id if definition != null else &""
	var locked := definition != null and (
		_app.current_session.run_state.locked_shop_offer_ids.has(content_id)
	)
	var lock := _shop_button(
		"Lock",
		("解锁" if locked else "锁定") if definition != null else "空槽",
		Callable(),
		Vector2(216, 44)
	)
	lock.disabled = definition == null
	lock.focus_mode = Control.FOCUS_NONE if definition == null else Control.FOCUS_ALL
	lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock.set_meta(&"content_id", content_id)
	lock.set_meta(&"focus_role", &"lock")
	lock.set_meta(&"offer_index", offer_index)
	if definition != null:
		var lock_index := offer_index
		lock.pressed.connect(func() -> void: _toggle_lock(lock_index))
	slot.add_child(lock)


func _build_stats_column(player: SessionPlayerState) -> void:
	var column := VBoxContainer.new()
	column.name = "StatsColumn"
	column.position = STATS_COLUMN_RECT.position
	column.size = STATS_COLUMN_RECT.size
	column.add_theme_constant_override(&"separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "属性"
	heading.custom_minimum_size.y = 30
	heading.add_theme_font_size_override(&"font_size", 24)
	heading.add_theme_color_override(&"font_color", Color("f3edd7"))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	var stat_list := STAT_LIST_PRESENTER.build(
		player,
		_app.current_session.content_snapshot,
		&"shop_compact"
	)
	stat_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stat_list)


func _build_status(status_text: String) -> void:
	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(32, 506)
	_status.size = Vector2(927, 36)
	_status.text = status_text
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override(&"font_size", 17)
	_status.add_theme_color_override(&"font_color", Color("f1ca52"))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


func _build_continue_button() -> void:
	var continue_button := _shop_button(
		"ContinueButton",
		"进入下一波",
		_continue_run,
		Vector2(265, 44)
	)
	continue_button.position = Vector2(983, 510)
	continue_button.set_meta(&"focus_role", &"continue")
	add_child(continue_button)


func _build_loadout(player: SessionPlayerState) -> void:
	var combine_action := Callable()
	if _selected_weapon_slot >= 0 and _selected_weapon_slot < player.weapon_ids.size():
		var selected_id := player.weapon_ids[_selected_weapon_slot]
		if player.weapon_ids.count(selected_id) >= 2:
			combine_action = _combine_weapon
	var loadout := LOADOUT_STRIP_PRESENTER.build(
		player,
		_app.current_session.content_snapshot,
		_static_asset_snapshot(),
		{
			"selected_weapon_slot": _selected_weapon_slot,
			"select": _select_weapon_slot,
			"sell": _sell_weapon,
			"combine": combine_action,
		}
	) as Control
	loadout.name = "LoadoutBar"
	loadout.position = LOADOUT_BAR_RECT.position
	loadout.size = LOADOUT_BAR_RECT.size
	loadout.custom_minimum_size = LOADOUT_BAR_RECT.size
	add_child(loadout)


func _shop_button(
	node_name: String,
	button_text: String,
	callback: Callable,
	minimum_size: Vector2
) -> Button:
	var button := Button.new()
	button.name = node_name
	configure_action_button(button, button_text, callback)
	button.custom_minimum_size = minimum_size
	button.size = minimum_size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override(&"font_size", 20)
	return button


func _buy(index: int) -> void:
	if index < 0 or index >= _shop.offers.size():
		return
	var content_id := _shop.offers[index].content_id
	var error := _shop.buy(_app.current_session, index)
	_rebuild(
		_focus_request(&"buy", content_id, index),
		"购买成功" if error == OK else "购买失败：%s" % error_string(error)
	)


func _toggle_lock(index: int) -> void:
	if index < 0 or index >= _shop.offers.size():
		return
	var content_id := _shop.offers[index].content_id
	var locked := _shop.toggle_lock(_app.current_session, index)
	_rebuild(
		_focus_request(&"lock", content_id, index),
		"已锁定" if locked else "已解锁"
	)


func _reroll() -> void:
	var error := _shop.reroll(_app.current_session)
	_rebuild(
		_focus_request(&"reroll", &"", -1),
		"刷新完成" if error == OK else "材料不足"
	)


func _select_weapon_slot(slot: int) -> void:
	var player := _app.current_session.run_state.player()
	if slot < 0 or slot >= player.weapon_ids.size():
		return
	_selected_weapon_slot = slot
	_rebuild(_focus_request(&"weapon", player.weapon_ids[slot], slot))


func _sell_weapon(slot: int) -> void:
	var player := _app.current_session.run_state.player()
	if slot < 0 or slot >= player.weapon_ids.size():
		return
	var content_id := player.weapon_ids[slot]
	var error := _shop.sell_weapon(_app.current_session, slot)
	_selected_weapon_slot = mini(slot, player.weapon_ids.size() - 1)
	_rebuild(
		_focus_request(&"sell", content_id, _selected_weapon_slot),
		"出售成功" if error == OK else "出售失败"
	)


func _combine_weapon(content_id: StringName) -> void:
	var preferred_slot := _selected_weapon_slot
	var error := _shop.combine_weapon(_app.current_session, content_id)
	var player := _app.current_session.run_state.player()
	if error == OK:
		_selected_weapon_slot = _nearest_weapon_slot(
			player.weapon_ids,
			content_id,
			preferred_slot
		)
	else:
		_clamp_selected_weapon_slot(player)
	_rebuild(
		_focus_request(&"combine", content_id, _selected_weapon_slot, &"weapon"),
		"合成成功" if error == OK else "没有可合成的重复武器"
	)


func _continue_run() -> void:
	if _app.current_session.continue_after_shop():
		_app.save_checkpoint()
		_app.route(FlowRoute.COMBAT)
	else:
		_app.route(FlowRoute.SETTLEMENT)


func _clamp_selected_weapon_slot(player: SessionPlayerState) -> void:
	if player == null or player.weapon_ids.is_empty():
		_selected_weapon_slot = -1
	elif _selected_weapon_slot >= player.weapon_ids.size():
		_selected_weapon_slot = player.weapon_ids.size() - 1


func _focus_request(
	role: StringName,
	content_id: StringName,
	index: int,
	fallback_role: StringName = &""
) -> Dictionary:
	return {
		"role": role,
		"content_id": content_id,
		"index": index,
		"fallback_role": fallback_role,
	}


func _restore_focus(request: Dictionary) -> void:
	if not is_inside_tree():
		return
	var buttons: Array[Button] = []
	for node in find_children("*", "Button", true, false):
		var button := node as Button
		if (
			button != null
			and not button.disabled
			and button.focus_mode != Control.FOCUS_NONE
			and button.is_visible_in_tree()
		):
			buttons.append(button)
	var role := request.get("role", &"") as StringName
	var content_id := request.get("content_id", &"") as StringName
	var index := int(request.get("index", -1))
	var target := _matching_focus_button(buttons, role, content_id, index)
	if target != null:
		target.grab_focus()
		return
	var requested_fallback := request.get("fallback_role", &"") as StringName
	if not requested_fallback.is_empty():
		target = _matching_focus_button(buttons, requested_fallback, content_id, index)
		if target != null:
			target.grab_focus()
			return
	for fallback_role: StringName in [&"reroll", &"continue", &"buy"]:
		target = _matching_focus_button(buttons, fallback_role, &"", -1)
		if target != null:
			target.grab_focus()
			return


func _matching_focus_button(
	buttons: Array[Button],
	role: StringName,
	content_id: StringName,
	index: int
) -> Button:
	for match_mode in 3:
		for button in buttons:
			var button_role := button.get_meta(&"focus_role", &"") as StringName
			var button_id := button.get_meta(&"content_id", &"") as StringName
			var button_index := _button_semantic_index(button)
			match match_mode:
				0:
					if button_role == role and button_id == content_id and button_index == index:
						return button
				1:
					if not content_id.is_empty() and button_role == role and button_id == content_id:
						return button
				2:
					if index >= 0 and button_role == role and button_index == index:
						return button
	if index >= 0:
		var nearest: Button = null
		var nearest_distance := 1 << 30
		for button in buttons:
			if button.get_meta(&"focus_role", &"") != role:
				continue
			var button_index := _button_semantic_index(button)
			if button_index < 0:
				continue
			var distance := absi(button_index - index)
			if distance < nearest_distance:
				nearest = button
				nearest_distance = distance
		if nearest != null:
			return nearest
	for button in buttons:
		if button.get_meta(&"focus_role", &"") == role:
			return button
	return null


func _nearest_weapon_slot(
	weapon_ids: Array[StringName],
	content_id: StringName,
	preferred_slot: int
) -> int:
	var nearest_slot := -1
	var nearest_distance := 1 << 30
	for slot in weapon_ids.size():
		if weapon_ids[slot] != content_id:
			continue
		var distance := absi(slot - preferred_slot)
		if distance < nearest_distance:
			nearest_slot = slot
			nearest_distance = distance
	return nearest_slot


func _button_semantic_index(button: Button) -> int:
	if button.has_meta(&"offer_index"):
		return int(button.get_meta(&"offer_index"))
	if button.has_meta(&"slot_index"):
		return int(button.get_meta(&"slot_index"))
	return -1
