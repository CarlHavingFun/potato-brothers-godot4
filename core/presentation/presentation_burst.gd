class_name PresentationBurst
extends Node2D


@export var color := Color.WHITE
@export_range(3, 32, 1) var ray_count := 10
@export_range(1.0, 64.0, 1.0) var radius := 18.0
@export_range(0.05, 2.0, 0.01) var lifetime := 0.22

var elapsed := 0.0


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	modulate.a = 1.0 - progress
	scale = Vector2.ONE * (0.65 + progress * 0.85)
	if progress >= 1.0:
		queue_free()


func _draw() -> void:
	for index: int in ray_count:
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / float(ray_count))
		draw_line(direction * radius * 0.35, direction * radius, color, 3.0, true)
		draw_circle(direction * radius, 2.5, color)
