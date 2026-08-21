class_name VideoSpritePreview
extends Node2D


@export var clip_id := ""
@export var root_anchor := Vector2(128.0, 232.0)
@export var preview_origin := Vector2(576.0, 324.0)

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var info: Label = $HUD/Info


func _ready() -> void:
	if sprite.sprite_frames == null or sprite.sprite_frames.get_animation_names().is_empty():
		push_error("Video sprite preview has no selection animations")
		return
	var animation := sprite.sprite_frames.get_animation_names()[0]
	sprite.animation = animation
	sprite.position = preview_origin - root_anchor
	sprite.play()
	queue_redraw()


func _process(_delta: float) -> void:
	if sprite.sprite_frames == null or info == null:
		return
	var animation := sprite.animation
	var count := sprite.sprite_frames.get_frame_count(animation)
	var fps := sprite.sprite_frames.get_animation_speed(animation)
	info.text = "%s  |  %s  |  frame %d/%d  |  %.3g FPS" % [
		clip_id, String(animation), mini(sprite.frame + 1, count), count, fps
	]


func _draw() -> void:
	_draw_checkerboard()
	_draw_root_guide()


func _draw_checkerboard() -> void:
	var tile := 32.0
	var size := get_viewport_rect().size
	for y in ceili(size.y / tile):
		for x in ceili(size.x / tile):
			var colour := Color("#e8ebef") if (x + y) % 2 == 0 else Color("#d8dde3")
			draw_rect(Rect2(Vector2(x, y) * tile, Vector2.ONE * tile), colour)


func _draw_root_guide() -> void:
	draw_line(
		Vector2(0.0, preview_origin.y),
		Vector2(get_viewport_rect().size.x, preview_origin.y),
		Color("#dd5268"),
		1.0
	)
	draw_line(preview_origin - Vector2(8.0, 0.0), preview_origin + Vector2(8.0, 0.0), Color.RED, 2.0)
	draw_line(preview_origin - Vector2(0.0, 8.0), preview_origin + Vector2(0.0, 8.0), Color.RED, 2.0)
