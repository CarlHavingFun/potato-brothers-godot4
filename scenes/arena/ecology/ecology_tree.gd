extends StaticBody2D
class_name EcologyTree

signal harvested(world_position: Vector2, pickup_kind: int)

@export var max_health := 3.0
var current_health := 3.0
var pickup_kind := 0


func _ready() -> void:
	current_health = max_health


func _on_hurtbox_damaged(hitbox: HitboxComponent) -> void:
	if hitbox == null or current_health <= 0.0:
		return
	current_health -= maxf(1.0, hitbox.damage)
	var trunk := $Trunk as Polygon2D
	trunk.modulate = Color(1.35, 1.35, 1.35, 1.0)
	var tween := create_tween()
	tween.tween_property(trunk, "modulate", Color.WHITE, 0.1)
	if current_health <= 0.0:
		harvested.emit(global_position, pickup_kind)
		queue_free()
