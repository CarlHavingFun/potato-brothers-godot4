extends GogoScreenBase

const SHOP_CARD_PRESENTER := preload("res://game/ui/static_card_presenter.gd")
const STAT_LIST_PRESENTER := preload("res://game/ui/stat_list_presenter.gd")
const LOADOUT_STRIP_PRESENTER := preload("res://game/ui/loadout_strip_presenter.gd")
const GogoWeaponQualityRules := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")
const OFFER_SLOT_COUNT := 4
const OFFER_ROW_RECT := Rect2(32, 100, 927, 384)
const STATS_COLUMN_RECT := Rect2(983, 100, 265, 394)
const LOADOUT_BAR_RECT := Rect2(32, 570, 1216, 118)
const OFFER_LABEL_COLOR_META := &"shop_offer_normal_font_color"
const OFFER_LABEL_OUTLINE_COLOR_META := &"shop_offer_normal_outline_color"
const OFFER_LABEL_OUTLINE_SIZE_META := &"shop_offer_normal_outline_size"

var _app: AppKernel
var _shop := ShopRuntimeService.new()
var _status: Label
var _offer_description: Label
var _offer_flavor: Label
var _selected_weapon_instance_id := 0
var _materials_flash_label: Label
var _materials_flash_tween: Tween
var _materials_flash_had_override := false
var _materials_flash_color := Color.WHITE
var _battlefield_backdrop: Texture2D
var _has_battlefield_backdrop_payload := false
var _weapon_action_menu: Control
var _weapon_action_target_id := 0
var _weapon_action_generation := 0
var _weapon_action_busy := false


func receive_route_payload(payload: Dictionary) -> void:
	_has_battlefield_backdrop_payload = payload.has("battlefield_backdrop")
	_battlefield_backdrop = payload.get("battlefield_backdrop") as Texture2D


func _ready() -> void:
	_app = AppContext.kernel(self)
	if _app == null or _app.current_session == null:
		return
	_shop.open_shop(_app.current_session)
	_rebuild(_focus_request(&"buy", &"", 0))


func _rebuild(
	focus_request: Dictionary = {},
	status_text: String = "",
	flash_materials: bool = false
) -> void:
	_clear_weapon_action_menu()
	var resolved_focus_request := (
		focus_request
		if not focus_request.is_empty()
		else _focus_request(&"buy", &"", 0)
	)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	body = null
	var player := _app.current_session.run_state.player()
	_validate_selected_weapon(player)
	_build_top_band(player)
	_build_battlefield_backdrop()
	_build_offer_row()
	_build_stats_column(player)
	_build_status(status_text)
	_build_offer_details()
	_build_continue_button()
	_build_loadout(player)
	_show_owned_weapon_details()
	call_deferred("_restore_focus", resolved_focus_request)
	if flash_materials:
		call_deferred("_flash_materials")


func _build_battlefield_backdrop() -> void:
	# A headless viewport cannot always produce a Texture2D, but the route still
	# carries the battlefield intent. Keep that state distinct from a normal shop
	# opened without a combat backdrop so rebuilds are deterministic in both modes.
	if not _has_battlefield_backdrop_payload:
		return
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
	veil.color = Color(0.0, 0.0, 0.0, 0.74)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	move_child(veil, 2)


func _build_top_band(player: SessionPlayerState) -> void:
	build_screen_chrome("", "")
	var top_band := get_node("TitleBand") as Control
	top_band.name = "TopBand"
	var wave := top_band.get_node("Title") as Label
	wave.name = "Wave"
	wave.position = Vector2.ZERO
	wave.size = Vector2(430, 64)
	wave.text = ("无尽 · 第 %d 波 · 商店" if _app.current_session.run_state.endless else "第 %d 波 · 商店") % _app.current_session.run_state.current_wave
	wave.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var materials := top_band.get_node("Subtitle") as Label
	materials.name = "Materials"
	materials.position = Vector2(470, 10)
	materials.size = Vector2(450, 44)
	materials.text = "金币 %d   武器 %d/6" % [player.materials, player.weapon_ids.size()]
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
		Vector2(216, 56)
	)
	reroll.position = Vector2(1000, 8)
	reroll.set_meta(&"focus_role", &"reroll")
	top_band.add_child(reroll)


