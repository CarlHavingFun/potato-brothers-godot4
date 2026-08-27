class_name GogoStaticCardPresenter
extends RefCounted


const CARD_SIZE := Vector2(294, 76)
const CARD_MINIMUM_SIZE := Vector2(216, 76)
const CARD_BACKGROUND_COLOR := Color("171b1e")
const MINIMUM_RARITY_CONTRAST := 3.0
const TIER_NAMES := ["", "普通", "精良", "稀有", "传说"]
const TIER_FRAME_SELECTORS: Array[StringName] = [
	&"",
	&"common",
	&"uncommon",
	&"rare",
	&"legendary",
]
const BUTTON_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"disabled"]
const MODIFIER_ORDER: Array[StringName] = [
	&"max_health",
	&"health_regen",
	&"movement_speed",
	&"movement_speed_multiplier",
	&"damage_multiplier",
	&"melee_damage",
	&"ranged_damage",
	&"attack_speed",
	&"attack_speed_multiplier",
	&"critical_chance",
	&"armor",
	&"dodge",
	&"pickup_range",
	&"attack_range_bonus",
	&"economy",
	&"explosion_damage_multiplier",
]
const MODIFIER_NAMES := {
	&"max_health": "最大生命",
	&"health_regen": "生命恢复",
	&"movement_speed": "移动速度",
	&"movement_speed_multiplier": "移动速度",
	&"damage_multiplier": "伤害",
	&"melee_damage": "近战伤害",
	&"ranged_damage": "远程伤害",
	&"attack_speed": "攻击速度",
	&"attack_speed_multiplier": "攻击速度",
	&"critical_chance": "暴击率",
	&"armor": "护甲",
	&"dodge": "闪避",
	&"pickup_range": "拾取范围",
	&"attack_range_bonus": "射程",
	&"economy": "经济",
	&"explosion_damage_multiplier": "爆炸伤害",
}
const PERCENT_DELTA_KEYS: Array[StringName] = [
	&"movement_speed_multiplier",
	&"damage_multiplier",
	&"attack_speed_multiplier",
	&"critical_chance",
	&"dodge",
	&"explosion_damage_multiplier",
]

static var _tier_palette_cache: Dictionary = {}


static func build_card(
	definition: GogoContentDefinition,
	price_text: String,
	snapshot: GogoStaticAssetSnapshot
) -> Control:
	var card := Button.new()
	card.name = "StaticCard"
	card.custom_minimum_size = CARD_MINIMUM_SIZE
	card.size = CARD_SIZE
	card.text = ""
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.focus_mode = Control.FOCUS_ALL
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.set_meta(&"content_id", definition.content_id if definition != null else &"")
	var tier := _tier(definition)
	_apply_card_styles(card, tier)

	var accent := ColorRect.new()
	accent.name = "RarityAccent"
	accent.position = Vector2.ZERO
	accent.size = Vector2(4, CARD_SIZE.y)
	card.add_child(accent)
	accent.anchor_bottom = 1.0
	accent.offset_bottom = 0.0
	accent.color = _authored_tier_color(snapshot, tier, definition)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_fallback := ColorRect.new()
	icon_fallback.name = "IconFallback"
	icon_fallback.position = Vector2(6, 6)
	icon_fallback.size = Vector2(64, 64)
	icon_fallback.color = Color("252a2d")
	icon_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_fallback)
	var fallback_label := _label("Label", Vector2.ZERO, Vector2(64, 64), 14)
	fallback_label.text = "无图"
	fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_fallback.add_child(fallback_label)

	var icon := _texture_rect("Icon", Vector2(6, 6), Vector2(64, 64))
	var icon_handle := _icon_handle(definition, snapshot)
	icon.texture = icon_handle.texture if icon_handle != null else null
	icon_fallback.visible = icon.texture == null
	GogoStaticConsumerRegistry.observe_handle(
		icon_handle,
		"res://game/ui/static_card_presenter.gd",
		"StaticCard/Icon/%s" % String(definition.content_id if definition != null else &"unknown")
	)
	card.add_child(icon)

	var name_label := _label("Name", Vector2(78, 1), Vector2(156, 24), 18)
	name_label.text = definition.display_name if definition != null else "未知道具"
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(name_label)
	_pin_between_left_and_price(name_label)

	var stat_rows := VBoxContainer.new()
	stat_rows.name = "StatRows"
	stat_rows.position = Vector2(78, 25)
	stat_rows.size = Vector2(156, 34)
	stat_rows.add_theme_constant_override(&"separation", 0)
	stat_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stat_rows)
	_pin_between_left_and_price(stat_rows)
	var rows := localized_stat_rows(definition)
	for index in 2:
		var row := _label("Stat%d" % (index + 1), Vector2.ZERO, Vector2(156, 17), 11)
		var payload: Dictionary = rows[index] if index < rows.size() else {"text": "", "amount": 0.0}
		row.text = String(payload.get("text", ""))
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var amount := float(payload.get("amount", 0.0))
		if amount > 0.0:
			row.add_theme_color_override(&"font_color", Color("72d572"))
		elif amount < 0.0:
			row.add_theme_color_override(&"font_color", Color("ef6a67"))
		stat_rows.add_child(row)

	var rarity_label := _label("RarityLabel", Vector2(78, 59), Vector2(156, 15), 10)
	rarity_label.text = TIER_NAMES[clampi(tier, 1, 4)]
	rarity_label.add_theme_color_override(&"font_color", _tier_color(tier))
	card.add_child(rarity_label)
	_pin_between_left_and_price(rarity_label)

	var price_label := _label("PriceOrState", Vector2(238, 4), Vector2(50, 68), 12)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price_label.clip_text = true
	price_label.text = price_text
	price_label.add_theme_color_override(&"font_color", Color("f1ca52"))
	card.add_child(price_label)
	_pin_price_to_right(price_label)

	return card


