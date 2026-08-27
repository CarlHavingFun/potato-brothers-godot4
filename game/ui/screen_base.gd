class_name GogoScreenBase
extends Control

const STATIC_CARD_PRESENTER := preload("res://game/ui/static_card_presenter.gd")
const NATIVE_SIZE := Vector2(1280, 720)
const TITLE_BAND_RECT := Rect2(32, 20, 1216, 64)
const CONTENT_RECT := Rect2(32, 100, 1216, 588)

static var _stable_ui_theme: Theme

var body: VBoxContainer
var content_root: Control
var static_asset_snapshot_override: GogoStaticAssetSnapshot


func build_screen(title: String, subtitle: String = "") -> VBoxContainer:
	var root := build_screen_chrome(title, subtitle)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return body


func build_screen_chrome(title: String, subtitle: String = "") -> Control:
	theme = _shared_stable_ui_theme()
	custom_minimum_size = NATIVE_SIZE
	size = NATIVE_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_add_screen_background()

	var title_band := Control.new()
	title_band.name = "TitleBand"
	title_band.position = TITLE_BAND_RECT.position
	title_band.size = TITLE_BAND_RECT.size
	title_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_band)

	var heading := Label.new()
	heading.name = "Title"
	heading.position = Vector2.ZERO
	heading.size = Vector2(780, 42)
	heading.text = title
	heading.add_theme_font_size_override(&"font_size", 34)
	heading.add_theme_color_override(&"font_color", Color("f3edd7"))
	heading.add_theme_color_override(&"font_outline_color", Color("111416"))
	heading.add_theme_constant_override(&"outline_size", 1)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_band.add_child(heading)

	var description := Label.new()
	description.name = "Subtitle"
	description.position = Vector2(2, 38)
	description.size = Vector2(900, 24)
	description.text = subtitle
	description.add_theme_font_size_override(&"font_size", 16)
	description.add_theme_color_override(&"font_color", Color("c9c3b1"))
	description.add_theme_color_override(&"font_outline_color", Color("111416"))
	description.add_theme_constant_override(&"outline_size", 1)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_band.add_child(description)

	content_root = Control.new()
	content_root.name = "ContentRoot"
	content_root.position = CONTENT_RECT.position
	content_root.size = CONTENT_RECT.size
	content_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content_root)
	return content_root


func add_principal_surface(rect: Rect2) -> Control:
	if content_root == null:
		build_screen_chrome("", "")
	var panel_texture := _global_texture(&"nine_slice_panel")
	var surface: Control
	if panel_texture != null:
		var nine_patch := NinePatchRect.new()
		nine_patch.texture = panel_texture
		nine_patch.patch_margin_left = 16
		nine_patch.patch_margin_top = 16
		nine_patch.patch_margin_right = 16
		nine_patch.patch_margin_bottom = 16
		nine_patch.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		nine_patch.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
		surface = nine_patch
	else:
		var fallback := PanelContainer.new()
		fallback.add_theme_stylebox_override(&"panel", _principal_surface_style())
		surface = fallback
	surface.name = "PrincipalSurface"
	surface.position = rect.position
	surface.size = rect.size
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	surface.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(surface)
	move_child(surface, content_root.get_index())
	return surface


func _add_screen_background() -> void:
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
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	style.corner_detail = 1
	style.content_margin_left = 24.0
	style.content_margin_top = 6.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 6.0
	return style


static func _principal_surface_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.075, 0.94)
	style.border_color = Color(0.25, 0.27, 0.28, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	return style