func _build_offer_row() -> void:
	# This is page-level battlefield suppression, not an offer-slot placeholder.
	# Purchased slots remain true null/childless holes while a bright player or
	# weapon behind the shop can no longer be mistaken for leftover card content.
	var row_veil := ColorRect.new()
	row_veil.name = "OfferRowVeil"
	row_veil.position = OFFER_ROW_RECT.position - Vector2(8, 8)
	row_veil.size = OFFER_ROW_RECT.size + Vector2(16, 16)
	row_veil.color = Color(0.0, 0.0, 0.0, 0.82)
	row_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row_veil)

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
	if definition == null:
		# Brotato leaves purchased offer columns visually empty. The fixed-width
		# slot remains only to keep the surviving cards from jumping horizontally.
		slot.set_meta(&"empty_offer_slot", true)
		return
	var price := _shop.item_pool.price_for(
		definition,
		_app.current_session.run_state.current_wave,
		_app.current_session.run_state.reroll_count
	)
	var price_text := "%d 金币" % price
	var card := SHOP_CARD_PRESENTER.build_card(
		definition,
		price_text,
		_static_asset_snapshot(),
		&"shop_offer",
		GogoHudSkin.COLOR_NEGATIVE if _app.current_session.run_state.player().materials < price else Color("f1ca52")
	) as Button
	card.name = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = false
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta(&"focus_role", &"buy")
	card.set_meta(&"offer_index", offer_index)
	_prepare_offer_card_focus(card)
	var buy_index := offer_index
	card.pressed.connect(func() -> void: _buy(buy_index))
	slot.add_child(card)

	var content_id := definition.content_id if definition != null else &""
	var locked := (
		_app.current_session.run_state.locked_shop_offer_ids.has(content_id)
	)
	var lock := _shop_button(
		"Lock",
		"解锁" if locked else "锁定",
		Callable(),
		Vector2(216, 56)
	)
	lock.disabled = false
	lock.focus_mode = Control.FOCUS_ALL
	lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock.set_meta(&"content_id", content_id)
	lock.set_meta(&"focus_role", &"lock")
	lock.set_meta(&"offer_index", offer_index)
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


func _prepare_offer_card_focus(card: Button) -> void:
	var accent := card.get_node_or_null("RarityAccent") as ColorRect
	if accent != null:
		card.remove_child(accent)
		accent.free()
	card.gui_input.connect(_on_offer_card_gui_input.bind(card))
	card.focus_entered.connect(_set_offer_card_content_focus.bind(card, true))
	card.focus_entered.connect(_show_offer_details.bind(card))
	card.focus_exited.connect(_set_offer_card_content_focus.bind(card, false))
	_set_offer_card_content_focus(card, false)


func _on_offer_card_gui_input(event: InputEvent, card: Button) -> void:
	if event is InputEventMouseMotion:
		card.grab_focus()


func _set_offer_card_content_focus(card: Button, focused: bool) -> void:
	if not is_instance_valid(card):
		return
	for node in card.find_children("*", "Label", true, false):
		var label := node as Label
		if not label.has_meta(OFFER_LABEL_COLOR_META):
			label.set_meta(OFFER_LABEL_COLOR_META, label.get_theme_color(&"font_color"))
			label.set_meta(
				OFFER_LABEL_OUTLINE_COLOR_META,
				label.get_theme_color(&"font_outline_color")
			)
			label.set_meta(
				OFFER_LABEL_OUTLINE_SIZE_META,
				label.get_theme_constant(&"outline_size")
			)
		if focused:
			label.add_theme_color_override(&"font_color", GogoHudSkin.COLOR_TEXT_FOCUS)
			label.add_theme_color_override(&"font_outline_color", Color.TRANSPARENT)
			label.add_theme_constant_override(&"outline_size", 0)
		else:
			label.add_theme_color_override(
				&"font_color",
				label.get_meta(OFFER_LABEL_COLOR_META) as Color
			)
			label.add_theme_color_override(
				&"font_outline_color",
				label.get_meta(OFFER_LABEL_OUTLINE_COLOR_META) as Color
			)
			label.add_theme_constant_override(
				&"outline_size",
				int(label.get_meta(OFFER_LABEL_OUTLINE_SIZE_META))
			)


