extends Camera2D
class_name Camera

const DEFAULT_ARENA_BOUNDS := preload("res://core/world/default_arena_bounds.tres")

@export var trauma_decay := 1.6
@export var max_offset := Vector2(18.0, 12.0)
@export var arena_bounds: ArenaBoundsDef = DEFAULT_ARENA_BOUNDS

var trauma := 0.0
var noise := FastNoiseLite.new()
var noise_time := 0.0


func _ready() -> void:
	add_to_group(&"presentation_camera")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.08
	_apply_arena_limits()


func _process(delta: float) -> void:
	if is_instance_valid(Global.player) and arena_bounds != null:
		var safe_zoom := Vector2(maxf(0.001, absf(zoom.x)), maxf(0.001, absf(zoom.y)))
		var viewport_world_size := get_viewport_rect().size / safe_zoom
		global_position = arena_bounds.clamp_camera_center(
			Global.player.global_position, viewport_world_size, max_offset
		)
	elif is_instance_valid(Global.player):
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


func _apply_arena_limits() -> void:
	if arena_bounds == null:
		return
	var bounds := arena_bounds.visual_rect()
	limit_left = floori(bounds.position.x)
	limit_top = floori(bounds.position.y)
	limit_right = ceili(bounds.end.x)
	limit_bottom = ceili(bounds.end.y)
