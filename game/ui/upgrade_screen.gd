extends GogoScreenBase

const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const CHOICE_ROW_RECT := Rect2(32, 150, 927, 215)
const STATS_COLUMN_RECT := Rect2(983, 100, 265, 496)

var _app: AppKernel
var _offers: Array[GogoUpgradeDefinition] = []
var _build_service := PlayerBuildService.new()
var _battlefield_backdrop: Texture2D


func _ready() -> void:
	_app = AppContext.kernel(self)
	if _app == null or _app.current_session == null:
		return
	_show_offers()


func receive_route_payload(payload: Dictionary) -> void:
	_battlefield_backdrop = payload.get("battlefield_backdrop") as Texture2D


func _show_offers(focus_index: int = 0, status_text: String = "") -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	build_screen_chrome("升级奖励", "战斗结束后选择一项强化")
	_build_battlefield_backdrop()
	var player := _app.current_session.run_state.player()
	_build_reward_status(player, status_text)
	_offers = _build_service.upgrade_reward_offers(_app.current_session)
	_build_choice_row()
	_build_stats_column(player)
	_build_reroll_button()
	call_deferred("_restore_choice_focus", focus_index)


func _build_battlefield_backdrop() -> void:
	(get_node("StaticMenuBackground") as TextureRect).visible = false
	(get_node("ReadabilityVeil") as ColorRect).visible = false
	var backdrop := TextureRect.new()
	backdrop.name = "BattlefieldBackdrop"
	backdrop.texture = _battlefield_backdrop
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 1)
	var veil := ColorRect.new()
	veil.name = "DimVeil"
	veil.color = Color(0.015, 0.02, 0.025, 0.80)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	move_child(veil, 2)


func _build_reward_status(player: SessionPlayerState, status_text: String) -> void:
	var status := Label.new()
	status.name = "RewardStatus"
	status.position = Vector2(32, 100)
	status.size = Vector2(927, 42)
	status.text = (
		status_text
		if not status_text.is_empty()
		else "选择一项升级 · 剩余 %d 次 · 材料 %d" % [
			_app.current_session.run_state.pending_upgrade_count,
			player.materials,
		]
	)
	status.add_theme_font_size_override(&"font_size", 22)
	status.add_theme_color_override(&"font_color", Color("f1ca52"))
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)


func _build_choice_row() -> void:
	var row := HBoxContainer.new()
	row.name = "UpgradeChoiceRow"
	row.position = CHOICE_ROW_RECT.position
	row.size = CHOICE_ROW_RECT.size
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for index in _offers.size():
		var definition := _offers[index]
		var card := add_static_card(
			definition,
			"选择",
			func() -> void: _choose(definition, index),
			false,
			row
		)
		card.name = "UpgradeChoice%d" % index
		card.custom_minimum_size = Vector2(224, 215)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_meta(&"focus_role", &"upgrade_choice")
		card.set_meta(&"offer_index", index)
		_configure_choice_card(card)


func _configure_choice_card(card: Button) -> void:
	card.size = Vector2(224, 215)
	for node_name: StringName in [&"IconFallback", &"Icon"]:
		var icon_control := card.get_node(NodePath(node_name)) as Control
		icon_control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		icon_control.position = Vector2(72, 8)
		icon_control.size = Vector2(80, 80)
	var name_label := card.get_node("Name") as Label
	name_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	name_label.position = Vector2(10, 92)
	name_label.size = Vector2(204, 28)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 20)
	var stat_rows := card.get_node("StatRows") as VBoxContainer
	stat_rows.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stat_rows.position = Vector2(12, 124)
	stat_rows.size = Vector2(200, 38)
	stat_rows.add_theme_constant_override(&"separation", 2)
	for row in stat_rows.get_children():
		(row as Label).custom_minimum_size.y = 18
		(row as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rarity := card.get_node("RarityLabel") as Label
	rarity.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rarity.position = Vector2(12, 166)
	rarity.size = Vector2(200, 16)
	rarity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var action := card.get_node("PriceOrState") as Label
	action.set_anchors_preset(Control.PRESET_TOP_LEFT)
	action.position = Vector2(12, 187)
	action.size = Vector2(200, 22)
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


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
	column.add_child(heading)
	var stats := STAT_LIST_PRESENTER.build(
		player,
		_app.current_session.content_snapshot,
		&"shop_compact"
	)
	stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stats)


func _build_reroll_button() -> void:
	var reroll := Button.new()
	reroll.name = "RerollButton"
	reroll.position = Vector2(32, 388)
	reroll.size = Vector2(240, 48)
	reroll.custom_minimum_size = reroll.size
	reroll.text = "刷新 %d" % _build_service.upgrade_reroll_price(_app.current_session)
	reroll.add_theme_font_size_override(&"font_size", 20)
	reroll.set_meta(&"focus_role", &"upgrade_reroll")
	reroll.pressed.connect(_reroll)
	add_child(reroll)


func _reroll() -> void:
	var error := _build_service.reroll_upgrade_rewards(_app.current_session)
	_show_offers(
		-1,
		"刷新完成" if error == OK else "材料不足"
	)


func _choose(definition: GogoUpgradeDefinition, previous_index: int) -> void:
	var session := _app.current_session
	if _build_service.apply_upgrade(session, session.run_state.player(), definition.content_id) != OK:
		return
	session.run_state.pending_upgrade_count = maxi(session.run_state.pending_upgrade_count - 1, 0)
	session.state_changed.emit()
	if session.run_state.pending_upgrade_count > 0:
		_show_offers(previous_index)
		return
	session.transition(&"shop")
	_app.route(FlowRoute.SHOP)


func _restore_choice_focus(index: int) -> void:
	if not is_inside_tree():
		return
	var target := get_node_or_null("UpgradeChoiceRow/UpgradeChoice%d" % maxi(index, 0)) as Button
	if target == null:
		target = get_node_or_null("UpgradeChoiceRow/UpgradeChoice0") as Button
	if target != null:
		target.grab_focus()


func _modifier_text(modifiers: Dictionary) -> String:
	var parts: Array[String] = []
	for key in modifiers:
		var amount := float(modifiers[key])
		parts.append("%s %s%.2f" % [String(key), "+" if amount >= 0.0 else "", amount])
	return ", ".join(parts)