func _build_status(status_text: String) -> void:
	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(32, 484)
	_status.size = Vector2(927, 20)
	_status.text = status_text
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override(&"font_size", 16)
	_status.add_theme_color_override(&"font_color", Color("f1ca52"))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


func _flash_materials() -> void:
	var materials := get_node_or_null("TopBand/Materials") as Label
	if materials == null:
		return
	if _materials_flash_tween != null: _materials_flash_tween.kill()
	if not is_instance_valid(_materials_flash_label) or _materials_flash_label != materials:
		_materials_flash_label = materials
		_materials_flash_had_override = materials.has_theme_color_override(&"font_color")
		_materials_flash_color = materials.get_theme_color(&"font_color")
	var had_font_color_override := _materials_flash_had_override
	var original_font_color := _materials_flash_color
	materials.add_theme_color_override(&"font_color", GogoHudSkin.COLOR_NEGATIVE)
	var tween := create_tween()
	_materials_flash_tween = tween
	tween.tween_interval(0.22)
	tween.tween_callback(func() -> void:
		if is_instance_valid(materials):
			if had_font_color_override:
				materials.add_theme_color_override(&"font_color", original_font_color)
			else:
				materials.remove_theme_color_override(&"font_color")
		_materials_flash_label = null
		_materials_flash_tween = null
	)


func _build_offer_details() -> void:
	var backing := ColorRect.new()
	backing.name = "OfferDetailsBacking"
	backing.position = Vector2(32, 506)
	backing.size = Vector2(927, 54)
	backing.color = Color(0.0, 0.0, 0.0, 0.66)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backing)
	_offer_description = _offer_detail_label(
		"OfferDescription",
		Vector2(32, 508),
		Vector2(927, 24),
		17,
		Color("eee8d9")
	)
	add_child(_offer_description)
	_offer_flavor = _offer_detail_label(
		"OfferFlavor",
		Vector2(32, 534),
		Vector2(927, 22),
		15,
		Color("b9b4a8")
	)
	add_child(_offer_flavor)
	for definition: GogoContentDefinition in _shop.offers:
		if definition != null:
			_set_offer_detail_copy(definition)
			return


func _show_offer_details(card: Button) -> void:
	if not is_instance_valid(card):
		return
	var offer_index := int(card.get_meta(&"offer_index", -1))
	if offer_index < 0 or offer_index >= _shop.offers.size():
		return
	var definition := _shop.offers[offer_index] as GogoContentDefinition
	if definition != null:
		_set_offer_detail_copy(definition)


func _set_offer_detail_copy(definition: GogoContentDefinition) -> void:
	if _offer_description == null or _offer_flavor == null:
		return
	_offer_description.add_theme_color_override(&"font_color", Color("eee8d9"))
	var description := _first_sentence(String(definition.get_meta(&"description", "")))
	var flavor := _single_line(String(definition.get_meta(&"flavor", "")))
	_offer_description.text = (
		definition.display_name
		if description.is_empty()
		else "%s · %s" % [definition.display_name, description]
	)
	_offer_flavor.text = flavor
	if definition is GogoWeaponDefinition:
		_offer_description.text = "%s I · 伤害 %s" % [definition.display_name, _damage_text(WeaponRuntimeService.new().build_instance(definition, _app.current_session.run_state.player()).damage)]


