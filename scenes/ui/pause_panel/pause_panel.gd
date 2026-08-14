extends Panel
class_name PausePanel

signal resume_requested
signal settings_requested
signal title_requested


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_title_button_pressed() -> void:
	title_requested.emit()
