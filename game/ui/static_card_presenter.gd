class_name GogoStaticCardPresenter
extends RefCounted

const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const GogoWeaponQualityRules := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")

const STAT_ICON_PRESENTER := preload("res://game/ui/stat_icon_presenter.gd")
const CARD_SIZE := Vector2(294, 76)
const CARD_MINIMUM_SIZE := Vector2(216, 76)
const CARD_BACKGROUND_COLOR := Color("171b1e")
const CARD_FOCUS_BORDER_COLOR := Color("f4e6b0")
const MINIMUM_RARITY_CONTRAST := 3.0
const TIER_NAMES := ["", "普通", "稀有", "史诗", "传说"]
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
	&"counter_strafe_brake",
	&"moving_recoil_control",
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
	&"counter_strafe_brake": "急停制动",
	&"moving_recoil_control": "跑打控枪",
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
const PERCENT_POINT_KEYS: Array[StringName] = [
	&"counter_strafe_brake",
	&"moving_recoil_control",
]

static var _tier_palette_cache: Dictionary = {}


static func build_card(
	definition: GogoContentDefinition,
	price_text: String,
	snapshot: GogoStaticAssetSnapshot,
	layout_variant: StringName = &"compact",
	price_color: Color = Color("f1ca52"),
	weapon_quality: int = 1
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
	card.set_meta(&"content_kind", definition.kind if definition != null else &"")
	var is_weapon := definition is GogoWeaponDefinition
	if is_weapon: card.set_meta(&"quality", weapon_quality)
	if definition != null:
		card.tooltip_text = _card_tooltip_text(definition, weapon_quality)
	var tier := weapon_quality if is_weapon else _tier(definition)
	_apply_card_styles(card, tier, layout_variant)

	var accent := ColorRect.new()
	accent.name = "RarityAccent"
	accent.position = Vector2.ZERO
	accent.size = Vector2(4, CARD_SIZE.y)
	card.add_child(accent)
	accent.anchor_bottom = 1.0
	accent.offset_bottom = 0.0
	accent.color = GogoWeaponQualityRules.color(weapon_quality) if is_weapon else _authored_tier_color(snapshot, tier, definition)
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
	var icon_handle: GogoStaticAssetHandle
	if definition == null or definition.direct_icon_texture == null:
		icon_handle = _icon_handle(definition, snapshot)
	icon.texture = (
		definition.direct_icon_texture
		if definition != null and definition.direct_icon_texture != null
		else (icon_handle.texture if icon_handle != null else null)
	)
	icon_fallback.visible = icon.texture == null
	GogoStaticConsumerRegistry.observe_handle(
		icon_handle,
		"res://game/ui/static_card_presenter.gd",
		"StaticCard/Icon/%s" % String(definition.content_id if definition != null else &"unknown")
	)
	card.add_child(icon)

	var name_label := _label("Name", Vector2(78, 1), Vector2(156, 24), 18)
	name_label.text = (
		definition.display_name
		if definition != null
		else "未知道具"
	)
	if is_weapon: name_label.text += " " + GogoWeaponQualityRules.label(weapon_quality)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(name_label)
	_pin_between_left_and_price(name_label)

	var type_badge := _label("TypeBadge", Vector2.ZERO, Vector2.ZERO, 13)
	type_badge.text = _content_type_label(definition)
	type_badge.visible = false
	type_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_badge.add_theme_color_override(
		&"font_color",
		HUD_SKIN.COLOR_TYPE
	)
	card.add_child(type_badge)

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
		var row := HBoxContainer.new()
		row.name = "Stat%d" % (index + 1)
		row.custom_minimum_size = Vector2(156, 17)
		row.add_theme_constant_override(&"separation", 3)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var payload: Dictionary = (
			rows[index]
			if index < rows.size()
			else {"text": "", "amount": 0.0, "stat_key": &""}
		)
		var stat_key := payload.get("stat_key", &"") as StringName
		row.add_child(STAT_ICON_PRESENTER.build_icon(stat_key, Vector2(14, 14)))
		var row_text := _label("Text", Vector2.ZERO, Vector2(139, 17), 11)
		row_text.text = String(payload.get("text", ""))
		row_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_text.clip_text = true
		row_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var amount := float(payload.get("amount", 0.0))
		if amount > 0.0:
			row_text.add_theme_color_override(&"font_color", Color("72d572"))
		elif amount < 0.0:
			row_text.add_theme_color_override(&"font_color", Color("ef6a67"))
		row.add_child(row_text)
		stat_rows.add_child(row)

	var rarity_label := _label("RarityLabel", Vector2(78, 59), Vector2(156, 15), 10)
	rarity_label.text = GogoWeaponQualityRules.label(weapon_quality) if is_weapon else TIER_NAMES[clampi(tier, 1, 4)]
	rarity_label.add_theme_color_override(&"font_color", GogoWeaponQualityRules.color(weapon_quality) if is_weapon else _tier_color(tier))
	card.add_child(rarity_label)
	_pin_between_left_and_price(rarity_label)

	var price_label := _label("PriceOrState", Vector2(238, 4), Vector2(50, 68), 12)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	price_label.clip_text = true
	price_label.text = price_text
	price_label.add_theme_color_override(&"font_color", price_color)
	card.add_child(price_label)
	_pin_price_to_right(price_label)
	if layout_variant == &"shop_offer":
		_apply_shop_offer_layout(card)

	return card


static func localized_stat_rows(definition: GogoContentDefinition) -> Array[Dictionary]:
	var all_rows := _all_localized_stat_rows(definition)
	if all_rows.size() <= 2:
		return all_rows

	var primary_positive: Dictionary = {}
	var primary_negative: Dictionary = {}
	for payload in all_rows:
		var amount := float(payload.get("amount", 0.0))
		if amount > 0.0 and primary_positive.is_empty():
			primary_positive = payload
		elif amount < 0.0 and primary_negative.is_empty():
			primary_negative = payload
	if not primary_positive.is_empty() and not primary_negative.is_empty():
		return [primary_positive, primary_negative]

	var first_two: Array[Dictionary] = []
	first_two.append(all_rows[0])
	first_two.append(all_rows[1])
	return first_two


static func _all_localized_stat_rows(definition: GogoContentDefinition) -> Array[Dictionary]:
	if definition is GogoWeaponDefinition:
		var weapon := definition as GogoWeaponDefinition
		return [
			{
				"text": "伤害 %s" % _unsigned_number(weapon.damage),
				"amount": 0.0,
				"stat_key": &"melee_damage" if weapon.mode == GogoWeaponDefinition.Mode.MELEE else &"ranged_damage",
			},
			{
				"text": "攻击间隔 %.2fs" % weapon.cooldown_seconds,
				"amount": 0.0,
				"stat_key": &"attack_speed",
			},
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
			"stat_key": key,
		})
	if result.is_empty():
		result.append({"text": "无额外属性", "amount": 0.0, "stat_key": &""})
	return result


