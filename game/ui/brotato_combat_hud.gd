class_name GogoBrotatoCombatHud
extends Control


const REFERENCE_SIZE := Vector2(320, 180)
const WEAPON_CAPACITY := 6
const ITEM_CAPACITY := 8

var content_snapshot: ContentSnapshot
var static_asset_snapshot: GogoStaticAssetSnapshot
var current_snapshot: GogoCombatHudSnapshot
var control_hint_dismissed := false

var timer_label: Label
var wave_label: Label
var health_bar: ProgressBar
var health_label: Label
var experience_bar: ProgressBar
var level_label: Label
var materials_label: Label
var weapon_strip: HBoxContainer
var item_strip: GridContainer
var control_hint: PanelContainer
var shell: TextureRect
var global_icons: Dictionary = {}


func _init() -> void:
	name = "BrotatoHUD"
	custom_minimum_size = REFERENCE_SIZE
	size = REFERENCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hierarchy()


func configure(
	snapshot: GogoCombatHudSnapshot,
	content: ContentSnapshot,
	static_assets: GogoStaticAssetSnapshot = null
) -> void:
	content_snapshot = content
	static_asset_snapshot = static_assets
	_apply_static_textures()
	if snapshot != null:
		apply_snapshot(snapshot)


func apply_snapshot(snapshot: GogoCombatHudSnapshot) -> void:
	if snapshot == null:
		return
	current_snapshot = snapshot
	timer_label.text = "%02d" % ceili(snapshot.seconds)
	wave_label.text = "第 %d 波" % snapshot.wave
	health_bar.max_value = maxf(snapshot.maximum_health, 1.0)
	health_bar.value = clampf(snapshot.health, 0.0, health_bar.max_value)
	health_label.text = "%d / %d" % [roundi(snapshot.health), roundi(snapshot.maximum_health)]
	experience_bar.max_value = maxi(snapshot.next_level_requirement, 1)
	experience_bar.value = clampi(snapshot.experience, 0, snapshot.next_level_requirement)
	level_label.text = "LV.%d" % snapshot.level
	materials_label.text = "$ %d" % snapshot.materials
	_refresh_equipment_strip(weapon_strip, snapshot.weapon_ids, &"weapon", WEAPON_CAPACITY)
	_refresh_equipment_strip(item_strip, snapshot.item_ids, &"item", ITEM_CAPACITY)
	if snapshot.wave == 1 and snapshot.wave_elapsed >= 4.0:
		_dismiss_control_hint()
	control_hint.visible = not control_hint_dismissed


