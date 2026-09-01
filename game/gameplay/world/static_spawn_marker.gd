class_name GogoStaticSpawnMarker
extends Node2D


const DURATION_SECONDS := 0.35
const VISUAL_SCALE := 1.0
const VISUAL_MODULATE := Color(1.0, 1.0, 1.0, 0.88)
const ATLAS_CELL_SIZE := Vector2i(48, 64)
const SMALL_ENEMY_REGION := Rect2(0, 0, 48, 64)
const BOSS_REGION := Rect2(48, 0, 48, 64)

var _sprite: Sprite2D
var _timer: Timer
var _callback := Callable()
var _completed := false


func configure_visual(handle: GogoStaticAssetHandle, is_boss: bool = false) -> bool:
	if handle == null or handle.texture == null:
		return false
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "StaticVisual"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_sprite.texture = handle.texture
	_sprite.region_enabled = true
	_sprite.region_rect = BOSS_REGION if is_boss else SMALL_ENEMY_REGION
	_sprite.scale = Vector2.ONE * VISUAL_SCALE
	_sprite.position = -Vector2(ATLAS_CELL_SIZE) * 0.5 * VISUAL_SCALE
	_sprite.modulate = VISUAL_MODULATE
	GogoStaticConsumerRegistry.observe_handle(
		handle,
		"res://game/gameplay/world/static_spawn_marker.gd",
		"SpawnMarker/StaticVisual"
	)
	return true


func visual_world_rect() -> Rect2:
	if _sprite == null or _sprite.texture == null:
		return Rect2(position, Vector2.ZERO)
	var visual_size := (
		_sprite.region_rect.size if _sprite.region_enabled else Vector2(_sprite.texture.get_size())
	)
	return Rect2(
		position + _sprite.position,
		visual_size * _sprite.scale.abs()
	)


func play(next_position: Vector2, callback: Callable) -> void:
	position = next_position.round()
	_callback = callback
	_completed = false
	if _sprite == null or _sprite.texture == null:
		_complete()
		return
	if _timer == null:
		_timer = Timer.new()
		_timer.name = "ActivationDelay"
		_timer.one_shot = true
		_timer.wait_time = DURATION_SECONDS
		_timer.timeout.connect(_complete)
		add_child(_timer)
	_timer.start()


func complete_now() -> void:
	if _timer != null:
		_timer.stop()
	_complete()


func cancel() -> void:
	if _completed:
		return
	_completed = true
	_callback = Callable()
	if _timer != null:
		_timer.stop()
	queue_free()


func _complete() -> void:
	if _completed:
		return
	_completed = true
	var callback := _callback
	_callback = Callable()
	if callback.is_valid():
		callback.call()
	queue_free()
