class_name GogoLoadoutStripPresenter
extends RefCounted


const WEAPON_SLOT_COUNT := 6
const WEAPON_SLOT_SIZE := Vector2(72, 72)
const ITEM_ICON_SIZE := Vector2(48, 48)
const MAX_VISIBLE_ITEMS := 8


static func build(
	player: SessionPlayerState,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot,
	actions: Dictionary
) -> Control:
	var strip := Control.new()
	strip.name = "LoadoutStrip"
	strip.custom_minimum_size = Vector2(1216, 88)
	strip.size = Vector2(1216, 88)

	var items := HBoxContainer.new()
	items.name = "Items"
	items.position = Vector2(0, 16)
	items.size = Vector2(736, 56)
	items.add_theme_constant_override(&"separation", 8)
	strip.add_child(items)
	if player != null:
		var visible_count := mini(player.item_ids.size(), MAX_VISIBLE_ITEMS)
		for index in visible_count:
			items.add_child(_item_icon(
				index,
				player.item_ids[index],
				content,
				snapshot
			))
		var overflow_count := player.item_ids.size() - visible_count
		if overflow_count > 0:
			var overflow := Label.new()
			overflow.name = "Overflow"
			overflow.text = "+%d" % overflow_count
			overflow.custom_minimum_size = Vector2(48, 48)
			overflow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			overflow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			overflow.add_theme_font_size_override(&"font_size", 18)
			overflow.add_theme_color_override(&"font_color", Color("f3edd7"))
			items.add_child(overflow)

	var weapons := HBoxContainer.new()
	weapons.name = "Weapons"
	weapons.position = Vector2(764, 8)
	weapons.size = Vector2(452, 72)
	weapons.add_theme_constant_override(&"separation", 4)
	strip.add_child(weapons)
	var selected_slot := int(actions.get("selected_weapon_slot", -1))
	for slot_index in WEAPON_SLOT_COUNT:
		var weapon_id := &""
		if player != null and slot_index < player.weapon_ids.size():
			weapon_id = player.weapon_ids[slot_index]
		weapons.add_child(_weapon_slot(
			slot_index,
			weapon_id,
			content,
			snapshot,
			actions,
			slot_index == selected_slot
		))
	return strip


static func _weapon_slot(
	slot_index: int,
	weapon_id: StringName,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot,
	actions: Dictionary,
	selected: bool
) -> Button:
	var slot := Button.new()
	slot.name = "WeaponSlot%d" % slot_index
	slot.custom_minimum_size = WEAPON_SLOT_SIZE
	slot.size = WEAPON_SLOT_SIZE
	slot.text = ""
	slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot.set_meta(&"slot_index", slot_index)
	slot.set_meta(&"content_id", weapon_id)
	slot.set_meta(&"focus_role", &"weapon")
	var occupied := not weapon_id.is_empty()
	slot.disabled = not occupied
	slot.focus_mode = Control.FOCUS_ALL if occupied else Control.FOCUS_NONE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if occupied else Control.MOUSE_FILTER_IGNORE
	_apply_slot_styles(slot, selected)
	var select_action: Callable = actions.get("select", Callable())
	if occupied and select_action.is_valid():
		slot.pressed.connect(func() -> void: select_action.call(slot_index))

	var definition := _definition(content, weapon_id, &"weapon")
	var tier := _tier(definition)
	var edge := ColorRect.new()
	edge.name = "RarityEdge"
	edge.position = Vector2.ZERO
	edge.size = Vector2(4, 72)
	edge.color = _tier_color(tier)
	edge.visible = not weapon_id.is_empty()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(edge)

	var icon := _icon_rect("Icon", Vector2(4, 4), Vector2(64, 64))
	var icon_handle := _icon_handle(definition, snapshot)
	icon.texture = icon_handle.texture if icon_handle != null else null
	GogoStaticConsumerRegistry.observe_handle(
		icon_handle,
		"res://game/ui/loadout_strip_presenter.gd",
		"Loadout/WeaponSlot%d/Icon" % slot_index
	)
	slot.add_child(icon)

	var fallback := Label.new()
	fallback.name = "FallbackLabel"
	fallback.position = Vector2(7, 13)
	fallback.size = Vector2(58, 46)
	fallback.text = "空" if weapon_id.is_empty() else _display_name(definition, weapon_id)
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback.clip_text = true
	fallback.add_theme_font_size_override(&"font_size", 11)
	fallback.add_theme_color_override(&"font_color", Color("ded8c5"))
	fallback.add_theme_color_override(&"font_outline_color", Color("111416"))
	fallback.add_theme_constant_override(&"outline_size", 1)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.visible = icon.texture == null
	slot.add_child(fallback)

	if selected and not weapon_id.is_empty():
		_add_selected_actions(slot, slot_index, weapon_id, actions)
	return slot


