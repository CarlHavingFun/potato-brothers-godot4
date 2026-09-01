class_name GogoHudSkin
extends RefCounted


const BUTTON_NORMAL := preload("res://game/assets/ui/hud_v2/button_normal.png")
const BUTTON_FOCUS := preload("res://game/assets/ui/hud_v2/button_focus.png")
const BUTTON_PRESSED := preload("res://game/assets/ui/hud_v2/button_pressed.png")
const BUTTON_DISABLED := preload("res://game/assets/ui/hud_v2/button_disabled.png")
const SURFACE_TEXTURE := preload("res://game/assets/ui/hud_v2/content_panel.png")
const DIALOG_TEXTURE := preload("res://game/assets/ui/hud_v2/modal_panel.png")
const SHOP_CARD_TEXTURE := preload("res://game/assets/ui/hud_v2/shop_card.png")
const SLOT_TEXTURE := preload("res://game/assets/ui/hud_v2/loadout_slot.png")

const COLOR_BACKGROUND := Color("07090a")
const COLOR_TEXT := Color("f5f1e5")
const COLOR_TEXT_MUTED := Color("b9b4a8")
const COLOR_TEXT_FOCUS := Color("151515")
const COLOR_FOCUS := Color("f2a241")
const COLOR_POSITIVE := Color("66d977")
const COLOR_NEGATIVE := Color("f05e63")
const COLOR_TYPE := Color("eae2b0")
const COLOR_PANEL := Color(0.0, 0.0, 0.0, 0.90)
const COLOR_PANEL_SOFT := Color(0.0, 0.0, 0.0, 0.78)
const COLOR_CONTROL := Color("111517")
const COLOR_CONTROL_BORDER := Color("252a2d")
const COLOR_CONTROL_DISABLED := Color("0b0e10")
const COLOR_CONTROL_DISABLED_BORDER := Color("171a1c")
const COLOR_CONTROL_FOCUS := Color("f1dfb5")
const COLOR_CONTROL_PRESSED := Color("e6bd78")

const BUTTON_HEIGHT_PRIMARY := 64.0
const BUTTON_HEIGHT_STANDARD := 56.0
const BUTTON_HEIGHT_COMPACT := 48.0

const BUTTON_PATCH_MARGIN := 20.0
const PANEL_PATCH_MARGIN := 16.0
const DIALOG_PATCH_MARGIN := 24.0
const SHOP_CARD_PATCH_MARGIN := 20.0
const SLOT_PATCH_MARGIN := 18.0

