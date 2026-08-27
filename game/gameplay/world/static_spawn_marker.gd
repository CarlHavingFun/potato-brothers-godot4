class_name GogoStaticSpawnMarker
extends Node2D


const DURATION_SECONDS := 0.35

var _sprite: Sprite2D
var _timer: Timer
var _callback := Callable()
var _completed := false


func configure_visual(handle: GogoStaticAssetHandle) -> bool:
	if handle == null or handle.texture == null:
		return false
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "StaticVisual"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_sprite.texture = handle.texture
	_sprite.position = -Vector2(handle.pivot_px)
	return true


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
