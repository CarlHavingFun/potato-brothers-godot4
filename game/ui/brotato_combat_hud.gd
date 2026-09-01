class_name GogoBrotatoCombatHud
extends Control


const VIEWPORT_SIZE := Vector2(1280, 720)
const DEFAULT_TEXT_COLOR := Color("f4ecd0")
const DANGER_TEXT_COLOR := Color("ff5c5c")
const METRIC_BACKING_COLOR := Color.TRANSPARENT
const SHELL_ALPHA := 0.0
const CONTROL_HINT_AUTO_DISMISS_SECONDS := 2.5
const TOP_LEFT_POSITION := Vector2(16, 14)
const TOP_LEFT_SIZE := Vector2(248, 90)
const TOP_CENTER_POSITION := Vector2(528, 8)
const TOP_CENTER_SIZE := Vector2(224, 64)
const CONTROL_HINT_POSITION := Vector2(16, 108)
const CONTROL_HINT_SIZE := Vector2(276, 30)

var content_snapshot: ContentSnapshot
var static_asset_snapshot: GogoStaticAssetSnapshot
var current_snapshot: GogoCombatHudSnapshot
var control_hint_dismissed := false

var timer_label: Label
var wave_label: Label
var health_bar: ProgressBar
var health_label: Label
var experience_bar: ProgressBar
var experience_label: Label
var level_label: Label
var materials_label: Label
var wave_materials_label: Label
var material_icon: TextureRect
var control_hint: PanelContainer
var shell: TextureRect
var metric_panels: Array[Panel] = []
var global_icons: Dictionary = {}


func _init() -> void:
	name = "BrotatoHUD"
	custom_minimum_size = VIEWPORT_SIZE
	size = VIEWPORT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hierarchy()


