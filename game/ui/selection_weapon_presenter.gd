extends RefCounted

const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const QUALITY_RULES := preload("res://game/gameplay/weapons/weapon_quality_rules.gd")

var _screen: GogoScreenBase
var _on_selected: Callable
var _stage: Control
var buttons: Array[Button] = []
var column_buttons: Array[Array] = []

# Stable content IDs, not translated names or audio profiles, define the five classes.
const WEAPON_CLASSES := [
	["近战", [&"weapon.training_blade:weapon/training_blade", &"gogobro.preview:weapon/community_tapper"]],
	["手枪", [&"weapon.training_blaster:weapon/training_blaster", &"gogobro.preview:weapon/suppressed_tactical_pistol", &"gogobro.preview:weapon/heavy_hand_cannon"]],
	["冲锋枪", [&"gogobro.preview:weapon/box_submachine_gun", &"gogobro.preview:weapon/compact_submachine_gun", &"gogobro.preview:weapon/bullpup_pdw", &"gogobro.preview:weapon/folding_stock_submachine_gun"]],
	["步枪", [&"gogobro.preview:weapon/wood_stock_assault_rifle", &"gogobro.preview:weapon/suppressed_carbine"]],
	["狙击枪", [&"gogobro.preview:weapon/heavy_bolt_sniper"]],
]


func build(screen: GogoScreenBase, app: AppKernel, on_selected: Callable, stage: Control) -> void:
	_screen = screen
	_on_selected = on_selected
	_stage = stage
	_build_detail()
	_build_columns(app)
	if not buttons.is_empty():
		var definition := app.content_snapshot.definition(buttons[0].get_meta(&"content_id"), &"weapon") as GogoWeaponDefinition
		_show_weapon(definition)


func apply_selection(content_id: StringName) -> void:
	for button in buttons:
		var selected: bool = button.get_meta(&"content_id") == content_id
		button.set_meta(&"selected", selected)
		HUD_SKIN.apply_card(button, selected)
		_update_label(button)
		if selected:
			_show_weapon(button.get_meta(&"definition") as GogoWeaponDefinition)


func _build_detail() -> void:
	var detail := _screen.ui_panel(_stage, "SelectedWeaponDetail", Rect2(348, 104, 900, 166))
	_add_icon(detail, "Icon", Rect2(16, 26, 170, 106))
	_screen.icon_fallback(detail, "IconFallback", Vector2(16, 26), Vector2(170, 106), "无图")
	_screen.ui_label(detail, "Name", Vector2(202, 14), Vector2(358, 38), 28)
	_screen.ui_label(detail, "Mode", Vector2(202, 56), Vector2(358, 28), 20)
	_screen.ui_label(detail, "Damage", Vector2(202, 90), Vector2(168, 30), 22)
	_screen.ui_label(detail, "Cooldown", Vector2(374, 90), Vector2(212, 30), 22)
	var quality := _screen.ui_label(detail, "QualityBadge", Vector2(202, 124), Vector2(80, 28), 20)
	quality.text = QUALITY_RULES.label(1)
	quality.add_theme_color_override(&"font_color", QUALITY_RULES.color(1))
	quality.add_theme_color_override(&"font_outline_color", Color("1a1c20"))
	quality.add_theme_constant_override(&"outline_size", 2)
	var modifiers := _screen.ui_label(detail, "Modifiers", Vector2(598, 20), Vector2(286, 132), 19)
	modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_columns(app: AppKernel) -> void:
	var columns := HBoxContainer.new()
	columns.name = "WeaponColumns"
	columns.position = Vector2(348, 282)
	columns.size = Vector2(900, 354)
	columns.add_theme_constant_override("separation", 10)
	_stage.add_child(columns)
	var option_index := 0
	for class_index in WEAPON_CLASSES.size():
		var column := VBoxContainer.new()
		column.name = "Class%d" % class_index
		column.custom_minimum_size.x = 172
		column.add_theme_constant_override("separation", 8)
		columns.add_child(column)
		var heading := _screen.ui_label(column, "Heading", Vector2.ZERO, Vector2(172, 34), 25)
		heading.custom_minimum_size.y = 34
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.text = WEAPON_CLASSES[class_index][0]
		heading.add_theme_color_override("font_color", HUD_SKIN.COLOR_TYPE)
		var group: Array[Button] = []
		for content_id: StringName in WEAPON_CLASSES[class_index][1]:
			var definition := app.content_snapshot.definition(content_id, &"weapon") as GogoWeaponDefinition
			if definition == null:
				continue
			var button := _weapon_option(definition, option_index)
			column.add_child(button)
			buttons.append(button)
			group.append(button)
			option_index += 1
		column_buttons.append(group)


