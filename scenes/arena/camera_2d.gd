extends Camera2D
class_name Camera

@export var trauma_decay := 1.6
@export var max_offset := Vector2(18.0, 12.0)

var trauma := 0.0
var noise := FastNoiseLite.new()
var noise_time := 0.0


func _ready() -> void:
	add_to_group(&"presentation_camera")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.08


func _process(delta: float) -> void:
	if is_instance_valid(Global.player):
		global_position = Global.player.global_position
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	if is_zero_approx(trauma):
		offset = Vector2.ZERO
		return
	noise_time += delta * 60.0
	var strength := trauma * trauma
	offset = Vector2(
		noise.get_noise_1d(noise_time) * max_offset.x,
		noise.get_noise_1d(noise_time + 1000.0) * max_offset.y
	) * strength


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + maxf(0.0, amount), 0.0, 1.0)
