class_name GogoScreenBase
extends Control

const STATIC_CARD_PRESENTER := preload("res://game/ui/static_card_presenter.gd")

static var _stable_ui_theme: Theme

var body: VBoxContainer
var static_asset_snapshot_override: GogoStaticAssetSnapshot


func build_screen(title: String, subtitle: String = "") -> VBoxContainer:
	theme = _shared_stable_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.name = "FlatMenuFallback"
	background.color = Color("151922")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var static_background := TextureRect.new()
	static_background.name = "StaticMenuBackground"
	static_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	static_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	static_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	static_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_background.texture = _global_texture(&"menu_background")
	add_child(static_background)
	var veil := ColorRect.new()
	veil.name = "ReadabilityVeil"
	veil.color = Color(0.02, 0.025, 0.03, 0.54)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel_texture := _global_texture(&"nine_slice_panel")
	var panel: Control
	if panel_texture != null:
		var nine_patch := NinePatchRect.new()
		nine_patch.texture = panel_texture
		nine_patch.patch_margin_left = 16
		nine_patch.patch_margin_top = 16
		nine_patch.patch_margin_right = 16
		nine_patch.patch_margin_bottom = 16
		nine_patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		nine_patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
		nine_patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		panel = nine_patch
	else:
		panel = PanelContainer.new()
	panel.name = "StaticNineSlicePanel"
	panel.custom_minimum_size = Vector2(660.0, 700.0)
	center.add_child(panel)
	body = VBoxContainer.new()
	body.name = "Body"
	body.position = Vector2(28, 22)
	body.size = Vector2(604, 656)
	body.add_theme_constant_override("separation", 14)
	panel.add_child(body)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	body.add_child(heading)
	if not subtitle.is_empty():
		var description := Label.new()
		description.text = subtitle
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(description)
	return body


func add_action(
	text: String,
	callback: Callable,
	disabled: bool = false,
	icon: Texture2D = null,
	node_name: String = ""
) -> Button:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	configure_action_button(button, text, callback, disabled, icon)
	body.add_child(button)
	return button


func add_static_card(
	definition: GogoContentDefinition,
	price_text: String,
	callback: Callable,
	disabled: bool = false,
	parent: Container = null
) -> Button:
	var card := STATIC_CARD_PRESENTER.build_card(
		definition,
		price_text,
		_static_asset_snapshot()
	) as Button
	card.disabled = disabled
	if callback.is_valid() and not card.pressed.is_connected(callback):
		card.pressed.connect(callback)
	(parent if parent != null else body).add_child(card)
	return card


func add_static_texture(
	asset_id: StringName,
	node_name: String,
	minimum_size: Vector2
) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.custom_minimum_size = minimum_size
	texture_rect.texture = _global_texture(asset_id)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(texture_rect)
	return texture_rect


func configure_action_button(
	button: Button,
	text: String,
	callback: Callable = Callable(),
	disabled: bool = false,
	icon: Texture2D = null
) -> Button:
	button.text = text
	button.custom_minimum_size.y = 48.0
	button.disabled = disabled
	button.icon = icon
	button.expand_icon = icon != null
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_constant_override(&"icon_max_width", 64)
	STATIC_CARD_PRESENTER.apply_button_state_textures(
		button,
		_static_asset_snapshot(),
		"ActionButton/%s" % (button.name if not button.name.is_empty() else text)
	)
	if callback.is_valid() and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	return button


func resolve_content_icon(definition: GogoContentDefinition) -> Texture2D:
	if definition == null or definition.icon_asset_id.is_empty():
		return null
	var snapshot := _static_asset_snapshot()
	if snapshot == null:
		return null
	var handle := snapshot.resolve_content(definition.kind, definition.content_id, &"icon")
	if handle == null:
		handle = snapshot.resolve_asset(definition.icon_asset_id, &"icon")
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/ui/screen_base.gd",
		"ContentIcon/%s" % String(definition.content_id)
	)
	return handle.texture if handle != null else null


func resolve_global_icon(asset_id: StringName, selector: StringName = &"") -> Texture2D:
	if asset_id.is_empty():
		return null
	var snapshot := _static_asset_snapshot()
	if snapshot == null:
		return null
	var handle := snapshot.resolve_global(asset_id, selector)
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/ui/screen_base.gd",
		"Global/%s/%s" % [asset_id, selector]
	)
	return handle.texture if handle != null else null


func _global_texture(asset_id: StringName, selector: StringName = &"") -> Texture2D:
	return resolve_global_icon(asset_id, selector)


func _static_asset_snapshot() -> GogoStaticAssetSnapshot:
	if static_asset_snapshot_override != null:
		return static_asset_snapshot_override
	if not is_inside_tree():
		return null
	var app := AppContext.kernel(self)
	if app == null or app.static_asset_service == null:
		return null
	return app.static_asset_service.active_snapshot()


static func selector_from_content_id(content_id: StringName) -> StringName:
	var value := String(content_id)
	var separator := value.rfind("/")
	if separator < 0 or separator == value.length() - 1:
		return &""
	return StringName(value.substr(separator + 1))


func add_info(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label


static func _shared_stable_ui_theme() -> Theme:
	if _stable_ui_theme != null:
		return _stable_ui_theme
	var result := Theme.new()
	var normal := _button_style(Color(0.025, 0.025, 0.025, 0.96), Color(0.18, 0.18, 0.18, 0.96))
	var hover := _button_style(Color(0.085, 0.085, 0.085, 0.98), Color(0.46, 0.46, 0.46, 1.0))
	var pressed := _button_style(Color(0.12, 0.08, 0.035, 0.98), Color(1.0, 0.63, 0.22, 1.0))
	result.set_color(&"font_color", &"Button", Color(0.93, 0.90, 0.77, 1.0))
	result.set_color(&"font_disabled_color", &"Button", Color(0.42, 0.43, 0.38, 0.75))
	result.set_color(&"font_hover_color", &"Button", Color(1.0, 0.88, 0.48, 1.0))
	result.set_color(&"font_focus_color", &"Button", Color(1.0, 0.88, 0.48, 1.0))
	result.set_font_size(&"font_size", &"Button", 24)
	result.set_stylebox(&"normal", &"Button", normal)
	result.set_stylebox(&"hover", &"Button", hover)
	result.set_stylebox(&"focus", &"Button", hover)
	result.set_stylebox(&"pressed", &"Button", pressed)
	result.set_stylebox(&"disabled", &"Button", normal)
	_stable_ui_theme = result
	return _stable_ui_theme


static func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.25
	style.border_blend = true
	style.corner_detail = 12
	style.content_margin_left = 24.0
	style.content_margin_top = 12.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 12.0
	return style