static func apply_action_button(
	button: Button,
	variant: StringName = &"standard",
	danger: bool = false,
	textured: bool = false
) -> Button:
	if button == null:
		return button
	button.custom_minimum_size.y = button_height(variant)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_font_size_override(
		&"font_size",
		26 if variant == &"primary" else 22
	)
	button.add_theme_color_override(
		&"font_color",
		COLOR_NEGATIVE if danger else COLOR_TEXT
	)
	button.add_theme_color_override(&"font_hover_color", COLOR_TEXT_FOCUS)
	button.add_theme_color_override(&"font_focus_color", COLOR_TEXT_FOCUS)
	button.add_theme_color_override(&"font_pressed_color", COLOR_TEXT_FOCUS)
	button.add_theme_color_override(&"font_disabled_color", Color(COLOR_TEXT, 0.20))
	if textured:
		button.add_theme_stylebox_override(
			&"normal",
			_texture_style(BUTTON_NORMAL, BUTTON_PATCH_MARGIN, 18.0, 8.0)
		)
		var focus_style := _texture_style(BUTTON_FOCUS, BUTTON_PATCH_MARGIN, 18.0, 8.0)
		button.add_theme_stylebox_override(&"hover", focus_style)
		button.add_theme_stylebox_override(&"focus", focus_style)
		button.add_theme_stylebox_override(
			&"pressed",
			_texture_style(BUTTON_PRESSED, BUTTON_PATCH_MARGIN, 18.0, 8.0)
		)
		button.add_theme_stylebox_override(
			&"disabled",
			_texture_style(BUTTON_DISABLED, BUTTON_PATCH_MARGIN, 18.0, 8.0)
		)
	else:
		button.add_theme_stylebox_override(&"normal", _control_style(
			COLOR_CONTROL,
			COLOR_CONTROL_BORDER,
			10.0,
			8.0
		))
		button.add_theme_stylebox_override(&"hover", _control_style(
			COLOR_CONTROL_FOCUS,
			COLOR_CONTROL_FOCUS,
			10.0,
			8.0
		))
		button.add_theme_stylebox_override(&"focus", _control_style(
			COLOR_CONTROL_FOCUS,
			COLOR_CONTROL_FOCUS,
			10.0,
			8.0
		))
		button.add_theme_stylebox_override(&"pressed", _control_style(
			COLOR_CONTROL_PRESSED,
			COLOR_CONTROL_PRESSED,
			10.0,
			8.0
		))
		button.add_theme_stylebox_override(&"disabled", _control_style(
			COLOR_CONTROL_DISABLED,
			COLOR_CONTROL_DISABLED_BORDER,
			10.0,
			8.0
		))
	var legacy_fill := button.get_node_or_null("ButtonFill")
	if legacy_fill != null:
		legacy_fill.queue_free()
	return button


static func apply_panel(panel: Control, variant: StringName = &"surface") -> Control:
	if panel == null:
		return panel
	var style: StyleBox
	match variant:
		&"dialog":
			style = _texture_style(DIALOG_TEXTURE, DIALOG_PATCH_MARGIN, 0.0, 0.0)
		&"stats":
			style = _flat_surface(COLOR_PANEL, 8)
		&"soft":
			style = _flat_surface(COLOR_PANEL_SOFT, 8)
		_:
			style = _texture_style(SURFACE_TEXTURE, PANEL_PATCH_MARGIN, 0.0, 0.0)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if panel is Panel:
		(panel as Panel).add_theme_stylebox_override(&"panel", style)
	elif panel is PanelContainer:
		(panel as PanelContainer).add_theme_stylebox_override(&"panel", style)
	return panel


static func apply_card(
	card: Button,
	selected: bool = false,
	textured: bool = false
) -> Button:
	if card == null:
		return card
	var normal := _control_style(COLOR_CONTROL, COLOR_CONTROL_BORDER, 12.0, 12.0)
	var hover := _control_style(
		COLOR_CONTROL_FOCUS,
		COLOR_CONTROL_FOCUS,
		12.0,
		12.0
	)
	var pressed := _control_style(
		COLOR_CONTROL_PRESSED,
		COLOR_CONTROL_PRESSED,
		12.0,
		12.0
	)
	var disabled := _control_style(
		COLOR_CONTROL_DISABLED,
		COLOR_CONTROL_DISABLED_BORDER,
		12.0,
		12.0
	)
	card.add_theme_stylebox_override(
		&"normal",
		_texture_style(SHOP_CARD_TEXTURE, SHOP_CARD_PATCH_MARGIN, 12.0, 12.0)
		if textured and not selected
		else normal
	)
	card.add_theme_stylebox_override(&"hover", hover)
	card.add_theme_stylebox_override(&"focus", hover)
	card.add_theme_stylebox_override(&"pressed", pressed)
	card.add_theme_stylebox_override(&"disabled", disabled)
	card.add_theme_color_override(&"font_color", COLOR_TEXT)
	card.add_theme_color_override(&"font_hover_color", COLOR_TEXT_FOCUS)
	card.add_theme_color_override(&"font_focus_color", COLOR_TEXT_FOCUS)
	card.add_theme_color_override(&"font_pressed_color", COLOR_TEXT_FOCUS)
	if selected:
		card.add_theme_stylebox_override(&"normal", hover)
		card.add_theme_color_override(&"font_color", COLOR_TEXT_FOCUS)
	return card


