class_name GogoStructureActor
extends StaticBody2D

var maximum_health := 20.0
var current_health := 20.0
var owner_player_index := 0


func configure(health: float, player_index: int) -> void:
	maximum_health = maxf(health, 1.0)
	current_health = maximum_health
	owner_player_index = player_index
	queue_redraw()


func take_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		queue_free()


func _draw() -> void:
	draw_rect(Rect2(-14.0, -14.0, 28.0, 28.0), Color("77a7c8"))