func _show_owned_weapon_details() -> void:
	var player := _app.current_session.run_state.player()
	var record := player.weapon_inventory.record(_selected_weapon_instance_id)
	if record.is_empty(): return
	var definition := _app.current_session.content_snapshot.definition(record.content_id, &"weapon") as GogoWeaponDefinition
	if definition == null: return
	var service := WeaponRuntimeService.new()
	var current := service.build_instance(definition, player, record.quality)
	var partner := player.weapon_inventory.combination_partner(_selected_weapon_instance_id)
	var damage := _damage_text(current.damage)
	if partner != 0:
		damage += " → " + _damage_text(service.build_instance(definition, player, record.quality + 1).damage)
	_offer_description.text = "%s %s · 伤害 %s" % [definition.display_name, GogoWeaponQualityRules.label(record.quality), damage]
	_offer_description.add_theme_color_override(&"font_color", GogoWeaponQualityRules.color(record.quality))
	var combination_reason := "无同品质合成伙伴"
	if record.quality == 4:
		combination_reason = "已达最高品质，无法合成"
	elif partner != 0:
		combination_reason = "合成伙伴 #%d" % partner
	_offer_flavor.text = "出售 %d 金币 · %s" % [GogoWeaponQualityRules.sale_price(definition.price, record.quality), combination_reason]