static func apply_slot(
	slot: Button,
	selected: bool = false,
	textured: bool = false
) -> Button:
	if slot == null:
		return slot
	var normal := _control_style(COLOR_CONTROL, COLOR_CONTROL_BORDER, 8.0, 8.0)
	var hover := _control_style(
		COLOR_CONTROL_FOCUS,
		COLOR_CONTROL_FOCUS,
		8.0,
		8.0
	)
	var pressed := _control_style(
		COLOR_CONTROL_PRESSED,
		COLOR_CONTROL_PRESSED,
		8.0,
		8.0
	)
	var disabled := _control_style(
		COLOR_CONTROL_DISABLED,
		COLOR_CONTROL_DISABLED_BORDER,
		8.0,
		8.0
	)
	slot.add_theme_stylebox_override(
		&"normal",
		_texture_style(SLOT_TEXTURE, SLOT_PATCH_MARGIN, 8.0, 8.0)
		if textured and not selected
		else normal
	)
	slot.add_theme_stylebox_override(&"hover", hover)
	slot.add_theme_stylebox_override(&"focus", hover)
	slot.add_theme_stylebox_override(&"pressed", pressed)
	slot.add_theme_stylebox_override(&"disabled", disabled)
	slot.add_theme_color_override(&"font_color", COLOR_TEXT)
	slot.add_theme_color_override(&"font_hover_color", COLOR_TEXT_FOCUS)
	slot.add_theme_color_override(&"font_focus_color", COLOR_TEXT_FOCUS)
	slot.add_theme_color_override(&"font_pressed_color", COLOR_TEXT_FOCUS)
	if selected:
		slot.add_theme_stylebox_override(&"normal", hover)
		slot.add_theme_color_override(&"font_color", COLOR_TEXT_FOCUS)
	return slot


static func type_label(definition: GogoContentDefinition) -> String:
	if definition is GogoWeaponDefinition:
		var weapon := definition as GogoWeaponDefinition
		return "武器 · 近战" if weapon.mode == GogoWeaponDefinition.Mode.MELEE else "武器 · 枪械"
	if definition is GogoItemDefinition:
		return "道具"
	if definition is GogoUpgradeDefinition:
		return "升级"
	return ""


static func button_height(variant: StringName) -> float:
	match variant:
		&"primary":
			return BUTTON_HEIGHT_PRIMARY
		&"compact":
			return BUTTON_HEIGHT_COMPACT
		_:
			return BUTTON_HEIGHT_STANDARD


static func _control_style(
	background: Color,
	border: Color,
	horizontal_content_margin: float,
	vertical_content_margin: float
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.anti_aliasing = false
	style.border_blend = false
	style.set_content_margin(SIDE_LEFT, horizontal_content_margin)
	style.set_content_margin(SIDE_TOP, vertical_content_margin)
	style.set_content_margin(SIDE_RIGHT, horizontal_content_margin)
	style.set_content_margin(SIDE_BOTTOM, vertical_content_margin)
	return style


static func _flat_surface(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.03, 0.03, 0.03, 0.96)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = false
	return style


static func _texture_style(
	texture: Texture2D,
	patch_margin: float,
	horizontal_content_margin: float,
	vertical_content_margin: float
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.region_rect = Rect2(Vector2.ZERO, Vector2(texture.get_size()))
	style.draw_center = true
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, patch_margin)
		style.set_expand_margin(side, 0.0)
	style.set_content_margin(SIDE_LEFT, horizontal_content_margin)
	style.set_content_margin(SIDE_TOP, vertical_content_margin)
	style.set_content_margin(SIDE_RIGHT, horizontal_content_margin)
	style.set_content_margin(SIDE_BOTTOM, vertical_content_margin)
	return style
