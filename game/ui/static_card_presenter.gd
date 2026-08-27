class_name GogoStaticCardPresenter
extends RefCounted


const CARD_SIZE := Vector2(286, 76)
const TIER_NAMES := ["", "普通", "精良", "稀有", "传说"]


static func build_card(
	definition: GogoContentDefinition,
	price_text: String,
	snapshot: GogoStaticAssetSnapshot
) -> Control:
	var card := Button.new()
	card.name = "StaticCard"
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.text = ""
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.focus_mode = Control.FOCUS_ALL
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.set_meta(&"content_id", definition.content_id if definition != null else &"")

	var frame := _texture_rect("Frame", Vector2(5, 5), Vector2(66, 66))
	var frame_handle: GogoStaticAssetHandle
	if snapshot != null:
		frame_handle = snapshot.resolve_global(&"card_and_rarity_frame_kit")
	frame.texture = frame_handle.texture if frame_handle != null else null
	frame.modulate = _tier_color(_tier(definition))
	card.add_child(frame)

	var icon := _texture_rect("Icon", Vector2(10, 10), Vector2(56, 56))
	var icon_handle: GogoStaticAssetHandle
	if snapshot != null and definition != null and not definition.icon_asset_id.is_empty():
		icon_handle = snapshot.resolve_asset(definition.icon_asset_id, &"icon")
	icon.texture = icon_handle.texture if icon_handle != null else null
	card.add_child(icon)

	var name_label := _label("Name", Vector2(77, 5), Vector2(137, 23), 16)
	name_label.text = definition.display_name if definition != null else "未知道具"
	card.add_child(name_label)

	var tier_label := _label("Tier", Vector2(77, 29), Vector2(56, 17), 12)
	var tier := _tier(definition)
	tier_label.text = TIER_NAMES[clampi(tier, 1, 4)]
	tier_label.add_theme_color_override("font_color", _tier_color(tier))
	card.add_child(tier_label)

	var stat_label := _label("StatLine", Vector2(77, 48), Vector2(137, 19), 10)
	stat_label.text = _stat_line(definition)
	card.add_child(stat_label)

	var price_label := _label("PriceOrState", Vector2(214, 7), Vector2(64, 61), 13)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.text = price_text
	price_label.add_theme_color_override("font_color", Color("f1ca52"))
	card.add_child(price_label)

	return card


static func _texture_rect(node_name: String, at: Vector2, rect_size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.position = at
	texture_rect.size = rect_size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


static func _label(
	node_name: String,
	at: Vector2,
	rect_size: Vector2,
	font_size: int
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = rect_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f3edd7"))
	label.add_theme_color_override("font_outline_color", Color("111416"))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _tier(definition: GogoContentDefinition) -> int:
	if definition is GogoWeaponDefinition:
		return (definition as GogoWeaponDefinition).tier
	if definition is GogoItemDefinition:
		return (definition as GogoItemDefinition).tier
	if definition is GogoUpgradeDefinition:
		return (definition as GogoUpgradeDefinition).tier
	return 1


static func _tier_color(tier: int) -> Color:
	return [
		Color("8d9487"),
		Color("8d9487"),
		Color("55b86b"),
		Color("4c88df"),
		Color("c65ce2"),
	][clampi(tier, 1, 4)]


static func _stat_line(definition: GogoContentDefinition) -> String:
	if definition is GogoWeaponDefinition:
		var weapon := definition as GogoWeaponDefinition
		return "伤害 %.1f · 间隔 %.2fs" % [weapon.damage, weapon.cooldown_seconds]
	var modifiers: Dictionary = {}
	if definition is GogoItemDefinition:
		modifiers = (definition as GogoItemDefinition).stat_modifiers
	elif definition is GogoUpgradeDefinition:
		modifiers = (definition as GogoUpgradeDefinition).stat_modifiers
	var parts: Array[String] = []
	for key: Variant in modifiers:
		var amount := float(modifiers[key])
		parts.append("%s %s%.2f" % [String(key), "+" if amount >= 0.0 else "", amount])
		if parts.size() == 2:
			break
	return " · ".join(parts) if not parts.is_empty() else "大色块像素装备"
