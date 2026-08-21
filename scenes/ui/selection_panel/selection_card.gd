extends Button
class_name SelectionCard


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_icon(texture: Texture2D) -> void:
	icon = texture


func _on_pressed() -> void:
	GameplayCues.emit_cue(&"ui.confirm")


func _on_mouse_entered() -> void:
	GameplayCues.emit_cue(&"ui.hover")


func _on_toggled(is_selected: bool) -> void:
	var indicator := get_node_or_null("SelectedIndicator") as Control
	if indicator != null:
		indicator.visible = is_selected
