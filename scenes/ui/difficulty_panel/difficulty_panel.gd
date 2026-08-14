extends Panel
class_name DifficultyPanel

signal difficulty_selected(level: int)

@onready var buttons_container: VBoxContainer = %ButtonsContainer


func load_difficulties(highest_unlocked: int = 1) -> void:
	for child: Node in buttons_container.get_children():
		child.queue_free()
	for definition: DifficultyDef in Content.catalog.get_difficulties():
		var button := Button.new()
		button.custom_minimum_size = Vector2(560, 64)
		button.add_theme_font_size_override("font_size", 28)
		button.text = tr("ui.difficulty.option") % [
			definition.level, definition.health_multiplier, definition.damage_multiplier
		]
		button.disabled = definition.level > highest_unlocked
		button.pressed.connect(_select.bind(definition.level))
		buttons_container.add_child(button)


func _select(level: int) -> void:
	difficulty_selected.emit(level)
	hide()
