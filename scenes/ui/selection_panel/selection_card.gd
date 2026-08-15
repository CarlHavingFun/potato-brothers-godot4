extends Button
class_name SelectionCard


func set_icon(texture: Texture2D) -> void:
	icon = texture


func _on_pressed() -> void:
	SoundManager.play_sound(SoundManager.Sound.UI)


func _on_mouse_entered() -> void:
	SoundManager.play_sound(SoundManager.Sound.UI)


func _on_toggled(is_selected: bool) -> void:
	var indicator := get_node_or_null("SelectedIndicator") as Control
	if indicator != null:
		indicator.visible = is_selected