func _ready() -> void:
	_observe_shell_disabled()


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
	timer_label.add_theme_color_override(
		"font_color",
		DANGER_TEXT_COLOR if snapshot.seconds <= 10.0 else DEFAULT_TEXT_COLOR
	)
	wave_label.text = ("无尽 · 第 %d 波" if snapshot.endless else "第 %d 波") % snapshot.wave
	health_bar.max_value = maxf(snapshot.maximum_health, 1.0)
	health_bar.value = clampf(snapshot.health, 0.0, health_bar.max_value)
	health_label.text = "%d / %d" % [roundi(snapshot.health), roundi(snapshot.maximum_health)]
	experience_bar.max_value = maxi(snapshot.next_level_requirement, 1)
	experience_bar.value = clampi(snapshot.experience, 0, snapshot.next_level_requirement)
	experience_label.text = "%d / %d" % [snapshot.experience, snapshot.next_level_requirement]
	level_label.text = "LV.%d" % snapshot.level
	materials_label.text = "%d" % snapshot.materials
	wave_materials_label.text = "+%d" % snapshot.wave_materials
	if (
		snapshot.wave > 1
		or (
			snapshot.wave == 1
			and snapshot.wave_elapsed >= CONTROL_HINT_AUTO_DISMISS_SECONDS
		)
	):
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
	shell = TextureRect.new()
	shell.name = "Shell"
	shell.size = VIEWPORT_SIZE
	shell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shell.stretch_mode = TextureRect.STRETCH_SCALE
	shell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.modulate.a = SHELL_ALPHA
	shell.visible = false
	add_child(shell)

	var top_left := Control.new()
	top_left.name = "TopLeft"
	top_left.position = TOP_LEFT_POSITION
	top_left.size = TOP_LEFT_SIZE
	add_child(top_left)

	var health_metric := _metric_panel("Health", Vector2.ZERO, Vector2(248, 34))
	top_left.add_child(health_metric)
	var health_icon := _texture_rect("HealthIcon", Vector2(0, 2), Vector2(16, 16))
	health_metric.add_child(health_icon)
	global_icons["hud_icon_kit|health"] = health_icon
	health_label = _metric_label("Value", 15, HORIZONTAL_ALIGNMENT_LEFT)
	health_label.position = Vector2(20, 0)
	health_label.size = Vector2(112, 22)
	health_metric.add_child(health_label)
	health_bar = _progress_bar("HealthBar", Color("df3849"))
	health_bar.position = Vector2(20, 25)
	health_bar.size = Vector2(228, 7)
	health_metric.add_child(health_bar)

	var experience_metric := _metric_panel("Experience", Vector2(0, 36), Vector2(248, 26))
	top_left.add_child(experience_metric)
	experience_bar = _progress_bar("ExperienceBar", Color("64c957"))
	experience_bar.position = Vector2(0, 2)
	experience_bar.size = Vector2(248, 20)
	experience_metric.add_child(experience_bar)
	level_label = _metric_label("Level", 14, HORIZONTAL_ALIGNMENT_LEFT)
	level_label.position = Vector2(5, 0)
	level_label.size = Vector2(72, 20)
	experience_bar.add_child(level_label)
	experience_label = _metric_label("Value", 12, HORIZONTAL_ALIGNMENT_RIGHT)
	experience_label.position = Vector2(156, 0)
	experience_label.size = Vector2(86, 20)
	experience_bar.add_child(experience_label)

	var material_metric := _metric_panel("Materials", Vector2(0, 64), Vector2(120, 26))
	top_left.add_child(material_metric)
	material_icon = _texture_rect("MaterialIcon", Vector2(0, 1), Vector2(22, 22))
	material_metric.add_child(material_icon)
	materials_label = _metric_label("Value", 19, HORIZONTAL_ALIGNMENT_LEFT)
	materials_label.position = Vector2(24, 0)
	materials_label.size = Vector2(92, 26)
	materials_label.add_theme_color_override("font_color", Color("f3c742"))
	material_metric.add_child(materials_label)

	# Keep the canonical WaveMaterials node on the same transparent line.
	var wave_material_metric := Control.new()
	wave_material_metric.name = "WaveMaterials"
	wave_material_metric.position = Vector2(120, 64)
	wave_material_metric.size = Vector2(128, 26)
	wave_material_metric.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_child(wave_material_metric)
	var wave_material_title := _metric_label("Title", 13, HORIZONTAL_ALIGNMENT_RIGHT)
	wave_material_title.text = "本波"
	wave_material_title.position = Vector2(0, 0)
	wave_material_title.size = Vector2(48, 26)
	wave_material_metric.add_child(wave_material_title)
	wave_materials_label = _metric_label("Value", 17, HORIZONTAL_ALIGNMENT_RIGHT)
	wave_materials_label.position = Vector2(50, 0)
	wave_materials_label.size = Vector2(76, 26)
	wave_materials_label.add_theme_color_override("font_color", Color("f3c742"))
	wave_material_metric.add_child(wave_materials_label)

	var top_center := Control.new()
	top_center.name = "TopCenter"
	top_center.position = TOP_CENTER_POSITION
	top_center.size = TOP_CENTER_SIZE
	add_child(top_center)
	wave_label = _label("Wave", 12, HORIZONTAL_ALIGNMENT_LEFT)
	wave_label.position = Vector2(68, 0)
	wave_label.size = Vector2(108, 24)
	top_center.add_child(wave_label)
	var wave_icon := _texture_rect("WaveIcon", Vector2(48, 4), Vector2(16, 16))
	top_center.add_child(wave_icon)
	global_icons["hud_icon_kit|wave"] = wave_icon
	timer_label = _label("Timer", 26, HORIZONTAL_ALIGNMENT_LEFT)
	timer_label.position = Vector2(88, 24)
	timer_label.size = Vector2(68, 40)
	top_center.add_child(timer_label)
	var timer_icon := _texture_rect("TimerIcon", Vector2(68, 36), Vector2(16, 16))
	top_center.add_child(timer_icon)
	global_icons["hud_icon_kit|wave_timer"] = timer_icon

	control_hint = PanelContainer.new()
	control_hint.name = "ControlHint"
	control_hint.position = CONTROL_HINT_POSITION
	control_hint.size = CONTROL_HINT_SIZE
	control_hint.add_theme_stylebox_override(
		"panel",
		_flat_style(Color(0.04, 0.05, 0.05, 0.30), Color.TRANSPARENT, 0)
	)
	add_child(control_hint)
	var hint_content := HBoxContainer.new()
	hint_content.name = "HintContent"
	hint_content.add_theme_constant_override("separation", 4)
	control_hint.add_child(hint_content)
	for spec in [
		["MoveKeyboardIcon", "move_keyboard_wasd"],
		["MoveGamepadIcon", "move_gamepad_left_stick"],
		["AutoAttackIcon", "auto_attack"],
	]:
		var hint_icon := _texture_rect(spec[0], Vector2.ZERO, Vector2(16, 16))
		hint_icon.custom_minimum_size = Vector2(16, 16)
		hint_content.add_child(hint_icon)
		global_icons["control_icon_kit|%s" % spec[1]] = hint_icon
	var hint_label := _label("HintText", 12, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.text = "WASD / 摇杆 · 自动开火"
	hint_label.custom_minimum_size = Vector2(196, 26)
	hint_content.add_child(hint_label)

	_apply_static_textures()


func _metric_panel(node_name: String, at: Vector2, rect_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = at
	panel.size = rect_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(
		"panel",
		_flat_style(METRIC_BACKING_COLOR, Color.TRANSPARENT, 0)
	)
	metric_panels.append(panel)
	return panel


func _apply_static_textures() -> void:
	# Keep the canonical Shell node and binding for compatibility, but never mount
	# its full-screen texture. The lightweight HUD must not leave a ghost frame.
	shell.texture = null
	shell.visible = false
	for panel: Panel in metric_panels:
		panel.add_theme_stylebox_override(
			"panel",
			_flat_style(METRIC_BACKING_COLOR, Color.TRANSPARENT, 0)
		)
	_observe_shell_disabled()
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
		GogoStaticConsumerRegistry.observe_handle(
			icon_handle,
			"res://game/ui/brotato_combat_hud.gd",
			"BrotatoHUD/GlobalIcon/%s" % key
		)
	var material_handle: GogoStaticAssetHandle
	if static_asset_snapshot != null:
		material_handle = static_asset_snapshot.resolve_asset(
			&"experience_pickup",
			&"world_sprite"
		)
	material_icon.texture = null
	if material_handle != null and material_handle.texture != null:
		var fragment_texture := AtlasTexture.new()
		fragment_texture.atlas = material_handle.texture
		fragment_texture.region = Rect2(64, 0, 32, 64)
		material_icon.texture = fragment_texture
	GogoStaticConsumerRegistry.observe_handle(
		material_handle,
		"res://game/ui/brotato_combat_hud.gd",
		"BrotatoHUD/MaterialFragment"
	)

func _observe_shell_disabled() -> void:
	if static_asset_snapshot == null or shell == null:
		return
	var shell_handle := static_asset_snapshot.resolve_global(&"combat_hud_shell")
	GogoStaticConsumerRegistry.observe_handle(
		shell_handle,
		"res://game/ui/brotato_combat_hud.gd",
		"BrotatoHUD/Shell"
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
	label.add_theme_color_override("font_color", DEFAULT_TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color("161719"))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _metric_label(node_name: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := _label(node_name, font_size, alignment)
	label.add_theme_constant_override("outline_size", 0)
	return label


func _progress_bar(node_name: String, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.add_theme_stylebox_override(
		"background",
		_flat_style(Color(0.035, 0.04, 0.045, 0.68), Color.TRANSPARENT, 0)
	)
	bar.add_theme_stylebox_override(
		"fill",
		_flat_style(fill_color, Color.TRANSPARENT, 0)
	)
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