static func _add_selected_actions(
	slot: Button,
	slot_index: int,
	weapon_id: StringName,
	actions: Dictionary
) -> void:
	var action_row := HBoxContainer.new()
	action_row.name = "Actions"
	action_row.position = Vector2(4, 50)
	action_row.size = Vector2(64, 18)
	action_row.add_theme_constant_override(&"separation", 2)
	slot.add_child(action_row)
	var sell_action: Callable = actions.get("sell", Callable())
	if sell_action.is_valid():
		var sell := _micro_action_button("SellButton", "售")
		sell.set_meta(&"focus_role", &"sell")
		sell.set_meta(&"slot_index", slot_index)
		sell.set_meta(&"content_id", weapon_id)
		sell.pressed.connect(func() -> void: sell_action.call(slot_index))
		action_row.add_child(sell)
	var combine_action: Callable = actions.get("combine", Callable())
	if combine_action.is_valid():
		var combine := _micro_action_button("CombineButton", "合")
		combine.set_meta(&"focus_role", &"combine")
		combine.set_meta(&"slot_index", slot_index)
		combine.set_meta(&"content_id", weapon_id)
		combine.pressed.connect(func() -> void: combine_action.call(weapon_id))
		action_row.add_child(combine)


static func _item_icon(
	index: int,
	item_id: StringName,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot
) -> Control:
	var root := Control.new()
	root.name = "ItemIcon%d" % index
	root.custom_minimum_size = ITEM_ICON_SIZE
	root.size = ITEM_ICON_SIZE
	root.set_meta(&"content_id", item_id)
	var definition := _definition(content, item_id, &"item")
	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.size = ITEM_ICON_SIZE
	backing.color = Color("171b1e")
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backing)
	var edge := ColorRect.new()
	edge.name = "RarityEdge"
	edge.size = Vector2(3, 48)
	edge.color = _tier_color(_tier(definition))
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(edge)
	var icon := _icon_rect("Icon", Vector2(4, 4), Vector2(40, 40))
	var icon_handle := _icon_handle(definition, snapshot)
	icon.texture = icon_handle.texture if icon_handle != null else null
	GogoStaticConsumerRegistry.observe_handle(
		icon_handle,
		"res://game/ui/loadout_strip_presenter.gd",
		"Loadout/ItemIcon%d/Icon" % index
	)
	root.add_child(icon)
	var fallback := Label.new()
	fallback.name = "FallbackLabel"
	fallback.position = Vector2(4, 4)
	fallback.size = Vector2(40, 40)
	fallback.text = "无图"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_font_size_override(&"font_size", 10)
	fallback.add_theme_color_override(&"font_color", Color("ded8c5"))
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fallback.visible = icon.texture == null
	root.add_child(fallback)
	return root


static func _definition(
	content: ContentSnapshot,
	content_id: StringName,
	kind: StringName
) -> GogoContentDefinition:
	if content == null or content_id.is_empty():
		return null
	return content.definition(content_id, kind)


static func _icon_handle(
	definition: GogoContentDefinition,
	snapshot: GogoStaticAssetSnapshot
) -> GogoStaticAssetHandle:
	if definition == null or snapshot == null or definition.icon_asset_id.is_empty():
		return null
	var handle := snapshot.resolve_content(definition.kind, definition.content_id, &"icon")
	if handle == null:
		handle = snapshot.resolve_asset(definition.icon_asset_id, &"icon", &"icon")
	if handle == null:
		handle = snapshot.resolve_asset(definition.icon_asset_id, &"icon")
	return handle


static func _display_name(
	definition: GogoContentDefinition,
	content_id: StringName
) -> String:
	return definition.display_name if definition != null else String(content_id)


static func _tier(definition: GogoContentDefinition) -> int:
	if definition is GogoWeaponDefinition:
		return (definition as GogoWeaponDefinition).tier
	if definition is GogoItemDefinition:
		return (definition as GogoItemDefinition).tier
	return 1


static func _tier_color(tier: int) -> Color:
	return [
		Color("8d9487"),
		Color("8d9487"),
		Color("4c88df"),
		Color("c65ce2"),
		Color("f1ca52"),
	][clampi(tier, 1, 4)]


static func _icon_rect(node_name: String, at: Vector2, rect_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.position = at
	icon.size = rect_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


static func _apply_slot_styles(slot: Button, selected: bool) -> void:
	var normal_border := Color("f1a34a") if selected else Color("394044")
	slot.add_theme_stylebox_override(&"normal", _slot_style(Color("171b1e"), normal_border, 1))
	slot.add_theme_stylebox_override(&"hover", _slot_style(Color("20262a"), Color("f1a34a"), 1))
	slot.add_theme_stylebox_override(&"focus", _slot_style(Color("20262a"), Color("f1a34a"), 1))
	slot.add_theme_stylebox_override(&"pressed", _slot_style(Color("29231a"), Color("f1a34a"), 1))


static func _micro_action_button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(31, 18)
	button.add_theme_font_size_override(&"font_size", 10)
	button.add_theme_stylebox_override(&"normal", _slot_style(Color("34302a"), Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override(&"hover", _slot_style(Color("5a432b"), Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override(&"pressed", _slot_style(Color("2a2118"), Color.TRANSPARENT, 0))
	return button


static func _slot_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style
