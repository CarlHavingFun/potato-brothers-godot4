class_name ArenaBoundsController
extends StaticBody2D


const DEFAULT_ARENA_BOUNDS := preload("res://core/world/default_arena_bounds.tres")

@export var arena_bounds: ArenaBoundsDef = DEFAULT_ARENA_BOUNDS
@export_range(1.0, 512.0, 1.0) var wall_thickness := 100.0


func _ready() -> void:
	apply_bounds()


func apply_bounds() -> void:
	if arena_bounds == null:
		return
	var bounds := arena_bounds.playable_rect
	_configure_wall(
		get_node_or_null("Top") as CollisionShape2D,
		Vector2(bounds.get_center().x, bounds.position.y - wall_thickness * 0.5),
		Vector2(bounds.size.x + wall_thickness * 2.0, wall_thickness)
	)
	_configure_wall(
		get_node_or_null("Bottom") as CollisionShape2D,
		Vector2(bounds.get_center().x, bounds.end.y + wall_thickness * 0.5),
		Vector2(bounds.size.x + wall_thickness * 2.0, wall_thickness)
	)
	_configure_wall(
		get_node_or_null("Left") as CollisionShape2D,
		Vector2(bounds.position.x - wall_thickness * 0.5, bounds.get_center().y),
		Vector2(wall_thickness, bounds.size.y + wall_thickness * 2.0)
	)
	_configure_wall(
		get_node_or_null("Right") as CollisionShape2D,
		Vector2(bounds.end.x + wall_thickness * 0.5, bounds.get_center().y),
		Vector2(wall_thickness, bounds.size.y + wall_thickness * 2.0)
	)


func _configure_wall(node: CollisionShape2D, wall_position: Vector2, size: Vector2) -> void:
	if node == null:
		return
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	node.position = wall_position
	node.shape = rectangle
