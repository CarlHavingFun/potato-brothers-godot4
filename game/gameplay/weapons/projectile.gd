class_name GogoProjectile
extends Node2D

var direction := Vector2.RIGHT
var speed := 500.0
var damage := 1.0
var knockback := 0.0
var lifetime := 1.5


func _ready() -> void:
	queue_redraw()


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	for enemy in get_tree().get_nodes_in_group(&"gogo_enemy"):
		if is_instance_valid(enemy) and global_position.distance_squared_to(enemy.global_position) <= 196.0:
			enemy.take_damage(damage, direction * knockback)
			queue_free()
			return


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color("f5d76e"))
	draw_circle(Vector2.ZERO, 2.0, Color.WHITE)
