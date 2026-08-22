class_name GogoPetActor
extends Node2D

var owner_actor: GogoPlayerActor
var follow_distance := 44.0
var follow_speed := 5.0


func configure(owner: GogoPlayerActor) -> void:
	owner_actor = owner


func _process(delta: float) -> void:
	if not is_instance_valid(owner_actor):
		return
	var offset := global_position - owner_actor.global_position
	var target := owner_actor.global_position - offset.normalized() * follow_distance if offset.length() > 0.1 else owner_actor.global_position
	global_position = global_position.lerp(target, clampf(follow_speed * delta, 0.0, 1.0))


func _draw() -> void:
	draw_circle(Vector2.ZERO, 7.0, Color("f1c75b"))
