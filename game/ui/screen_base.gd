class_name GogoScreenBase
extends Control

const STATIC_CARD_PRESENTER := preload("res://game/ui/static_card_presenter.gd")
const HUD_SKIN := preload("res://game/ui/hud_skin.gd")
const NATIVE_SIZE := Vector2(1280, 720)
const TITLE_BAND_RECT := Rect2(32, 20, 1216, 64)
const CONTENT_RECT := Rect2(32, 100, 1216, 588)

static var _stable_ui_theme: Theme

var body: VBoxContainer
var content_root: Control
var static_asset_snapshot_override: GogoStaticAssetSnapshot
var _selection_back_route: StringName = &""
var use_menu_background_v2 := false


func ui_label(parent: Node, node_name: String, at: Vector2, extent: Vector2, font_size: int = 22) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = extent
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", HUD_SKIN.COLOR_TEXT)
	label.add_theme_color_override(&"font_outline_color", Color("111416"))
	label.add_theme_constant_override(&"outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func ui_panel(parent: Node, node_name: String, rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	HUD_SKIN.apply_panel(panel, &"surface")
	parent.add_child(panel)
	return panel


func ui_button(parent: Node, node_name: String, text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	configure_action_button(button, text, callback)
	HUD_SKIN.apply_action_button(button, &"primary", false, true)
	button.custom_minimum_size = rect.size
	button.position = rect.position
	button.size = rect.size
	parent.add_child(button)
	return button


func link_focus_cycle(controls: Array[Control]) -> void:
	for index in controls.size():
		var current := controls[index]
		var previous := controls[posmod(index - 1, controls.size())]
		var next := controls[(index + 1) % controls.size()]
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)


func selection_back(route_id: StringName) -> Button:
	_selection_back_route = route_id
	var button := ui_button(self, "BackButton", "← 返回", Rect2(32, 24, 168, 56),
		func() -> void: AppContext.kernel(self).route(route_id))
	button.z_index = 10
	return button


func _unhandled_key_input(event: InputEvent) -> void:
	if not _selection_back_route.is_empty() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		AppContext.kernel(self).route(_selection_back_route)


func selection_title() -> void:
	for node_name in ["Title", "Subtitle"]:
		var label := get_node("TitleBand/%s" % node_name) as Label
		label.size.x = TITLE_BAND_RECT.size.x - label.position.x
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func character_frame(character: CharacterDefinition) -> Texture2D:
	if character == null or character.sprite_frames == null or not character.sprite_frames.has_animation(character.default_animation):
		return null
	if character.sprite_frames.get_frame_count(character.default_animation) == 0:
		return null
	return character.sprite_frames.get_frame_texture(character.default_animation, 0)


func selection_character(app: AppKernel) -> CharacterDefinition:
	var id := app.selection_draft.get("character_id", NikoContentFactory.CHARACTER_ID) as StringName
	var character := app.content_snapshot.definition(id, &"character") as CharacterDefinition
	if character == null:
		character = app.content_snapshot.definition(NikoContentFactory.CHARACTER_ID, &"character") as CharacterDefinition
	return character


func icon_fallback(parent: Node, node_name: String, at: Vector2, extent: Vector2, text: String) -> Control:
	var fallback := ColorRect.new()
	fallback.name = node_name
	fallback.position = at
	fallback.size = extent
	fallback.color = Color(0.12, 0.13, 0.15, 0.94)
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fallback)
	var label := ui_label(fallback, "Label", Vector2(4, 4), extent - Vector2(8, 8), 14)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return fallback


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


func add_principal_surface(
	rect: Rect2,
	_consumer_scene_path := "res://game/ui/screen_base.gd",
	_consumer_node_path := "PrincipalSurface"
) -> Control:
	if content_root == null:
		build_screen_chrome("", "")
	var surface := Panel.new()
	HUD_SKIN.apply_panel(surface, &"surface")
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
	background.color = HUD_SKIN.COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var static_background := TextureRect.new()
	static_background.name = "StaticMenuBackground"
	static_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	static_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	static_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	static_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_background.texture = load("res://game/assets/ui/hud_v2/menu_background_v2.png") as Texture2D if use_menu_background_v2 else _global_texture(&"menu_background")
	add_child(static_background)
	var veil := ColorRect.new()
	veil.name = "ReadabilityVeil"
	veil.color = Color(0.0, 0.0, 0.0, 0.16 if use_menu_background_v2 else 0.42)
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
	button.custom_minimum_size.y = 52.0
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.disabled = disabled
	button.icon = icon
	button.expand_icon = icon != null
	button.add_theme_constant_override(&"icon_max_width", 64)
	HUD_SKIN.apply_action_button(button)
	if callback.is_valid() and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)
	return button


func resolve_content_icon(definition: GogoContentDefinition) -> Texture2D:
	if definition == null:
		return null
	if definition.direct_icon_texture != null:
		return definition.direct_icon_texture
	if definition.icon_asset_id.is_empty():
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
	return _global_texture(asset_id, selector)


func resolve_global_handle(
	asset_id: StringName,
	selector: StringName = &""
) -> GogoStaticAssetHandle:
	if asset_id.is_empty():
		return null
	var snapshot := _static_asset_snapshot()
	if snapshot == null:
		return null
	return snapshot.resolve_global(asset_id, selector)


func _global_texture(asset_id: StringName, selector: StringName = &"") -> Texture2D:
	var handle := resolve_global_handle(asset_id, selector)
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/ui/screen_base.gd",
		"Global/%s/%s" % [asset_id, selector]
	)
	return handle.texture if handle != null else null


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
	# Empty compatibility copy should not reserve a full text row in compact
	# native layouts now that action buttons use their authored 52 px height.
	label.visible = not text.is_empty()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	return label


static func _shared_stable_ui_theme() -> Theme:
	if _stable_ui_theme != null:
		return _stable_ui_theme
	var result := Theme.new()
	var normal := _button_style(Color(0.0, 0.0, 0.0, 0.78), Color(0.03, 0.03, 0.03, 0.96))
	var hover := _button_style(Color(0.96, 0.95, 0.93, 0.90), Color(0.12, 0.12, 0.12, 0.98))
	var pressed := _button_style(Color(0.68, 0.68, 0.66, 0.92), Color(0.10, 0.10, 0.10, 1.0))
	result.set_color(&"font_color", &"Button", HUD_SKIN.COLOR_TEXT)
	result.set_color(&"font_disabled_color", &"Button", Color(HUD_SKIN.COLOR_TEXT, 0.20))
	result.set_color(&"font_hover_color", &"Button", HUD_SKIN.COLOR_TEXT_FOCUS)
	result.set_color(&"font_focus_color", &"Button", HUD_SKIN.COLOR_TEXT_FOCUS)
	result.set_font_size(&"font_size", &"Button", 22)
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
	style.set_corner_radius_all(12)
	style.anti_aliasing = false
	style.border_blend = false
	style.corner_detail = 1
	style.content_margin_left = 24.0
	style.content_margin_top = 14.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 14.0
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