func _weapon_option(definition: GogoWeaponDefinition, index: int) -> Button:
	var button := Button.new()
	button.name = "WeaponOption%d" % index
	button.tooltip_text = definition.display_name
	button.set_meta(&"content_id", definition.content_id)
	button.set_meta(&"definition", definition)
	button.set_meta(&"selected", false)
	_screen.configure_action_button(button, "", _on_selected.bind(definition.content_id))
	HUD_SKIN.apply_card(button, false)
	button.custom_minimum_size = Vector2(172, 72)
	button.size = Vector2(172, 72)
	button.focus_entered.connect(_show_weapon.bind(definition))
	button.mouse_entered.connect(_show_weapon.bind(definition))
	var icon := _add_icon(button, "Icon", Rect2(8, 10, 60, 50), _screen.resolve_content_icon(definition))
	_screen.icon_fallback(button, "IconFallback", icon.position, icon.size, definition.display_name).visible = icon.texture == null
	var label := _screen.ui_label(button, "Name", Vector2(74, 8), Vector2(92, 54), 18)
	label.text = definition.display_name
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var quality := _screen.ui_label(button, "QualityBadge", Vector2(74, 52), Vector2(32, 18), 14)
	quality.text = QUALITY_RULES.label(1)
	quality.add_theme_color_override(&"font_color", QUALITY_RULES.color(1))
	quality.add_theme_color_override(&"font_outline_color", Color("1a1c20"))
	quality.add_theme_constant_override(&"outline_size", 2)
	quality.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_entered.connect(_update_label.bind(button))
	button.mouse_entered.connect(_update_label.bind(button))
	button.focus_exited.connect(_update_label.bind(button))
	button.mouse_exited.connect(_update_label.bind(button))
	_update_label(button)
	return button


func _update_label(button: Button) -> void:
	var highlighted := bool(button.get_meta(&"selected", false)) or button.has_focus() or button.is_hovered()
	var label := button.get_node("Name") as Label
	label.add_theme_color_override("font_color", HUD_SKIN.COLOR_TEXT_FOCUS if highlighted else HUD_SKIN.COLOR_TEXT)
	label.add_theme_constant_override("outline_size", 0 if highlighted else 1)


func _show_weapon(definition: GogoWeaponDefinition) -> void:
	var detail := _stage.get_node("SelectedWeaponDetail") as Control
	var icon := detail.get_node("Icon") as TextureRect
	icon.texture = _screen.resolve_content_icon(definition)
	(detail.get_node("IconFallback") as Control).visible = icon.texture == null
	(detail.get_node("IconFallback/Label") as Label).text = definition.display_name
	(detail.get_node("Name") as Label).text = definition.display_name
	(detail.get_node("Mode") as Label).text = "近战" if definition.mode == GogoWeaponDefinition.Mode.MELEE else "远程"
	(detail.get_node("Damage") as Label).text = "伤害  %s" % _num(definition.damage * QUALITY_RULES.factor(1))
	(detail.get_node("Cooldown") as Label).text = "冷却  %s 秒" % _num(definition.cooldown_seconds)
	(detail.get_node("Modifiers") as Label).text = "范围 %s · 击退 %s\n弹速 %s\n伤害类型 %s\n命中反馈 %s" % [
		_num(definition.attack_range), _num(definition.knockback),
		"—" if definition.mode == GogoWeaponDefinition.Mode.MELEE else _num(definition.projectile_speed),
		"近战" if definition.damage_kind == &"melee" else "弹道",
		{&"critical": "暴击", &"pierce_exit": "穿透", &"normal": "普通"}.get(definition.impact_kind, "普通")]


func _add_icon(parent: Node, node_name: String, rect: Rect2, texture: Texture2D = null) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.position = rect.position
	icon.size = rect.size
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _num(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else String.num(value, 2).trim_suffix("0")
