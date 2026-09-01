class_name GogoLoadoutStripPresenter
extends RefCounted

const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const GogoWeaponQualityRules := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")

const WEAPON_SLOT_COUNT := 6
const WEAPON_SLOT_SIZE := Vector2(72, 72)
const ITEM_ICON_SIZE := Vector2(48, 48)
const EXPANDED_ITEM_ICON_SIZE := Vector2(64, 64)
const MAX_VISIBLE_ITEMS := 8


static func build(
	player: SessionPlayerState,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot,
	actions: Dictionary
) -> Control:
	var expanded := bool(actions.get("expanded", false))
	var item_icon_size := EXPANDED_ITEM_ICON_SIZE if expanded else ITEM_ICON_SIZE
	var strip: Control
	if expanded:
		strip = Panel.new()
		HUD_SKIN.apply_panel(strip, &"surface")
	else:
		strip = Control.new()
	strip.name = "LoadoutStrip"
	strip.custom_minimum_size = Vector2(620, 480) if expanded else Vector2(1216, 88)
	strip.size = strip.custom_minimum_size

	var items: Container
	if expanded:
		var item_scroll := ScrollContainer.new()
		item_scroll.name = "ItemsScroll"
		item_scroll.position = Vector2(20, 202)
		item_scroll.size = Vector2(580, 258)
		item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		item_scroll.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		strip.add_child(item_scroll)
		var item_grid := GridContainer.new()
		item_grid.name = "ItemsGrid"
		item_grid.columns = 8
		item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_grid.add_theme_constant_override(&"h_separation", 8)
		item_grid.add_theme_constant_override(&"v_separation", 8)
		item_scroll.add_child(item_grid)
		items = item_grid
	else:
		var item_row := HBoxContainer.new()
		item_row.name = "Items"
		item_row.position = Vector2(0, 16)
		item_row.size = Vector2(736, 56)
		item_row.add_theme_constant_override(&"separation", 8)
		strip.add_child(item_row)
		items = item_row
	if player != null:
		var visible_count := (
			player.item_ids.size()
			if expanded
			else mini(player.item_ids.size(), MAX_VISIBLE_ITEMS)
		)
		for index in visible_count:
			items.add_child(_item_icon(
				index,
				player.item_ids[index],
				content,
				snapshot,
				item_icon_size
			))
		var overflow_count := 0 if expanded else player.item_ids.size() - visible_count
		if overflow_count > 0:
			var overflow := Label.new()
			overflow.name = "Overflow"
			overflow.text = "+%d" % overflow_count
			overflow.custom_minimum_size = item_icon_size
			overflow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			overflow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			overflow.add_theme_font_size_override(&"font_size", 18)
			overflow.add_theme_color_override(&"font_color", Color("f3edd7"))
			items.add_child(overflow)

	var weapons := HBoxContainer.new()
	weapons.name = "Weapons"
	weapons.position = Vector2(20, 62) if expanded else Vector2(764, 8)
	weapons.size = Vector2(452, 72)
	weapons.add_theme_constant_override(&"separation", 4)
	strip.add_child(weapons)
	var selected_id := int(actions.get("selected_weapon_instance_id", 0))
	var records: Array[Dictionary] = player.weapon_inventory.records() if player != null and player.weapon_inventory != null else []
	var weapon_count := records.size()
	for slot_index in weapon_count:
		weapons.add_child(_weapon_slot(
			slot_index,
			records[slot_index],
			content,
			snapshot,
			actions,
			records[slot_index].instance_id == selected_id
		))
	if weapon_count == 0:
		var empty := Label.new()
		empty.name = "EmptyWeapons"
		empty.text = "尚未装备武器"
		empty.custom_minimum_size = Vector2(452, 72)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.add_theme_font_size_override(&"font_size", 20)
		empty.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT)
		weapons.add_child(empty)
	return strip


