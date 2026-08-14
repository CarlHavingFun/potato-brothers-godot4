extends Panel
class_name TitlePanel

signal start_requested
signal settings_requested


func _on_start_button_pressed() -> void:
	start_requested.emit()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