func note_movement(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		_dismiss_control_hint()


func _dismiss_control_hint() -> void:
	control_hint_dismissed = true
	if control_hint != null:
		control_hint.visible = false


func _build_hierarchy() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color("14181b")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	shell = TextureRect.new()
	shell.name = "Shell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shell.stretch_mode = TextureRect.STRETCH_SCALE
	shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)

	var top_center := Control.new()
	top_center.name = "TopCenter"
	top_center.position = Vector2(112, 3)
	top_center.size = Vector2(96, 29)
	add_child(top_center)
	wave_label = _label("Wave", 7, HORIZONTAL_ALIGNMENT_CENTER)
	wave_label.position = Vector2(0, 0)
	wave_label.size = Vector2(96, 10)
	top_center.add_child(wave_label)
	var wave_icon := _texture_rect("WaveIcon", Vector2(8, 1), Vector2(8, 8))
	top_center.add_child(wave_icon)
	global_icons["hud_icon_kit|wave"] = wave_icon
	timer_label = _label("Timer", 14, HORIZONTAL_ALIGNMENT_CENTER)
	timer_label.position = Vector2(0, 8)
	timer_label.size = Vector2(96, 20)
	top_center.add_child(timer_label)
	var timer_icon := _texture_rect("TimerIcon", Vector2(12, 13), Vector2(9, 9))
	top_center.add_child(timer_icon)
	global_icons["hud_icon_kit|wave_timer"] = timer_icon

	var bottom_left := Control.new()
	bottom_left.name = "BottomLeft"
	bottom_left.position = Vector2(7, 146)
	bottom_left.size = Vector2(92, 29)
	add_child(bottom_left)
	health_bar = _progress_bar("HealthBar", Color("df3849"))
	health_bar.position = Vector2(11, 12)
	health_bar.size = Vector2(81, 13)
	bottom_left.add_child(health_bar)
	health_label = _label("Health", 7, HORIZONTAL_ALIGNMENT_LEFT)
	health_label.position = Vector2(2, 11)
	health_label.size = Vector2(88, 14)
	bottom_left.add_child(health_label)
	var health_caption := _label("HealthCaption", 6, HORIZONTAL_ALIGNMENT_LEFT)
	health_caption.text = "生命"
	health_caption.position = Vector2(1, 0)
	health_caption.size = Vector2(90, 10)
	bottom_left.add_child(health_caption)
	var health_icon := _texture_rect("HealthIcon", Vector2(0, 13), Vector2(10, 10))
	bottom_left.add_child(health_icon)
	global_icons["hud_icon_kit|health"] = health_icon

	var bottom_center := Control.new()
	bottom_center.name = "BottomCenter"
	bottom_center.position = Vector2(105, 146)
	bottom_center.size = Vector2(105, 29)
	add_child(bottom_center)
	experience_bar = _progress_bar("ExperienceBar", Color("5aa9df"))
	experience_bar.position = Vector2(0, 12)
	experience_bar.size = Vector2(105, 9)
	bottom_center.add_child(experience_bar)
	level_label = _label("Level", 7, HORIZONTAL_ALIGNMENT_CENTER)
	level_label.position = Vector2(0, 0)
	level_label.size = Vector2(105, 11)
	bottom_center.add_child(level_label)

	var bottom_right := Control.new()
	bottom_right.name = "BottomRight"
	bottom_right.position = Vector2(228, 148)
	bottom_right.size = Vector2(82, 24)
	add_child(bottom_right)
	materials_label = _label("Materials", 10, HORIZONTAL_ALIGNMENT_RIGHT)
	materials_label.position = Vector2(0, 0)
	materials_label.size = bottom_right.size
	materials_label.add_theme_color_override("font_color", Color("f3c742"))
	bottom_right.add_child(materials_label)

	weapon_strip = HBoxContainer.new()
	weapon_strip.name = "WeaponStrip"
	weapon_strip.position = Vector2(94, 121)
	weapon_strip.size = Vector2(132, 22)
	weapon_strip.add_theme_constant_override("separation", 2)
	add_child(weapon_strip)
	for index in WEAPON_CAPACITY:
		weapon_strip.add_child(_equipment_cell("WeaponCell%02d" % index, Vector2(20, 20)))

	item_strip = GridContainer.new()
	item_strip.name = "ItemStrip"
	item_strip.columns = 2
	item_strip.position = Vector2(282, 76)
	item_strip.size = Vector2(34, 68)
	item_strip.add_theme_constant_override("h_separation", 2)
	item_strip.add_theme_constant_override("v_separation", 1)
	add_child(item_strip)
	for index in ITEM_CAPACITY:
		item_strip.add_child(_equipment_cell("ItemCell%02d" % index, Vector2(16, 16)))

	control_hint = PanelContainer.new()
	control_hint.name = "ControlHint"
	control_hint.position = Vector2(93, 35)
	control_hint.size = Vector2(134, 15)
	control_hint.add_theme_stylebox_override("panel", _flat_style(Color(0.04, 0.05, 0.05, 0.88), Color("6c725e"), 1))
	add_child(control_hint)
	var hint_label := _label("HintText", 6, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.text = "WASD / 左摇杆移动 · 武器自动开火"
	var hint_content := HBoxContainer.new()
	hint_content.name = "HintContent"
	hint_content.add_theme_constant_override("separation", 2)
	control_hint.add_child(hint_content)
	for spec in [
		["MoveKeyboardIcon", "move_keyboard_wasd"],
		["MoveGamepadIcon", "move_gamepad_left_stick"],
		["AutoAttackIcon", "auto_attack"],
	]:
		var hint_icon := _texture_rect(spec[0], Vector2.ZERO, Vector2(9, 9))
		hint_icon.custom_minimum_size = Vector2(9, 9)
		hint_content.add_child(hint_icon)
		global_icons["control_icon_kit|%s" % spec[1]] = hint_icon
	hint_label.custom_minimum_size = Vector2(101, 11)
	hint_content.add_child(hint_label)

	_apply_static_textures()


func _equipment_cell(node_name: String, cell_size: Vector2) -> Control:
	var cell := Control.new()
	cell.name = node_name
	cell.custom_minimum_size = cell_size
	cell.size = cell_size
	var background := Panel.new()
	background.name = "Card"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override(
		"panel",
		_flat_style(Color("242a2d"), Color("5d645b"), 1)
	)
	cell.add_child(background)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var fallback := _label("Fallback", 6, HORIZONTAL_ALIGNMENT_CENTER)
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(fallback)
	return cell


func _refresh_equipment_strip(
	strip: Container,
	ids: Array[StringName],
	kind: StringName,
	capacity: int
) -> void:
	for index in capacity:
		var cell := strip.get_child(index) as Control
		var icon := cell.get_node("Icon") as TextureRect
		var fallback := cell.get_node("Fallback") as Label
		icon.texture = null
		icon.visible = false
		fallback.text = ""
		cell.tooltip_text = ""
		if index >= ids.size():
			continue
		var content_id := ids[index]
		var definition := (
			content_snapshot.definition(content_id, kind)
			if content_snapshot != null
			else null
		) as GogoContentDefinition
		var texture := _resolve_content_texture(definition, kind, content_id)
		icon.texture = texture
		icon.visible = texture != null
		fallback.text = "" if texture != null else str(index + 1)
		cell.tooltip_text = definition.display_name if definition != null else String(content_id)


func _resolve_content_texture(
	definition: GogoContentDefinition,
	kind: StringName,
	content_id: StringName
) -> Texture2D:
	if static_asset_snapshot == null:
		return null
	var handle := static_asset_snapshot.resolve_content(kind, content_id, &"icon")
	if handle == null and definition != null and not definition.icon_asset_id.is_empty():
		handle = static_asset_snapshot.resolve_asset(definition.icon_asset_id, &"icon")
	return handle.texture if handle != null else null


func _apply_static_textures() -> void:
	if shell == null:
		return
	var handle: GogoStaticAssetHandle
	if static_asset_snapshot != null:
		handle = static_asset_snapshot.resolve_global(&"combat_hud_shell")
	shell.texture = handle.texture if handle != null else null
	for key: String in global_icons:
		var parts := key.split("|", false)
		var icon_handle: GogoStaticAssetHandle
		if static_asset_snapshot != null:
			icon_handle = static_asset_snapshot.resolve_global(
				StringName(parts[0]),
				StringName(parts[1])
			)
		(global_icons[key] as TextureRect).texture = (
			icon_handle.texture if icon_handle != null else null
		)


func _texture_rect(node_name: String, at: Vector2, rect_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.position = at
	icon.size = rect_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _label(node_name: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = node_name
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f4ecd0"))
	label.add_theme_color_override("font_outline_color", Color("161719"))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _progress_bar(node_name: String, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _flat_style(Color("171a1c"), Color("08090a"), 1))
	bar.add_theme_stylebox_override("fill", _flat_style(fill_color, Color("08090a"), 1))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


static func _flat_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(1)
	style.anti_aliasing = false
	return style