func _damage_text(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")


func _offer_detail_label(
	node_name: String,
	at: Vector2,
	rect_size: Vector2,
	font_size: int,
	font_color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = rect_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", font_color)
	label.add_theme_color_override(&"font_outline_color", Color("111416"))
	label.add_theme_constant_override(&"outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _first_sentence(copy: String) -> String:
	var normalized := _single_line(copy)
	for separator in ["。", "！", "？"]:
		var index := normalized.find(separator)
		if index >= 0:
			return normalized.left(index + 1)
	return normalized


func _single_line(copy: String) -> String:
	return copy.replace("\r", " ").replace("\n", " ").strip_edges()


func _build_continue_button() -> void:
	var session := _app.current_session
	if session.is_final_shop():
		# Reserve room beside the final actions without obscuring item details.
		for detail_name in ["OfferDetailsBacking", "OfferDescription", "OfferFlavor"]:
			(get_node(detail_name) as Control).size.x = 648.0
		var finish := _shop_button("FinishRunButton", "结束并结算", _finish_run, Vector2(265, 64))
		GogoHudSkin.apply_action_button(finish, &"secondary", false, true)
		finish.position = Vector2(700, 510)
		finish.set_meta(&"focus_role", &"finish")
		add_child(finish)
		var endless := _shop_button("EndlessButton", "继续无尽", _continue_endless, Vector2(265, 64))
		GogoHudSkin.apply_action_button(endless, &"primary", false, true)
		endless.position = Vector2(983, 510)
		endless.set_meta(&"focus_role", &"continue")
		add_child(endless)
		return
	if session.run_state.ended or session.run_state.phase != &"shop" or session.run_state.pending_upgrade_count != 0 or session.run_state.player().current_health <= 0.0:
		return
	var continue_button := _shop_button(
		"ContinueButton",
		"进入下一波",
		_continue_run,
		Vector2(265, 64)
	)
	GogoHudSkin.apply_action_button(continue_button, &"primary", false, true)
	continue_button.position = Vector2(983, 510)
	continue_button.set_meta(&"focus_role", &"continue")
	add_child(continue_button)


func _build_loadout(player: SessionPlayerState) -> void:
	var loadout := LOADOUT_STRIP_PRESENTER.build(
		player,
		_app.current_session.content_snapshot,
		_static_asset_snapshot(),
		{
			"selected_weapon_instance_id": _selected_weapon_instance_id,
			"select": _select_weapon,
		}
	) as Control
	loadout.name = "LoadoutBar"
	loadout.position = LOADOUT_BAR_RECT.position
	loadout.size = LOADOUT_BAR_RECT.size
	loadout.custom_minimum_size = LOADOUT_BAR_RECT.size
	var items := loadout.get_node("Items") as HBoxContainer
	items.position.y = 48.0
	var weapons := loadout.get_node("Weapons") as HBoxContainer
	weapons.position.y = 40.0
	var items_title := _loadout_title("ItemsTitle", "道具", Vector2(0, 4), Vector2(736, 30))
	loadout.add_child(items_title)
	var weapons_title := _loadout_title(
		"WeaponsTitle",
		"武器 %d/6" % player.weapon_ids.size(),
		Vector2(764, 4),
		Vector2(452, 30)
	)
	loadout.add_child(weapons_title)
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
	var resolved_size := Vector2(minimum_size.x, maxf(minimum_size.y, 56.0))
	GogoHudSkin.apply_action_button(button, &"primary", false, true)
	button.custom_minimum_size = resolved_size
	button.size = resolved_size
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return button


func _buy(index: int) -> void:
	var content_id: StringName = &""
	if index >= 0 and index < _shop.offers.size() and _shop.offers[index] != null:
		content_id = _shop.offers[index].content_id
	var error := _shop.buy(_app.current_session, index)
	if error != OK:
		_show_failure()
		return
	_rebuild(
		_focus_request(&"buy", content_id, index),
		"购买成功"
	)


func _toggle_lock(index: int) -> void:
	if index < 0 or index >= _shop.offers.size():
		return
	if _shop.offers[index] == null:
		return
	var content_id := _shop.offers[index].content_id
	var locked := _shop.toggle_lock(_app.current_session, index)
	_rebuild(
		_focus_request(&"lock", content_id, index),
		"已锁定" if locked else "已解锁"
	)


func _loadout_title(
	node_name: String,
	label_text: String,
	at: Vector2,
	rect_size: Vector2
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = label_text
	label.position = at
	label.size = rect_size
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", GogoHudSkin.COLOR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _reroll() -> void:
	var error := _shop.reroll(_app.current_session)
	if error != OK:
		_show_failure()
		return
	_rebuild(
		_focus_request(&"reroll", &"", -1),
		"刷新完成"
	)


func _show_failure() -> void:
	if _status != null: _status.text = _shop_failure_status()
	if is_instance_valid(_weapon_action_menu):
		var failure := _weapon_action_menu.get_node_or_null("Panel/Failure") as Label
		if failure != null:
			failure.text = _shop_failure_status()
	if _shop.last_failure_reason == "insufficient_materials": _flash_materials()


func _shop_failure_status() -> String:
	match _shop.last_failure_reason:
		"insufficient_materials":
			return "金币不足"
		"weapon_slots_full":
			return "武器栏已满（6槽）"
		"item_limit_reached":
			return "道具持有上限"
		"invalid_offer":
			return "报价已失效"
		"unavailable_content":
			return "内容不可用"
		"all_offers_locked":
			return "全部报价已锁定"
		"invalid_weapon_instance":
			return "武器已失效"
		"no_matching_weapon":
			return "没有同品质的可合成武器"
		"inventory_id_exhausted":
			return "武器库存编号已耗尽"
		"sale_credit_overflow":
			return "金币已达上限，无法出售"
		"unavailable_session":
			return "当前无法操作武器"
		_:
			return "购买失败"


func _select_weapon(inventory_instance_id: int) -> void:
	var player := _app.current_session.run_state.player()
	if player.weapon_inventory.index_of(inventory_instance_id) < 0: return
	_selected_weapon_instance_id = inventory_instance_id
	_rebuild(_weapon_focus_request(inventory_instance_id))
	call_deferred("_open_weapon_action_menu", inventory_instance_id)


func _sell_weapon(inventory_instance_id: int) -> void:
	var session := _app.current_session
	var player := session.run_state.player() if session != null and session.run_state != null else null
	var slot := player.weapon_inventory.index_of(inventory_instance_id) if player != null and player.weapon_inventory != null else -1
	var error := _shop.sell_weapon(_app.current_session, inventory_instance_id)
	if error != OK:
		_show_failure()
		return
	var records := player.weapon_inventory.records()
	_selected_weapon_instance_id = records[mini(slot, records.size() - 1)].instance_id if not records.is_empty() else 0
	_rebuild(_weapon_focus_request(_selected_weapon_instance_id), "出售成功")


func _combine_weapon(inventory_instance_id: int) -> void:
	var error := _shop.combine_weapon(_app.current_session, inventory_instance_id)
	if error != OK:
		_show_failure()
		return
	_selected_weapon_instance_id = inventory_instance_id
	_rebuild(_weapon_focus_request(inventory_instance_id), "合成成功")


func _open_weapon_action_menu(inventory_instance_id: int) -> void:
	var player := _current_action_player()
	if player == null:
		return
	var record := player.weapon_inventory.record(inventory_instance_id)
	if record.is_empty():
		return
	var definition := _app.current_session.content_snapshot.definition(record.content_id, &"weapon") as GogoWeaponDefinition
	if definition == null:
		return
	_clear_weapon_action_menu()
	_weapon_action_target_id = inventory_instance_id
	_weapon_action_generation += 1
	var generation := _weapon_action_generation
	var menu := Control.new()
	menu.name = "WeaponActionMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.gui_input.connect(_on_weapon_action_menu_gui_input.bind(generation))
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.0, 0.0, 0.0, 0.74)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_weapon_action_menu_gui_input.bind(generation))
	menu.add_child(scrim)
	var panel := Panel.new()
	panel.name = "Panel"
	panel.position = Vector2(390, 88)
	panel.size = Vector2(500, 544)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	GogoHudSkin.apply_panel(panel, &"surface")
	menu.add_child(panel)
	var title := _weapon_action_label("Title", "武器操作", Vector2(28, 20), Vector2(444, 36), 28, GogoHudSkin.COLOR_TEXT)
	panel.add_child(title)
	var name_label := _weapon_action_label("DisplayName", definition.display_name, Vector2(28, 68), Vector2(444, 30), 22, GogoHudSkin.COLOR_TEXT)
	panel.add_child(name_label)
	var quality := int(record.quality)
	var quality_label := _weapon_action_label("Quality", "品质 %s" % GogoWeaponQualityRules.label(quality), Vector2(28, 104), Vector2(444, 28), 19, GogoWeaponQualityRules.color(quality))
	panel.add_child(quality_label)
	var id_label := _weapon_action_label("InstanceId", "实例 ID #%d" % inventory_instance_id, Vector2(28, 136), Vector2(444, 26), 17, Color("d5d0c3"))
	panel.add_child(id_label)
	var sale_value := GogoWeaponQualityRules.sale_price(definition.price, quality)
	var sale_label := _weapon_action_label("SaleValue", "出售可得 %d 金币" % sale_value, Vector2(28, 174), Vector2(444, 30), 19, Color("f1ca52"))
	panel.add_child(sale_label)
	var partner := player.weapon_inventory.combination_partner(inventory_instance_id)
	var reason := _weapon_combine_reason(quality, partner)
	var combine_detail := _weapon_action_label("CombineDetail", reason, Vector2(28, 212), Vector2(444, 62), 17, Color("d5d0c3"))
	combine_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combine_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	panel.add_child(combine_detail)
	var failure := _weapon_action_label("Failure", "", Vector2(28, 278), Vector2(444, 30), 16, GogoHudSkin.COLOR_NEGATIVE)
	failure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(failure)
	var sell := _shop_button("SellButton", "出售 %d 金币" % sale_value, func() -> void: _weapon_action_sell(inventory_instance_id, generation), Vector2(444, 56))
	sell.position = Vector2(28, 324)
	sell.set_meta(&"focus_role", &"weapon_action_sell")
	panel.add_child(sell)
	var combine := _shop_button("CombineButton", "合成", func() -> void: _weapon_action_combine(inventory_instance_id, generation), Vector2(444, 56))
	combine.position = Vector2(28, 392)
	combine.set_meta(&"focus_role", &"weapon_action_combine")
	combine.disabled = quality >= 4 or partner == 0
	combine.focus_mode = Control.FOCUS_NONE if combine.disabled else Control.FOCUS_ALL
	panel.add_child(combine)
	var cancel := _shop_button("CancelButton", "取消", func() -> void: _close_weapon_action_menu(), Vector2(444, 56))
	cancel.position = Vector2(28, 460)
	cancel.set_meta(&"focus_role", &"weapon_action_cancel")
	panel.add_child(cancel)
	_weapon_action_menu = menu
	add_child(menu)
	_set_weapon_action_focus_loop([cancel, sell] if combine.disabled else [cancel, sell, combine])
	call_deferred("_focus_weapon_action_cancel", generation)


func _weapon_action_label(node_name: String, text: String, at: Vector2, rect_size: Vector2, font_size: int, font_color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = at
	label.size = rect_size
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", font_color)
	label.add_theme_color_override(&"font_outline_color", Color("111416"))
	label.add_theme_constant_override(&"outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _weapon_combine_reason(quality: int, partner: int) -> String:
	if quality >= 4:
		return "已达最高品质 IV，无法合成"
	if partner == 0:
		return "无同品质合成伙伴"
	return "合成伙伴 #%d · 下一品质 %s" % [partner, GogoWeaponQualityRules.label(quality + 1)]


func _set_weapon_action_focus_loop(buttons: Array) -> void:
	for index in buttons.size():
		var current := buttons[index] as Button
		var next := buttons[(index + 1) % buttons.size()] as Button
		var previous := buttons[(index - 1 + buttons.size()) % buttons.size()] as Button
		var next_path: NodePath = current.get_path_to(next)
		var previous_path: NodePath = current.get_path_to(previous)
		current.focus_neighbor_top = previous_path
		current.focus_neighbor_bottom = next_path
		current.focus_neighbor_left = previous_path
		current.focus_neighbor_right = next_path
		current.focus_next = next_path
		current.focus_previous = previous_path


func _focus_weapon_action_cancel(generation: int) -> void:
	if generation != _weapon_action_generation or not is_instance_valid(_weapon_action_menu):
		return
	var cancel := _weapon_action_menu.get_node_or_null("Panel/CancelButton") as Button
	if cancel != null and not cancel.disabled:
		cancel.grab_focus()


func _on_weapon_action_menu_gui_input(event: InputEvent, generation: int) -> void:
	if generation != _weapon_action_generation:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		_close_weapon_action_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_instance_valid(_weapon_action_menu):
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		_close_weapon_action_menu()


func _weapon_action_sell(inventory_instance_id: int, generation: int) -> void:
	if not _weapon_action_is_current(inventory_instance_id, generation):
		return
	if _current_action_player().weapon_inventory.record(inventory_instance_id).is_empty():
		_close_missing_weapon_action_target()
		return
	_weapon_action_busy = true
	var session := _app.current_session
	var player := _current_action_player()
	var slot := player.weapon_inventory.index_of(inventory_instance_id)
	var error := _shop.sell_weapon(session, inventory_instance_id)
	_weapon_action_busy = false
	if error != OK:
		_show_failure()
		return
	var records := player.weapon_inventory.records()
	_selected_weapon_instance_id = records[mini(slot, records.size() - 1)].instance_id if not records.is_empty() else 0
	_clear_weapon_action_menu()
	_rebuild(_weapon_focus_request(_selected_weapon_instance_id), "出售成功")


func _weapon_action_combine(inventory_instance_id: int, generation: int) -> void:
	if not _weapon_action_is_current(inventory_instance_id, generation):
		return
	var player := _current_action_player()
	var record := player.weapon_inventory.record(inventory_instance_id)
	if record.is_empty():
		_close_missing_weapon_action_target()
		return
	var partner := player.weapon_inventory.combination_partner(inventory_instance_id)
	if int(record.quality) >= 4 or partner == 0:
		_refresh_weapon_action_menu(record, partner)
		return
	_weapon_action_busy = true
	var error := _shop.combine_weapon(_app.current_session, inventory_instance_id)
	_weapon_action_busy = false
	if error != OK:
		_show_failure()
		return
	_selected_weapon_instance_id = inventory_instance_id
	_clear_weapon_action_menu()
	_rebuild(_weapon_focus_request(inventory_instance_id), "合成成功")


func _weapon_action_is_current(inventory_instance_id: int, generation: int) -> bool:
	return not _weapon_action_busy and generation == _weapon_action_generation and inventory_instance_id == _weapon_action_target_id and is_instance_valid(_weapon_action_menu) and _current_action_player() != null


func _current_action_player() -> SessionPlayerState:
	if _app == null or _app.current_session == null or _app.current_session.run_state == null:
		return null
	return _app.current_session.run_state.player()


func _refresh_weapon_action_menu(record: Dictionary, partner: int) -> void:
	if not is_instance_valid(_weapon_action_menu):
		return
	var reason := _weapon_action_menu.get_node_or_null("Panel/CombineDetail") as Label
	if reason != null:
		reason.text = _weapon_combine_reason(int(record.quality), partner)
	var combine := _weapon_action_menu.get_node_or_null("Panel/CombineButton") as Button
	if combine != null:
		combine.disabled = true
		combine.focus_mode = Control.FOCUS_NONE
		var cancel := _weapon_action_menu.get_node_or_null("Panel/CancelButton") as Button
		var sell := _weapon_action_menu.get_node_or_null("Panel/SellButton") as Button
		if cancel != null and sell != null:
			_set_weapon_action_focus_loop([cancel, sell])
			cancel.grab_focus()
	var failure := _weapon_action_menu.get_node_or_null("Panel/Failure") as Label
	if failure != null:
		failure.text = "合成条件已变化"


func _close_weapon_action_menu() -> void:
	var focus_id := _weapon_action_target_id
	_clear_weapon_action_menu()
	call_deferred("_restore_focus", _weapon_focus_request(focus_id))


func _close_missing_weapon_action_target() -> void:
	var player := _current_action_player()
	var records: Array = player.weapon_inventory.records() if player != null else []
	_selected_weapon_instance_id = records[0].instance_id if not records.is_empty() else 0
	var focus_request := (
		_weapon_focus_request(_selected_weapon_instance_id)
		if _selected_weapon_instance_id != 0
		else _focus_request(&"reroll", &"", -1)
	)
	_rebuild(focus_request)


func _clear_weapon_action_menu() -> void:
	_weapon_action_generation += 1
	_weapon_action_busy = false
	_weapon_action_target_id = 0
	if is_instance_valid(_weapon_action_menu):
		_weapon_action_menu.queue_free()
	_weapon_action_menu = null


func _continue_run() -> void:
	_clear_weapon_action_menu()
	if _app.current_session != null and _app.current_session.continue_after_shop():
		var save_error := _app.save_checkpoint()
		if save_error != OK:
			_app.route(FlowRoute.DIAGNOSTIC, {"message": "存档保存失败", "details": [_app.profile_service.last_error]})
			return
		_app.route(FlowRoute.COMBAT)


func _finish_run() -> void:
	_clear_weapon_action_menu()
	if _app.current_session != null and _app.current_session.finish_normal_run():
		_app.route(FlowRoute.SETTLEMENT)


func _continue_endless() -> void:
	_clear_weapon_action_menu()
	if _app.current_session != null and _app.current_session.continue_endless():
		var save_error := _app.save_checkpoint()
		if save_error != OK:
			_app.route(FlowRoute.DIAGNOSTIC, {"message": "存档保存失败", "details": [_app.profile_service.last_error]})
			return
		_app.route(FlowRoute.COMBAT)


func _validate_selected_weapon(player: SessionPlayerState) -> void:
	if player == null or player.weapon_inventory.index_of(_selected_weapon_instance_id) < 0:
		_selected_weapon_instance_id = 0


func _weapon_focus_request(inventory_instance_id: int) -> Dictionary:
	return {"role": &"weapon", "inventory_instance_id": inventory_instance_id}


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
	if request.has("inventory_instance_id"):
		for button in buttons:
			if button.get_meta(&"focus_role", &"") == role and button.get_meta(&"inventory_instance_id", 0) == request.inventory_instance_id:
				button.grab_focus()
				_show_owned_weapon_details()
				return
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


func _button_semantic_index(button: Button) -> int:
	if button.has_meta(&"offer_index"):
		return int(button.get_meta(&"offer_index"))
	if button.has_meta(&"slot_index"):
		return int(button.get_meta(&"slot_index"))
	return -1
