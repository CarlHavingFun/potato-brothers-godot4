class_name CharacterSpriteCurationItemList
extends ItemList


var drag_owner: Control


func _get_drag_data(at_position: Vector2) -> Variant:
	return drag_owner._get_drag_data(at_position) if is_instance_valid(drag_owner) else null


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return bool(drag_owner._can_drop_data(at_position, data)) if is_instance_valid(drag_owner) else false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if is_instance_valid(drag_owner):
		drag_owner._drop_data(at_position, data)
