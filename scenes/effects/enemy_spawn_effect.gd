extends Node2D
class_name EnemySpawnEffect

const OUTLINE_COLOR := Color(0.16, 0.015, 0.02, 1.0)
const FILL_COLOR := Color(0.94, 0.055, 0.07, 1.0)
const OUTLINE_BACKSLASH := [
	Vector2(-22, -26),
	Vector2(-26, -22),
	Vector2(22, 26),
	Vector2(26, 22),
]
const OUTLINE_SLASH := [
	Vector2(22, -26),
	Vector2(26, -22),
	Vector2(-22, 26),
	Vector2(-26, 22),
]
const FILL_BACKSLASH := [
	Vector2(-19, -23),
	Vector2(-23, -19),
	Vector2(19, 23),
	Vector2(23, 19),
]
const FILL_SLASH := [
	Vector2(19, -23),
	Vector2(23, -19),
	Vector2(-19, 23),
	Vector2(-23, 19),
]

@onready var anim_player: AnimationPlayer = $AnimationPlayer


func _draw() -> void:
	# Integer-coordinate polygons keep the warning crisp without texture filtering
	# or translucent edge pixels. The dark bars are drawn first as a hard outline.
	draw_colored_polygon(PackedVector2Array(OUTLINE_BACKSLASH), OUTLINE_COLOR)
	draw_colored_polygon(PackedVector2Array(OUTLINE_SLASH), OUTLINE_COLOR)
	draw_colored_polygon(PackedVector2Array(FILL_BACKSLASH), FILL_COLOR)
	draw_colored_polygon(PackedVector2Array(FILL_SLASH), FILL_COLOR)
