extends Panel
class_name CodexPanel

signal closed

const CATEGORIES := [&"characters", &"weapons", &"passives", &"enemies"]

@onready var grid: GridContainer = %EntryGrid
@onready var discovered_label: Label = %DiscoveredLabel
@onready var category_buttons: HBoxContainer = %CategoryButtons

var current_category := 0


func _ready() -> void:
	for index in category_buttons.get_child_count():
		var button := category_buttons.get_child(index) as Button
		button.pressed.connect(show_category.bind(index))
	hide()


func open_codex() -> void:
	show()
	show_category(current_category)
	var first_button := category_buttons.get_child(current_category) as Button
	first_button.grab_focus()


func close_codex() -> void:
	hide()
	closed.emit()


func category_count() -> int:
	return CATEGORIES.size()


func entry_count() -> int:
	return grid.get_child_count()


func show_category(index: int) -> void:
	current_category = clampi(index, 0, CATEGORIES.size() - 1)
	_clear_grid()
	var definitions := _definitions_for_category(current_category)
	var discovered_count := 0
	for definition: ContentDef in definitions:
		var stable_id := definition.get_stable_id(Content.catalog.pack_id)
		var discovered := Global.meta_progress.is_discovered(stable_id)
		if discovered:
			discovered_count += 1
		grid.add_child(_make_entry(definition, discovered))
	discovered_label.text = "已发现 %d / %d" % [discovered_count, definitions.size()]
	for button_index in category_buttons.get_child_count():
		var button := category_buttons.get_child(button_index) as Button
		button.set_pressed_no_signal(button_index == current_category)


func _definitions_for_category(index: int) -> Array:
	match index:
		0: return Content.catalog.get_characters()
		1: return Content.catalog.get_weapons()
		2: return Content.catalog.get_passives()
		_: return Content.catalog.get_enemies()


func _make_entry(definition: ContentDef, discovered: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(250, 210)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.13, 0.96) if discovered else Color(0.045, 0.05, 0.06, 0.95)
	style.border_color = Color(0.24, 0.72, 0.66, 0.75) if discovered else Color(0.22, 0.24, 0.25, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	card.add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if discovered else Color(0.08, 0.09, 0.1, 1.0)
	icon.texture = _definition_icon(definition)
	column.add_child(icon)
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 24)
	name_label.text = _definition_name(definition) if discovered else "？？？"
	column.add_child(name_label)
	var tag_label := Label.new()
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_color_override(&"font_color", Color(0.55, 0.78, 0.74))
	tag_label.text = " · ".join(Array(definition.tags).map(func(tag: StringName): return String(tag))) if discovered else "尚未发现"
	column.add_child(tag_label)
	return card


func _definition_icon(definition: ContentDef) -> Texture2D:
	var category := &"pickup"
	if definition is CharacterDef:
		category = &"character"
	elif definition is WeaponDef:
		category = &"weapon"
	elif definition is EnemyDef:
		category = &"enemy"
	return Presentation.resolve_texture(
		category,
		definition.get_presentation_id(Content.catalog.pack_id),
		definition.icon
	)


func _definition_name(definition: ContentDef) -> String:
	if definition is CharacterDef:
		return Content.catalog.get_character_display_name(definition as CharacterDef)
	if definition is WeaponDef:
		return Content.catalog.get_item_display_name((definition as WeaponDef).tiers[0])
	if definition is PassiveItemDef:
		return Content.catalog.get_item_display_name((definition as PassiveItemDef).item)
	return Global.translate_text(definition.display_name_key, String(definition.content_id).get_file().capitalize())


func _clear_grid() -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close_codex()
		get_viewport().set_input_as_handled()