static func localized_stat_rows(definition: GogoContentDefinition) -> Array[Dictionary]:
	if definition is GogoWeaponDefinition:
		var weapon := definition as GogoWeaponDefinition
		return [
			{"text": "伤害 %s" % _unsigned_number(weapon.damage), "amount": 0.0},
			{"text": "攻击间隔 %.2fs" % weapon.cooldown_seconds, "amount": 0.0},
		]
	var modifiers: Dictionary = {}
	if definition is GogoItemDefinition:
		modifiers = (definition as GogoItemDefinition).stat_modifiers
	elif definition is GogoUpgradeDefinition:
		modifiers = (definition as GogoUpgradeDefinition).stat_modifiers
	var result: Array[Dictionary] = []
	for key in MODIFIER_ORDER:
		if not modifiers.has(key):
			continue
		var amount := float(modifiers[key])
		result.append({
			"text": "%s %s" % [String(MODIFIER_NAMES[key]), _signed_modifier(key, amount)],
			"amount": amount,
		})
		if result.size() == 2:
			break
	if result.is_empty():
		result.append({"text": "无额外属性", "amount": 0.0})
	return result


static func apply_button_state_textures(
	button: Button,
	snapshot: GogoStaticAssetSnapshot,
	consumer_node_path: String
) -> void:
	if button == null or snapshot == null:
		return
	var fallback := snapshot.resolve_global(&"four_state_button")
	for state: StringName in BUTTON_STATES:
		var handle := snapshot.resolve_global(&"four_state_button", state)
		if handle == null:
			handle = fallback
		GogoStaticConsumerRegistry.observe_handle(
			handle,
			"res://game/ui/static_card_presenter.gd",
			"%s/%s" % [consumer_node_path, state]
		)
		if handle == null or handle.texture == null:
			continue
		var style := _button_texture_style(handle.texture)
		button.add_theme_stylebox_override(state, style)
		if state == &"hover":
			button.add_theme_stylebox_override(&"focus", style)


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