static func _card_tooltip_text(definition: GogoContentDefinition, weapon_quality: int = 1) -> String:
	if definition == null:
		return ""
	var lines := PackedStringArray([definition.display_name])
	if definition is GogoWeaponDefinition: lines[0] += " " + GogoWeaponQualityRules.label(weapon_quality)
	for metadata_key: StringName in [&"description", &"flavor"]:
		var copy := String(definition.get_meta(metadata_key, "")).strip_edges()
		if not copy.is_empty():
			lines.append(copy)
	for payload in _all_localized_stat_rows(definition):
		var stat_text := String(payload.get("text", "")).strip_edges()
		if not stat_text.is_empty():
			lines.append(stat_text)
	return "\n".join(lines)


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


static func _apply_card_styles(
	card: Button,
	_tier: int,
	layout_variant: StringName
) -> void:
	HUD_SKIN.apply_card(card, false, layout_variant == &"shop_offer")


static func _card_style(background: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style


static func _button_texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	# The approved 64px state cells contain 13-14px of transparent padding above
	# and below the visible button. Crop that authored canvas padding at draw time;
	# otherwise a 44px control renders as a thin 16px strip behind Chinese text.
	style.region_rect = Rect2(4.0, 13.0, 55.0, 38.0)
	style.set_texture_margin(SIDE_LEFT, 12.0)
	style.set_texture_margin(SIDE_TOP, 10.0)
	style.set_texture_margin(SIDE_RIGHT, 12.0)
	style.set_texture_margin(SIDE_BOTTOM, 10.0)
	style.set_content_margin(SIDE_LEFT, 24.0)
	style.set_content_margin(SIDE_TOP, 8.0)
	style.set_content_margin(SIDE_RIGHT, 24.0)
	style.set_content_margin(SIDE_BOTTOM, 8.0)
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


static func _apply_shop_offer_layout(card: Button) -> void:
	card.custom_minimum_size = Vector2(216, 320)
	card.size = Vector2(216, 320)

	var accent := card.get_node("RarityAccent") as ColorRect
	accent.offset_right = 4.0

	for node_name: StringName in [&"IconFallback", &"Icon"]:
		var icon_control := card.get_node(NodePath(node_name)) as Control
		icon_control.anchor_left = 0.5
		icon_control.anchor_right = 0.5
		icon_control.position = Vector2.ZERO
		icon_control.offset_left = -64.0
		icon_control.offset_top = 8.0
		icon_control.offset_right = 64.0
		icon_control.offset_bottom = 136.0
	var fallback_label := card.get_node("IconFallback/Label") as Label
	fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var name_label := card.get_node("Name") as Label
	name_label.anchor_left = 0.0
	name_label.anchor_right = 1.0
	name_label.position = Vector2.ZERO
	name_label.offset_left = 12.0
	name_label.offset_top = 140.0
	name_label.offset_right = -12.0
	name_label.offset_bottom = 172.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var type_badge := card.get_node("TypeBadge") as Label
	type_badge.visible = not type_badge.text.is_empty()
	type_badge.anchor_left = 0.0
	type_badge.anchor_right = 1.0
	type_badge.position = Vector2.ZERO
	type_badge.offset_left = 14.0
	type_badge.offset_top = 170.0
	type_badge.offset_right = -14.0
	type_badge.offset_bottom = 192.0

	var stat_rows := card.get_node("StatRows") as VBoxContainer
	stat_rows.anchor_left = 0.0
	stat_rows.anchor_right = 1.0
	stat_rows.position = Vector2.ZERO
	stat_rows.offset_left = 14.0
	stat_rows.offset_top = 196.0
	stat_rows.offset_right = -14.0
	stat_rows.offset_bottom = 248.0
	stat_rows.add_theme_constant_override(&"separation", 4)
	for child in stat_rows.get_children():
		var stat_row := child as HBoxContainer
		stat_row.custom_minimum_size.y = 24.0
		stat_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var rarity_label := card.get_node("RarityLabel") as Label
	rarity_label.anchor_left = 0.0
	rarity_label.anchor_right = 1.0
	rarity_label.position = Vector2.ZERO
	rarity_label.offset_left = 12.0
	rarity_label.offset_top = 250.0
	rarity_label.offset_right = -12.0
	rarity_label.offset_bottom = 268.0
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var price_label := card.get_node("PriceOrState") as Label
	price_label.anchor_left = 0.0
	price_label.anchor_right = 1.0
	price_label.position = Vector2.ZERO
	price_label.offset_left = 12.0
	price_label.offset_top = 268.0
	price_label.offset_right = -12.0
	price_label.offset_bottom = 310.0
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.autowrap_mode = TextServer.AUTOWRAP_OFF


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


static func _content_type_label(definition: GogoContentDefinition) -> String:
	return HUD_SKIN.type_label(definition)


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
	var is_fraction_percent := PERCENT_DELTA_KEYS.has(key)
	var display_amount := amount * 100.0 if is_fraction_percent else amount
	var suffix := "%" if is_fraction_percent or PERCENT_POINT_KEYS.has(key) else ""
	return "%s%s%s" % ["+" if display_amount > 0.0 else "", _unsigned_number(display_amount), suffix]


static func _unsigned_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