static func _weapon_slot(
	slot_index: int,
	record: Dictionary,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot,
	actions: Dictionary,
	selected: bool
) -> Button:
	var weapon_id: StringName = record.content_id
	var inventory_instance_id: int = record.instance_id
	var quality: int = record.quality
	var slot := Button.new()
	slot.name = "WeaponSlot%d" % slot_index
	slot.custom_minimum_size = WEAPON_SLOT_SIZE
	slot.size = WEAPON_SLOT_SIZE
	slot.text = ""
	slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot.set_meta(&"slot_index", slot_index)
	slot.set_meta(&"content_id", weapon_id)
	slot.set_meta(&"inventory_instance_id", inventory_instance_id)
	slot.set_meta(&"quality", quality)
	slot.set_meta(&"focus_role", &"weapon")
	var occupied := not weapon_id.is_empty()
	slot.disabled = not occupied
	slot.focus_mode = Control.FOCUS_ALL if occupied else Control.FOCUS_NONE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if occupied else Control.MOUSE_FILTER_IGNORE
	_apply_slot_styles(slot, selected, occupied)
	var select_action: Callable = actions.get("select", Callable())
	if occupied and select_action.is_valid():
		slot.pressed.connect(func() -> void: select_action.call(inventory_instance_id))

	var definition := _definition(content, weapon_id, &"weapon")
	slot.tooltip_text = "%s %s" % [_display_name(definition, weapon_id), GogoWeaponQualityRules.label(quality)]
	var edge := ColorRect.new()
	edge.name = "RarityEdge"
	edge.position = Vector2.ZERO
	edge.size = Vector2(4, 72)
	edge.color = GogoWeaponQualityRules.color(quality)
	edge.visible = not weapon_id.is_empty()
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(edge)

	var icon := _icon_rect("Icon", Vector2(4, 4), Vector2(64, 64))
	var icon_handle: GogoStaticAssetHandle
	if definition == null or definition.direct_icon_texture == null:
		icon_handle = _icon_handle(definition, snapshot)
	icon.texture = (
		definition.direct_icon_texture
		if definition != null and definition.direct_icon_texture != null
		else (icon_handle.texture if icon_handle != null else null)
	)
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
	fallback.text = "" if weapon_id.is_empty() else _display_name(definition, weapon_id)
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
	var badge := Label.new()
	badge.name = "QualityBadge"
	badge.position = Vector2(44, 4)
	badge.size = Vector2(24, 18)
	badge.text = GogoWeaponQualityRules.label(quality)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override(&"font_size", 12)
	badge.add_theme_color_override(&"font_color", GogoWeaponQualityRules.color(quality))
	badge.add_theme_color_override(&"font_outline_color", Color("111416"))
	badge.add_theme_constant_override(&"outline_size", 2)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(badge)

	return slot


static func _item_icon(
	index: int,
	item_id: StringName,
	content: ContentSnapshot,
	snapshot: GogoStaticAssetSnapshot,
	icon_size: Vector2 = ITEM_ICON_SIZE
) -> Control:
	var root := Control.new()
	root.name = "ItemIcon%d" % index
	root.custom_minimum_size = icon_size
	root.size = icon_size
	root.set_meta(&"content_id", item_id)
	var definition := _definition(content, item_id, &"item")
	var backing := ColorRect.new()
	backing.name = "Backing"
	backing.size = icon_size
	backing.color = Color("171b1e")
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backing)
	var edge := ColorRect.new()
	edge.name = "RarityEdge"
	edge.size = Vector2(3, icon_size.y)
	edge.color = _tier_color(_tier(definition))
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(edge)
	var inner_size := icon_size - Vector2(8, 8)
	var icon := _icon_rect("Icon", Vector2(4, 4), inner_size)
	var icon_handle: GogoStaticAssetHandle
	if definition == null or definition.direct_icon_texture == null:
		icon_handle = _icon_handle(definition, snapshot)
	icon.texture = (
		definition.direct_icon_texture
		if definition != null and definition.direct_icon_texture != null
		else (icon_handle.texture if icon_handle != null else null)
	)
	GogoStaticConsumerRegistry.observe_handle(
		icon_handle,
		"res://game/ui/loadout_strip_presenter.gd",
		"Loadout/ItemIcon%d/Icon" % index
	)
	root.add_child(icon)
	var fallback := Label.new()
	fallback.name = "FallbackLabel"
	fallback.position = Vector2(4, 4)
	fallback.size = inner_size
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


static func _apply_slot_styles(slot: Button, selected: bool, occupied: bool) -> void:
	HUD_SKIN.apply_slot(slot, selected, occupied)


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
