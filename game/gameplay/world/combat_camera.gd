class_name GogoCombatCamera
extends Camera2D

var target: Node2D
var world_bounds := Rect2()


func configure(next_target: Node2D, next_world_bounds: Rect2) -> void:
	target = next_target
	world_bounds = next_world_bounds
	enabled = true
	_snap_to_target()


func _process(_delta: float) -> void:
	_snap_to_target()


func _snap_to_target() -> void:
	if target == null or world_bounds.size.x <= 0.0 or world_bounds.size.y <= 0.0:
		return
	global_position = _clamp_center(target.global_position)


func _clamp_center(desired: Vector2) -> Vector2:
	var visible_size := get_viewport_rect().size / zoom
	var half_size := visible_size * 0.5
	return Vector2(
		_axis_center(desired.x, world_bounds.position.x, world_bounds.end.x, half_size.x),
		_axis_center(desired.y, world_bounds.position.y, world_bounds.end.y, half_size.y)
	)


func _axis_center(desired: float, minimum: float, maximum: float, half_visible: float) -> float:
	if maximum - minimum <= half_visible * 2.0:
		return (minimum + maximum) * 0.5
	return clampf(desired, minimum + half_visible, maximum - half_visible)
