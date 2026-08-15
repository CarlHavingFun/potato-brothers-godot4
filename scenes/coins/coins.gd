extends Area2D
class_name Coins

@export var move_speed := 1000.0
@export var collect_distance := 15.0

var value := 1
var target_screen_pos := Vector2.INF
var target_pos: Vector2
var collected := false

@onready var coin_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	var material_texture := Presentation.resolve_texture(&"pickup", &"pickup.material")
	if material_texture != null:
		var frames := SpriteFrames.new()
		frames.set_animation_speed(&"default", 10.0)
		for frame_index: int in 4:
			frames.add_frame(&"default", material_texture)
		coin_sprite.sprite_frames = frames
	shadow.texture = Presentation.resolve_texture(&"pickup", &"pickup.shadow")

func _process(delta: float) -> void:
	if collected and target_screen_pos == Vector2.INF:
		if is_instance_valid(Global.player):
			target_pos = Global.player.global_position
	
	if target_screen_pos != Vector2.INF:
		target_pos = get_canvas_transform().affine_inverse() * target_screen_pos
	
	if target_pos != Vector2.ZERO:
		global_position = global_position.move_toward(target_pos, move_speed * delta)
	
	if global_position.distance_to(target_pos) < collect_distance:
		add_coins()


func add_coins() -> void:
	Global.collect_materials(value)
	Global.dispatch_gameplay_event(GameplayEvent.Type.PICKED_UP, {"amount": value}, [&"pickup/material"])
	queue_free()


func set_collection_target(screen_pos: Vector2) -> void:
	target_screen_pos = screen_pos


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	collected = true