static func _apply_card_styles(card: Button, tier: int) -> void:
	var rarity := _tier_color(tier)
	card.add_theme_stylebox_override(&"normal", _card_style(Color("171b1e"), Color("394044")))
	card.add_theme_stylebox_override(&"hover", _card_style(Color("20262a"), rarity))
	card.add_theme_stylebox_override(&"focus", _card_style(Color("20262a"), rarity))
	card.add_theme_stylebox_override(&"pressed", _card_style(Color("29231a"), Color("f1a34a")))
	card.add_theme_stylebox_override(&"disabled", _card_style(Color("121518"), Color("303537")))


static func _card_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _button_texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 12.0)
	style.set_content_margin(SIDE_LEFT, 24.0)
	style.set_content_margin(SIDE_TOP, 6.0)
	style.set_content_margin(SIDE_RIGHT, 24.0)
	style.set_content_margin(SIDE_BOTTOM, 6.0)
	return style


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


static func _pin_between_left_and_price(control: Control) -> void:
	control.anchor_right = 1.0
	control.offset_right = -62.0


static func _pin_price_to_right(control: Control) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.offset_left = -56.0
	control.offset_right = -6.0


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
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color("f3edd7"))
	label.add_theme_color_override(&"font_outline_color", Color("111416"))
	label.add_theme_constant_override(&"outline_size", 1)
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
		Color("4c88df"),
		Color("c65ce2"),
		Color("f1ca52"),
	][clampi(tier, 1, 4)]


static func _authored_tier_color(
	snapshot: GogoStaticAssetSnapshot,
	tier: int,
	definition: GogoContentDefinition
) -> Color:
	var fallback := _tier_color(tier)
	if snapshot == null:
		return fallback
	var selector := TIER_FRAME_SELECTORS[clampi(tier, 1, 4)]
	var handle := snapshot.resolve_global(&"card_and_rarity_frame_kit", selector)
	if handle == null:
		handle = snapshot.resolve_global(&"card_and_rarity_frame_kit")
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/ui/static_card_presenter.gd",
		"StaticCard/RarityPalette/%s" % String(
			definition.content_id if definition != null else &"unknown"
		)
	)
	if handle == null or handle.texture == null:
		return fallback
	var cache_key := "%s|%d|%s|%s|%d" % [
		snapshot.registry_sha256,
		snapshot.generation,
		handle.binding_key,
		selector,
		handle.texture.get_instance_id(),
	]
	if _tier_palette_cache.has(cache_key):
		return _tier_palette_cache[cache_key] as Color
	var image := handle.texture.get_image()
	if image == null or image.is_empty():
		return fallback
	var best_color := fallback
	var best_score := -1.0
	var step_x := maxi(1, image.get_width() / 16)
	var step_y := maxi(1, image.get_height() / 16)
	for y in range(0, image.get_height(), step_y):
		for x in range(0, image.get_width(), step_x):
			var sampled := image.get_pixel(x, y)
			var color := Color(sampled.r, sampled.g, sampled.b, 1.0)
			var saturation := color.s
			var contrast := _contrast_ratio(color, CARD_BACKGROUND_COLOR)
			var score := saturation * color.v
			if sampled.a >= 0.5 and contrast >= MINIMUM_RARITY_CONTRAST and score > best_score:
				best_score = score
				best_color = color
	var result := best_color if best_score >= 0.08 else fallback
	_tier_palette_cache[cache_key] = result
	return result


static func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance := _relative_luminance(first)
	var second_luminance := _relative_luminance(second)
	return (
		(maxf(first_luminance, second_luminance) + 0.05)
		/ (minf(first_luminance, second_luminance) + 0.05)
	)


static func _relative_luminance(color: Color) -> float:
	return (
		0.2126 * _linear_channel(color.r)
		+ 0.7152 * _linear_channel(color.g)
		+ 0.0722 * _linear_channel(color.b)
	)


static func _linear_channel(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


static func _signed_modifier(key: StringName, amount: float) -> String:
	var display_amount := amount * 100.0 if PERCENT_DELTA_KEYS.has(key) else amount
	var suffix := "%" if PERCENT_DELTA_KEYS.has(key) else ""
	return "%s%s%s" % ["+" if display_amount > 0.0 else "", _unsigned_number(display_amount), suffix]


static func _unsigned_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
